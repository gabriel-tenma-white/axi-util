library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

-- 2x2 transposer and shallow fifo
entity oxiToAxiBurstTransposer is
	generic(width: integer := 8;
	       depthOrder: integer := 5);
	port(aclk: in std_logic;
		din_tstrobe: in std_logic;
		din_tready: out std_logic;
		din_tdata: in std_logic_vector(width-1 downto 0);

		dout_tvalid: out std_logic;
		dout_tready: in std_logic;
		dout_tdata: out std_logic_vector(width-1 downto 0);
		doTranspose: in std_logic := '1');
end entity;
architecture a of oxiToAxiBurstTransposer is
	attribute X_INTERFACE_PARAMETER : string;
	attribute X_INTERFACE_INFO : string;
	attribute X_INTERFACE_INFO of din_tstrobe: signal is "owocomm:interface:oxi_stream_rtl:1.0 din tstrobe";
	attribute X_INTERFACE_INFO of din_tready: signal is "owocomm:interface:oxi_stream_rtl:1.0 din tready";
	attribute X_INTERFACE_INFO of din_tdata: signal is "owocomm:interface:oxi_stream_rtl:1.0 din tdata";
	--attribute X_INTERFACE_INFO of din_tuser: signal is "owocomm:interface:oxi_stream_rtl:1.0 din tuser";

	attribute X_INTERFACE_INFO of dout_tvalid: signal is "xilinx.com:interface:axis_rtl:1.0 dout tvalid";
	attribute X_INTERFACE_INFO of dout_tready: signal is "xilinx.com:interface:axis_rtl:1.0 dout tready";
	attribute X_INTERFACE_INFO of dout_tdata: signal is "xilinx.com:interface:axis_rtl:1.0 dout tdata";
	--attribute X_INTERFACE_INFO of dout_tuser: signal is "xilinx.com:interface:axis_rtl:1.0 dout tuser";

	constant depth: integer := 2**depthOrder;
	constant blockOrder: integer := 2;

	signal din_tstrobe1: std_logic;
	signal din_tdata1: std_logic_vector(width-1 downto 0);
	signal wAddr, wAddrPermuted, rdWAddr, rAddr, rAddrNext: unsigned(depthOrder-1 downto 0) := (others=>'0');
	signal rValid, rReady: std_logic;
	signal rData: std_logic_vector(width-1 downto 0);
	signal outCE, outCE1, outValid: std_logic;

	signal doTranspose1: std_logic;

	signal ready0: std_logic;

	type ram1_t is array(depth-1 downto 0) of std_logic_vector(width-1 downto 0);
	signal ram1: ram1_t;
	attribute ram_style : string;
	attribute ram_style of ram1 : signal is "distributed";
begin
	-- register inputs
	din_tstrobe1 <= din_tstrobe when rising_edge(aclk);
	din_tdata1 <= din_tdata when rising_edge(aclk);
	doTranspose1 <= doTranspose when rising_edge(aclk);

	-- write side
	wAddr <= wAddr+1 when din_tstrobe='1' and rising_edge(aclk);
	wAddrPermuted <= wAddr when doTranspose='0' else
					wAddr(wAddr'left downto blockOrder) & wAddr(0) & wAddr(1);
	process(aclk)
	begin
		if(rising_edge(aclk)) then
			ram1(to_integer(wAddrPermuted)) <= din_tdata;
		end if;
	end process;

	-- read side
	-- round down to the nearest block size
	rdWAddr <= wAddr(wAddr'left downto blockOrder) & (blockOrder-1 downto 0=>'0');
	rValid <= '0' when rAddr=rdWAddr else '1';
	rAddrNext <= rAddr+1 when rValid='1' and rReady='1' else rAddr;
	rAddr <= rAddrNext when rising_edge(aclk);
	rData <= ram1(to_integer(rAddr));

	-- output register
	dout_tvalid <= outValid;
	outValid <= rValid when outCE='1' and rising_edge(aclk);
	dout_tdata <= rData when outCE='1' and rising_edge(aclk);
	outCE <= (not outValid) or dout_tready;
	rReady <= outCE;

	-- flow control
	outCE1 <= outCE when rising_edge(aclk);
	ready0 <= '1' when rAddr=rdWAddr else
				'1' when rAddr(rAddr'left downto blockOrder)+1 = wAddr(wAddr'left downto blockOrder) else
				'1' when outCE1='1' else
				'0';
	din_tready <= ready0 when rising_edge(aclk);
end a;

library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.oxiToAxiBurstTransposer;

-- 2x2 transposer
entity axiBurstTransposer is
	generic(width: integer := 8;
			tuserWidth: integer := 1;
			doTransposeFlagNum: integer := 0);
	port(aclk: in std_logic;
		din_tvalid: in std_logic;
		din_tready: out std_logic;
		din_tdata: in std_logic_vector(width-1 downto 0);
		din_tuser: in std_logic_vector(tuserWidth-1 downto 0) := (others=>'1');

		dout_tvalid: out std_logic;
		dout_tready: in std_logic;
		dout_tdata: out std_logic_vector(width-1 downto 0);
		dout_tuser: out std_logic_vector(tuserWidth-1 downto 0));
end entity;
architecture a of axiBurstTransposer is
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
	signal i_tstrobe, i_tready, i_tready1, i_doTranspose: std_logic;
	signal i_tdata, o_tdata: std_logic_vector(width+tuserWidth-1 downto 0);
begin
	-- convert axi to oxi
	i_tdata <= din_tuser & din_tdata when rising_edge(aclk);
	i_doTranspose <= din_tuser(doTransposeFlagNum) when rising_edge(aclk);
	i_tstrobe <= din_tvalid and i_tready1 when rising_edge(aclk);
	i_tready1 <= i_tready when rising_edge(aclk);
	din_tready <= i_tready1;

	inst: entity oxiToAxiBurstTransposer
		generic map(width=>width+tuserWidth)
		port map(aclk=>aclk,
			din_tstrobe=>i_tstrobe, din_tready=>i_tready, din_tdata=>i_tdata,
			doTranspose=>i_doTranspose,
			dout_tvalid=>dout_tvalid, dout_tready=>dout_tready, dout_tdata=>o_tdata);

	dout_tdata <= o_tdata(dout_tdata'range);
	dout_tuser <= o_tdata(o_tdata'left downto dout_tdata'length);
end a;

