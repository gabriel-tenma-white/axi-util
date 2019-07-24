library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

-- a shallow fifo for converting oxi to axi, SRL16 based
entity oxiToAxiSkid is
	generic(width: integer := 8;
			depthOrder: integer := 4);
	port(aclk: in std_logic;
		din_tstrobe: in std_logic;
		din_tready: out std_logic;
		din_tdata: in std_logic_vector(width-1 downto 0);

		dout_tvalid: out std_logic;
		dout_tready: in std_logic;
		dout_tdata: out std_logic_vector(width-1 downto 0));
end entity;
architecture a of oxiToAxiSkid is
	constant depth: integer := 2**depthOrder;

	signal din_tstrobe1: std_logic;
	signal din_tdata1: std_logic_vector(width-1 downto 0);
	
	signal cnt, cntNext: unsigned(depthOrder-1 downto 0) := (others=>'1');
	constant cntEmpty: unsigned(depthOrder-1 downto 0) := (others=>'1');
	
	signal rValid, rReady: std_logic;
	signal rData: std_logic_vector(width-1 downto 0);
	signal outCE, outCE1, outValid: std_logic;

	signal ready0: std_logic;

	type sr1_t is array(depth-1 downto 0) of std_logic_vector(width-1 downto 0);
	signal sr1: sr1_t;
begin
	-- register inputs
	din_tstrobe1 <= din_tstrobe when rising_edge(aclk);
	din_tdata1 <= din_tdata when rising_edge(aclk);

	-- write side
	sr1 <= sr1(sr1'left-1 downto 0) & din_tdata1 when din_tstrobe1='1' and rising_edge(aclk);

	-- read side
	cnt <= cntNext when rising_edge(aclk);
	cntNext <= cnt+1 when din_tstrobe1='1' and (rReady='0' or cnt=cntEmpty) else
				cnt-1 when cnt /= cntEmpty and din_tstrobe1='0' and rReady='1' else
				cnt;
	rValid <= '1' when cnt /= cntEmpty else
				'0';
	rData <= sr1(to_integer(cnt));

	-- output register
	dout_tvalid <= outValid;
	outValid <= rValid when outCE='1' and rising_edge(aclk);
	dout_tdata <= rData when outCE='1' and rising_edge(aclk);
	outCE <= (not outValid) or dout_tready;
	rReady <= outCE;

	-- flow control
	outCE1 <= outCE when rising_edge(aclk);
	ready0 <= '1' when cnt=0 else
				'1' when outCE1='1' else
				'0';
	din_tready <= ready0 when rising_edge(aclk);
end a;
