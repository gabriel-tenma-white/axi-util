
library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

entity axiTransposerAddrPerm is
	generic(rowsOrder, colsOrder, repPeriodOrder: integer);
	port(
			aclk, ce: in std_logic;
			bitPermIn: in unsigned(rowsOrder+colsOrder-1 downto 0);
			bitPermCount: in unsigned(repPeriodOrder-1 downto 0);
			bitPermOut: out unsigned(rowsOrder+colsOrder-1 downto 0));
end entity;

architecture a of axiTransposerAddrPerm is
	constant depthOrder: integer := rowsOrder+colsOrder;
	type addrStages_t is array(repPeriodOrder downto 0) of unsigned(depthOrder-1 downto 0);
	signal addrStages: addrStages_t;
begin

g1: for I in 0 to repPeriodOrder-1 generate
		addrStages(I+1) <= addrStages(I) when bitPermCount(I)='0' else
							rotate_left(addrStages(I), colsOrder * (2**I));
	end generate;
	addrStages(0) <= bitPermIn;
	bitPermOut <= addrStages(repPeriodOrder) when ce='1' and rising_edge(aclk);
end a;


library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.axiReorderBuffer;
use work.axiReorderBuffer_types.all;
use work.axiTransposerAddrPerm;

entity axiTransposer is
	-- rowsOrder and colsOrder are as viewed from the input side
	-- (colsOrder is the minor size and rowsOrder the major size)
	-- unless swapRowColSize is '1'
	generic(wordWidth: integer := 8;
			tuserWidth: integer := 2;
			doTransposeFlagNum: integer := 0;
			swapRowColSizeFlagNum: integer := 1;
			rowsOrder, colsOrder: integer);
	port(
			aclk, reset: in std_logic;

		-- axi stream input
			din_tvalid: in std_logic;
			din_tready: out std_logic;
			din_tdata: in std_logic_vector(wordWidth-1 downto 0);
			din_tuser: in std_logic_vector(tuserWidth-1 downto 0) := (0=>'1', 1=>'0', others=>'0');
			din_tlast: in std_logic := '0';

		-- axi stream output
			dout_tvalid: out std_logic;
			dout_tready: in std_logic;
			dout_tdata: out std_logic_vector(wordWidth-1 downto 0);
			dout_tuser: out std_logic_vector(tuserWidth-1 downto 0);
			dout_tlast: out std_logic
		);
end entity;
architecture a of axiTransposer is
	attribute X_INTERFACE_PARAMETER : string;
	attribute X_INTERFACE_PARAMETER of aclk: signal is "ASSOCIATED_BUSIF din:dout";
	attribute X_INTERFACE_INFO : string;
	attribute X_INTERFACE_INFO of din_tvalid: signal is "xilinx.com:interface:axis_rtl:1.0 din tvalid";
	attribute X_INTERFACE_INFO of din_tready: signal is "xilinx.com:interface:axis_rtl:1.0 din tready";
	attribute X_INTERFACE_INFO of din_tdata: signal is "xilinx.com:interface:axis_rtl:1.0 din tdata";
	attribute X_INTERFACE_INFO of din_tuser: signal is "xilinx.com:interface:axis_rtl:1.0 din tuser";
	attribute X_INTERFACE_INFO of din_tlast: signal is "xilinx.com:interface:axis_rtl:1.0 din tlast";
	attribute X_INTERFACE_INFO of dout_tvalid: signal is "xilinx.com:interface:axis_rtl:1.0 dout tvalid";
	attribute X_INTERFACE_INFO of dout_tready: signal is "xilinx.com:interface:axis_rtl:1.0 dout tready";
	attribute X_INTERFACE_INFO of dout_tdata: signal is "xilinx.com:interface:axis_rtl:1.0 dout tdata";
	attribute X_INTERFACE_INFO of dout_tuser: signal is "xilinx.com:interface:axis_rtl:1.0 dout tuser";
	attribute X_INTERFACE_INFO of dout_tlast: signal is "xilinx.com:interface:axis_rtl:1.0 dout tlast";

	constant depthOrder: integer := rowsOrder+colsOrder;
	constant repPeriod: integer := depthOrder;
	constant repPeriodOrder: integer := ceilLog2(depthOrder);

	signal doTranspose1, swapRowColSize1: std_logic;

	signal bitPermIn0, bitPermIn1: unsigned(depthOrder-1 downto 0);
	signal bitPermCount0, bitPermCount1: unsigned(repPeriodOrder-1 downto 0);
	signal bitPermOut0, bitPermOut1: unsigned(depthOrder-1 downto 0);
	signal bitPermCE0, bitPermCE1: std_logic;
begin
	doTranspose1 <= din_tuser(doTransposeFlagNum);
	swapRowColSize1 <= din_tuser(swapRowColSizeFlagNum);


	rb: entity axiReorderBuffer
		generic map(wordWidth=>wordWidth, tuserWidth=>tuserWidth,
					depthOrder=>depthOrder, repPeriod=>repPeriod, addrPermDelay=>1)
		port map(aclk=>aclk, reset=>reset,
			din_tvalid=>din_tvalid, din_tready=>din_tready,
			din_tdata=>din_tdata, din_tuser=>din_tuser, din_tlast=>din_tlast,
			dout_tvalid=>dout_tvalid, dout_tready=>dout_tready,
			dout_tdata=>dout_tdata, dout_tuser=>dout_tuser, dout_tlast=>dout_tlast,

			bitPermIn0=>bitPermIn0, bitPermIn1=>bitPermIn1,
			bitPermCount0=>bitPermCount0, bitPermCount1=>bitPermCount1,
			bitPermOut0=>bitPermOut0, bitPermOut1=>bitPermOut1,
			bitPermCE0=>bitPermCE0, bitPermCE1=>bitPermCE1,

			doReorder=>doTranspose1, bitPermInverse=>swapRowColSize1);

	bitPerm0: entity axiTransposerAddrPerm
		generic map(rowsOrder=>rowsOrder, colsOrder=>colsOrder, repPeriodOrder=>repPeriodOrder)
		port map(aclk=>aclk, ce=>bitPermCE0,
				bitPermIn=>bitPermIn0, bitPermCount=>bitPermCount0, bitPermOut=>bitPermOut0);

	bitPerm1: entity axiTransposerAddrPerm
		generic map(rowsOrder=>rowsOrder, colsOrder=>colsOrder, repPeriodOrder=>repPeriodOrder)
		port map(aclk=>aclk, ce=>bitPermCE1,
				bitPermIn=>bitPermIn1, bitPermCount=>bitPermCount1, bitPermOut=>bitPermOut1);
end a;

