
library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

-- connect axi stream source to oxi stream sink
entity axiToOxi is
	generic(width: integer := 8);
	port(aclk: in std_logic;
		din_tvalid: in std_logic;
		din_tready: out std_logic;
		din_tdata: in std_logic_vector(width-1 downto 0);

		dout_tstrobe: out std_logic;
		dout_tready: in std_logic;
		dout_tdata: out std_logic_vector(width-1 downto 0));
end entity;
architecture a of axiToOxi is
	attribute X_INTERFACE_INFO : string;
	attribute X_INTERFACE_INFO of din_tvalid: signal is "xilinx.com:interface:axis_rtl:1.0 din tvalid";
	attribute X_INTERFACE_INFO of din_tready: signal is "xilinx.com:interface:axis_rtl:1.0 din tready";
	attribute X_INTERFACE_INFO of din_tdata: signal is "xilinx.com:interface:axis_rtl:1.0 din tdata";
	attribute X_INTERFACE_INFO of dout_tstrobe: signal is "owocomm:interface:oxi_stream_rtl:1.0 dout tstrobe";
	attribute X_INTERFACE_INFO of dout_tready: signal is "owocomm:interface:oxi_stream_rtl:1.0 dout tready";
	attribute X_INTERFACE_INFO of dout_tdata: signal is "owocomm:interface:oxi_stream_rtl:1.0 dout tdata";
	signal i_tstrobe, i_tready, i_tready1: std_logic;
	signal i_tdata: std_logic_vector(width-1 downto 0);
begin
	-- convert axi to oxi
	i_tdata <= din_tdata when rising_edge(aclk);
	i_tstrobe <= din_tvalid and i_tready1 when rising_edge(aclk);
	i_tready1 <= i_tready when rising_edge(aclk);
	din_tready <= i_tready1;

	dout_tstrobe <= i_tstrobe;
	i_tready <= dout_tready;
	dout_tdata <= i_tdata;
end a;
