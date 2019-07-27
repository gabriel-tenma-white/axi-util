
library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

package axiReorderBuffer_types is
	function ceilLog2(val: integer) return integer;
end package;

package body axiReorderBuffer_types is
	function ceilLog2(val: integer) return integer is
		variable tmp: integer;
	begin
		for I in 0 to 32 loop
			tmp := 2**I;
			if tmp >= val then
				return I;
			end if;
		end loop;
		return -1;
	end function;
end package body;

library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.axiReorderBuffer_types.all;
use work.dcram;
use work.sr;
use work.sr_bit;
use work.sr_unsigned;

entity axiReorderBuffer is
	generic(wordWidth, tuserWidth: integer;
			depthOrder: integer;
			repPeriod: integer;
			addrPermDelay: integer := 0);
	port(
			aclk, reset: in std_logic;

		-- axi stream input
			din_tvalid: in std_logic;
			din_tready: out std_logic;
			din_tdata: in std_logic_vector(wordWidth-1 downto 0);
			din_tuser: in std_logic_vector(tuserWidth-1 downto 0);

		-- axi stream output
			dout_tvalid: out std_logic;
			dout_tready: in std_logic;
			dout_tdata: out std_logic_vector(wordWidth-1 downto 0);
			dout_tuser: out std_logic_vector(tuserWidth-1 downto 0);

		-- external bit permutor
			bitPermIn0, bitPermIn1: out unsigned(depthOrder-1 downto 0);
			bitPermCount0, bitPermCount1: out unsigned(ceilLog2(repPeriod)-1 downto 0);
			bitPermOut0, bitPermOut1: in unsigned(depthOrder-1 downto 0);
			bitPermCE0, bitPermCE1: out std_logic;

		-- whether to decrement the bitPermCount counter instead of incrementing
			bitPermInverse: in std_logic := '0';

		-- whether to reorder the current input frame
			doReorder: in std_logic := '1'
		);
end entity;
architecture a of axiReorderBuffer is
	attribute X_INTERFACE_PARAMETER : string;
	attribute X_INTERFACE_PARAMETER of aclk: signal is "ASSOCIATED_BUSIF din:dout";
	attribute X_INTERFACE_INFO : string;
	attribute X_INTERFACE_INFO of din_tvalid: signal is "xilinx.com:interface:axis_rtl:1.0 din tvalid";
	attribute X_INTERFACE_INFO of din_tready: signal is "xilinx.com:interface:axis_rtl:1.0 din tready";
	attribute X_INTERFACE_INFO of din_tdata: signal is "xilinx.com:interface:axis_rtl:1.0 din tdata";
	attribute X_INTERFACE_INFO of din_tuser: signal is "xilinx.com:interface:axis_rtl:1.0 din tuser";
	attribute X_INTERFACE_INFO of dout_tvalid: signal is "xilinx.com:interface:axis_rtl:1.0 dout tvalid";
	attribute X_INTERFACE_INFO of dout_tready: signal is "xilinx.com:interface:axis_rtl:1.0 dout tready";
	attribute X_INTERFACE_INFO of dout_tdata: signal is "xilinx.com:interface:axis_rtl:1.0 dout tdata";
	attribute X_INTERFACE_INFO of dout_tuser: signal is "xilinx.com:interface:axis_rtl:1.0 dout tuser";


	-- write side
	-- counters are (depthOrder+1) bits because we need to distinguish "full" from 0.
	signal wAddr, wAddrNext, wAddrPrev: unsigned(depthOrder downto 0) := (others=>'0');
	signal wAddrUpper: unsigned(1 downto 0);
	signal wData: std_logic_vector(wordWidth-1 downto 0);
	signal wIncrement, wReady, wEnable, wEnable0: std_logic;
	signal tuser1: std_logic_vector(tuserWidth-1 downto 0);
	signal sampleFlags0, sampleFlags1, sampleFlags2: std_logic;
	
	-- read side
	signal rAddr, rAddrNext, rAddrPermuted, rAddrPrev: unsigned(depthOrder downto 0)
			:= (depthOrder=>'1', others=>'0');
	signal rIncrement, outCE: std_logic;
	signal rValid, outValid: std_logic;

	-- generation counter
	constant generationOrder: integer := ceilLog2(repPeriod);
	signal generation, generationNext: unsigned(generationOrder-1 downto 0) := (others=>'0');

	-- generation control logic
	signal done, done1, done2, donePulse: std_logic := '0';
	signal incrementGeneration, bitPermInverse1, doReorder1: std_logic;
