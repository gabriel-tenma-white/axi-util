library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

-- a shallow fifo for converting oxi to axi, lutram based
entity oxitoaxififo is
	generic(width: integer := 8;
			depthOrder: integer := 5);
	port(aclk: in std_logic;
		din_tstrobe: in std_logic;
		din_tready: out std_logic;
		din_tdata: in std_logic_vector(width-1 downto 0);

		dout_tvalid: out std_logic;
		dout_tready: in std_logic;
		dout_tdata: out std_logic_vector(width-1 downto 0));
end entity;
architecture a of oxiToAxiFIFO is
	attribute X_INTERFACE_PARAMETER : string;
	attribute X_INTERFACE_INFO : string;
	attribute X_INTERFACE_INFO of din_tstrobe: signal is "owocomm:interface:oxi_stream_rtl:1.0 din tstrobe";
	attribute X_INTERFACE_INFO of din_tready: signal is "owocomm:interface:oxi_stream_rtl:1.0 din tready";
	attribute X_INTERFACE_INFO of din_tdata: signal is "owocomm:interface:oxi_stream_rtl:1.0 din tdata";

	attribute X_INTERFACE_INFO of dout_tvalid: signal is "xilinx.com:interface:axis_rtl:1.0 dout tvalid";
	attribute X_INTERFACE_INFO of dout_tready: signal is "xilinx.com:interface:axis_rtl:1.0 dout tready";
	attribute X_INTERFACE_INFO of dout_tdata: signal is "xilinx.com:interface:axis_rtl:1.0 dout tdata";

	constant depth: integer := 2**depthOrder;

	signal din_tstrobe1: std_logic;
	signal din_tdata1: std_logic_vector(width-1 downto 0);
	signal wAddr, wAddrNext, rAddr, rAddrNext: unsigned(depthOrder-1 downto 0) := (others=>'0');
	signal rValid, rReady: std_logic;
	signal rData: std_logic_vector(width-1 downto 0);
	signal outCE, outCE1, outValid: std_logic;

	signal ready0: std_logic;

	type ram1_t is array(depth-1 downto 0) of std_logic_vector(width-1 downto 0);
	signal ram1: ram1_t;
	attribute ram_style : string;
	attribute ram_style of ram1 : signal is "distributed";
begin
	-- register inputs
	din_tstrobe1 <= din_tstrobe when rising_edge(aclk);
	din_tdata1 <= din_tdata when rising_edge(aclk);

	-- write side
	wAddr <= wAddr+1 when din_tstrobe='1' and rising_edge(aclk);
	process(aclk)
	begin
		if(rising_edge(aclk)) then
			ram1(to_integer(wAddr)) <= din_tdata;
		end if;
	end process;

	-- read side
	rValid <= '0' when rAddr=wAddr else '1';
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
	ready0 <= '1' when rAddr=wAddr else
				'1' when outCE1='1' else
				'0';
	din_tready <= ready0 when rising_edge(aclk);
end a;
