library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
USE ieee.math_real.log2;
USE ieee.math_real.ceil;
use work.dcfifo;

-- to be used in conjunction with axi_config_registers, 
-- as a listener on the bus
entity axiMMFIFO is
	generic(memAddrWidth: integer := 8;
			wordWidth: integer := 32;
			myAddress: integer := 123; -- in words, not bytes
			depthOrder: integer := 4);
	port(
		--axi memory mapped slave, write side
			aclk: in std_logic;
			awaddr: in std_logic_vector(memAddrWidth-1 downto 0);
			awvalid,awready: in std_logic;
			wdata: in std_logic_vector(wordWidth-1 downto 0);
			wvalid,wready: in std_logic;
			wrroom: out unsigned(wordWidth-1 downto 0);
			
			fifoOut_clk: in std_logic;
			fifoOut_tready: in std_logic;
			fifoOut_tvalid: out std_logic;
			fifoOut_tdata: out std_logic_vector(wordWidth-1 downto 0)
		);
end entity;

architecture a of axiMMFIFO is
	constant myAddress_bytes: integer := myAddress*wordWidth/8;
	signal willWrite,willWrite1,willWrite2,willWrite2Next: std_logic;
	signal awaddr1: std_logic_vector(memAddrWidth-1 downto 0);
	signal wdata1,wdata2: std_logic_vector(wordWidth-1 downto 0);
	signal wrroom0: unsigned(depthOrder-1 downto 0);
begin
	awaddr1 <= awaddr when rising_edge(aclk);
	wdata1 <= wdata when rising_edge(aclk);
	wdata2 <= wdata1 when rising_edge(aclk);
	
	willWrite <= awvalid and wvalid and awready and wready;
	willWrite1 <= willWrite when rising_edge(aclk);
	willWrite2Next <= '1' when willWrite1='1' and unsigned(awaddr1)=myAddress_bytes else '0';
	willWrite2 <= willWrite2Next when rising_edge(aclk);
	
	fifo1: entity dcfifo generic map(width=>wordWidth, depthOrder=>depthOrder)
		port map(rdclk=>fifoOut_clk, wrclk=>aclk,
			rdvalid=>fifoOut_tvalid, rdready=>fifoOut_tready, rddata=>fifoOut_tdata,
			wrvalid=>willWrite2, wrready=>open, wrdata=>wdata2, wrroom=>wrroom0);
	wrroom <= resize(wrroom0, 32);
end a;



