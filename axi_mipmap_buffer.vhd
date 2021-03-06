library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.axiMipmap_types.all;
use work.dcram;

entity axiMipmap_buffer is
	generic(channels, depthOrder: integer);
	port(
			aclk, reset: in std_logic;
			in_tdata: in minMaxArray(channels-1 downto 0);
			in_tstrobe, in_tlast: in std_logic;
			
			out_tdata: out minMaxArray(channels-1 downto 0);
			out_tvalid, out_tlast: out std_logic;
			out_tready: in std_logic
		);
end entity;
architecture a of axiMipmap_buffer is
	constant ramWidth: integer := channels*minMaxWidth*2;
	constant depth: integer := 2**depthOrder;
	signal reset1: std_logic;
	signal raddr, raddrNext, raddrM1, waddr, waddrNext, waddrPrev: unsigned(depthOrder downto 0) := (others=>'0');
	signal rdata, wdata: std_logic_vector(ramWidth-1 downto 0);
	signal wvalid, wlast: std_logic;

	signal outputRunning, outputRunning1, outputRunningNext: std_logic := '0';
	signal trigger, triggerPrev, triggerNext: std_logic;
	signal outputStop, outputStop0, outputStop0Next: std_logic := '0';
	signal outputCE: std_logic;

	-- tlast handling
	signal wAdvance, rAdvance, inLast, inLast1, inLastPrev, currFrameIsLast, outLast0: std_logic;
begin
	reset1 <= reset when rising_edge(aclk);

	ram: entity dcram
		generic map(width=>ramWidth, depthOrder=>depthOrder+1,
					outputRegistered=>false, ramType=>2)
		port map(rdclk=>aclk, wrclk=>aclk,
				rden=>outputCE, rdaddr=>raddr, rddata=>rdata,
				wren=>wvalid, wraddr=>waddr, wrdata=>wdata);

	-- unpack input data
g1: for I in 0 to channels-1 generate
		wdata((I+1)*minMaxWidth*2-1 downto I*minMaxWidth*2) <=
				std_logic_vector(in_tdata(I).upper & in_tdata(I).lower);
	end generate;
	wvalid <= in_tstrobe;
	--wlast <= in_tlast;

	-- increment counter
	waddrNext <= (others=>'0') when reset1='1' else
	           (not waddr(waddr'left)) & (waddr'left-1 downto 0=>'0') when wvalid='1' and wlast='1' else
	           waddr+1 when wvalid='1' else
	           waddr;
	waddr <= waddrNext when rising_edge(aclk);
	waddrPrev <= waddr when rising_edge(aclk);

	-- start output when counter reaches two thresholds
	triggerNext <=
			'1' when waddr = 0     and raddr(raddr'left)='1' else
			'1' when waddr = depth and raddr(raddr'left)='0' else
			'0';
	trigger <= triggerNext when rising_edge(aclk);
	triggerPrev <= trigger when rising_edge(aclk);

	outputRunningNext <=
			'0' when reset1='1' else
			'0' when outputStop='1' else
			'1' when trigger='1' and triggerPrev='0' else
			outputRunning;
	outputRunning <= outputRunningNext when rising_edge(aclk);

	raddrNext <= (others=>'0') when reset1='1' else
	           raddr + 1 when outputRunning='1' and outputCE='1' else
	           raddr;
	raddr <= raddrNext when rising_edge(aclk);
	raddrM1 <= raddr when outputCE='1' and rising_edge(aclk);

	-- outputStop0 is true when rdaddr = depth-1.
	-- outputStop is true if we will stop incrementing read address next cycle.
	outputStop0Next <= '1' when raddr(raddr'left-1 downto 0) = (depth-2) else '0';
	outputStop0 <= outputStop0Next when outputCE='1' and rising_edge(aclk);
	outputStop <= outputStop0 and outputCE;

	-- outputCE controls whether the output pipeline (the portion from raddr to out_tdata)
	-- should advance.
	outputRunning1 <= outputRunning when outputCE='1' and rising_edge(aclk);
	--outputRunning2 <= outputRunning1 when outputCE='1' and rising_edge(aclk);
	out_tvalid <= outputRunning1;

	outputCE <= out_tready or not outputRunning1;

	-- output data
g2: for I in 0 to channels-1 generate
		out_tdata(I).upper <= signed(rdata((I+1)*minMaxWidth*2-1 downto I*minMaxWidth*2+minMaxWidth));
		out_tdata(I).lower <= signed(rdata((I+1)*minMaxWidth*2-minMaxWidth-1 downto I*minMaxWidth*2));
	end generate;


	-- tlast logic
	inLast <= in_tstrobe and in_tlast;
	inLast1 <= inLast when rising_edge(aclk);
	wAdvance <= '1' when waddr(waddr'left) /= waddrPrev(waddr'left) else '0';
	rAdvance <= '1' when raddr(rAddr'left) /= raddrM1(raddr'left) else '0';
	currFrameIsLast <= inLast1 when wAdvance='1' and rising_edge(aclk);
	outLast0 <= currFrameIsLast and rAdvance;
	out_tlast <= outLast0;
end a;