begin

	-- write side
	wReady <= '0' when wAddr=rAddrPrev else '1';
	din_tready <= wReady;
	wIncrement <= din_tvalid and wReady;
	wAddrNext <= wAddr+1 when wIncrement='1' else
				wAddr;
	wAddr <= wAddrNext when rising_edge(aclk);
	wAddrPrev <= wAddr when rising_edge(aclk);
	bitPermCE0 <= '1';
	bitPermIn0 <= wAddr(depthOrder-1 downto 0);
	bitPermCount0 <= generation;
	wEnable0 <= wIncrement;
	sr_wData: entity sr
		generic map(bits=>wordWidth, len=>addrPermDelay)
		port map(clk=>aclk, din=>din_tdata, dout=>wData);
	sr_wEnable: entity sr_bit
		generic map(len=>addrPermDelay)
		port map(clk=>aclk, din=>wEnable0, dout=>wEnable);

	-- read side
	rValid <= '1' when rAddr(rAddr'left)=wAddrPrev(wAddr'left) else '0';
	sr_outValid: entity sr_bit
		generic map(len=>addrPermDelay+2)
		port map(clk=>aclk, din=>rValid, dout=>outValid, ce=>outCE);
	dout_tvalid <= outValid;

	outCE <= dout_tready or (not outValid);
	rIncrement <= rValid and outCE;

	rAddrNext <= rAddr+1 when rIncrement='1' else
				rAddr;
	rAddr <= rAddrNext when rising_edge(aclk);
	sr_rAddrPrev: entity sr_unsigned
		generic map(bits=>rAddr'length, len=>addrPermDelay+1)
		port map(clk=>aclk, din=>rAddr, dout=>rAddrPrev, ce=>outCE);

	bitPermCE1 <= outCE;
	bitPermIn1 <= rAddr(depthOrder-1 downto 0);
	bitPermCount1 <= generation;

	-- ram
	ram: entity dcram
		generic map(width=>wordWidth, depthOrder=>depthOrder,
					outputRegistered=>true)
		port map(rdclk=>aclk, wrclk=>aclk,
				rden=>outCE, rdaddr=>bitPermOut1, rddata=>dout_tdata,
				wren=>wEnable, wraddr=>bitPermOut0, wrdata=>wData);

	-- generation counter
	wAddrUpper <= wAddr(wAddr'left-1 downto wAddr'left-2);
	sampleFlags0 <= '1' when wAddrUpper="10" else '0';
	sampleFlags1 <= sampleFlags0 when rising_edge(aclk);
	sampleFlags2 <= sampleFlags1 and din_tvalid;

	bitPermInverse1 <= bitPermInverse when sampleFlags2='1' and rising_edge(aclk);
	doReorder1 <= doReorder when sampleFlags2='1' and rising_edge(aclk);
	tuser1 <= din_tuser when sampleFlags2='1' and rising_edge(aclk);
	dout_tuser <= tuser1 when rAddr(depthOrder-1 downto 0)=(1+addrPermDelay) and rising_edge(aclk);

	generationNext <= to_unsigned(0, generation'length) when bitPermInverse1='0' and generation=(repPeriod-1) else
						generation+1 when bitPermInverse1='0' else
						to_unsigned(repPeriod-1, generation'length) when bitPermInverse1='1' and generation=0 else
						generation-1;
	generation <= generationNext when incrementGeneration='1' and doReorder1='1' and rising_edge(aclk);

	-- increment generation & reset counters when a frame is done
	done <= wAddr(wAddr'left);
	done1 <= done when rising_edge(aclk);
	done2 <= done1 when rising_edge(aclk);
	donePulse <= done xor done1 when rising_edge(aclk);

	incrementGeneration <= donePulse;
end a;

