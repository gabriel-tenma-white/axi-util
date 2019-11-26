library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.dcfifo;
entity dcfifoWrapper_tlast is
	generic(width: integer := 8;
				depthOrder: integer := 9);
	port(rd_aclk,wr_aclk: in std_logic;
			
			-- read side; synchronous to rdclk
			rd_tvalid: out std_logic;
			rd_tready: in std_logic;
			rd_tdata: out std_logic_vector(width-1 downto 0);
			rd_tlast: out std_logic;
			
			--write side; synchronous to wrclk
			wr_tvalid: in std_logic;
			wr_tready: out std_logic;
			wr_tdata: in std_logic_vector(width-1 downto 0);
			wr_tlast: in std_logic;
			
			-- how many input words are left to be read
			rdleft: out unsigned(depthOrder-1 downto 0);
			
			-- how much space is available in the queue, in output words
			wrroom: out unsigned(depthOrder-1 downto 0)
			);
end entity;

architecture a of dcfifoWrapper_tlast is
    attribute X_INTERFACE_INFO : string;
	attribute X_INTERFACE_INFO of wr_tvalid: signal is "xilinx.com:interface:axis_rtl:1.0 wr tvalid";
	attribute X_INTERFACE_INFO of wr_tready: signal is "xilinx.com:interface:axis_rtl:1.0 wr tready";
	attribute X_INTERFACE_INFO of wr_tdata: signal is "xilinx.com:interface:axis_rtl:1.0 wr tdata";
	attribute X_INTERFACE_INFO of wr_tlast: signal is "xilinx.com:interface:axis_rtl:1.0 wr tlast";
	attribute X_INTERFACE_INFO of rd_tvalid: signal is "xilinx.com:interface:axis_rtl:1.0 rd tvalid";
	attribute X_INTERFACE_INFO of rd_tready: signal is "xilinx.com:interface:axis_rtl:1.0 rd tready";
	attribute X_INTERFACE_INFO of rd_tdata: signal is "xilinx.com:interface:axis_rtl:1.0 rd tdata";
	attribute X_INTERFACE_INFO of rd_tlast: signal is "xilinx.com:interface:axis_rtl:1.0 rd tlast";
	signal din, dout: std_logic_vector(width downto 0);
begin
	fifo: entity dcfifo
		generic map(width=>width+1, depthOrder=>depthOrder)
		port map(rdclk=>rd_aclk, wrclk=>wr_aclk,
			rdvalid=>rd_tvalid, rdready=>rd_tready, rddata=>dout,
			wrvalid=>wr_tvalid, wrready=>wr_tready, wrdata=>din,
			rdleft=>rdleft, wrroom=>wrroom);
	din(wr_tdata'range) <= wr_tdata;
	din(din'left) <= wr_tlast;
	rd_tlast <= dout(dout'left);
	rd_tdata <= dout(rd_tdata'range);
end a;

