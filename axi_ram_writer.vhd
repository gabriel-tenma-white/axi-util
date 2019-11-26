library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

entity axiramwriter is
	generic(memAddrWidth: integer := 8;
			wordWidth: integer := 32);
	port(
		--axi memory mapped slave, read side
			aclk,rst: in std_logic;
			arready: out std_logic;
			arvalid: in std_logic;
			araddr: in std_logic_vector(memAddrWidth-1 downto 0);
			arprot: in std_logic_vector(2 downto 0);
			
			rvalid: out std_logic;
			rready: in std_logic;
			rdata: out std_logic_vector(wordWidth-1 downto 0);
		
		--axi memory mapped slave, write side
			awaddr: in std_logic_vector(memAddrWidth-1 downto 0);
			awprot: in std_logic_vector(2 downto 0);
			awvalid: in std_logic;
			awready: out std_logic;
			wdata: in std_logic_vector(wordWidth-1 downto 0);
			wvalid: in std_logic;
			wready: out std_logic;
			
			bvalid: out std_logic;
			bready: in std_logic;
			bresp: out std_logic_vector(1 downto 0);
		
		-- ram write out
			ramWAddr: out unsigned(memAddrWidth-1 downto 0);
			ramWData: out std_logic_vector(wordWidth-1 downto 0);
			ramWEn: out std_logic
		);
end entity;

architecture a of axiRamWriter is
	constant addrBitsInternal: integer := memAddrWidth;
	
	signal canWrite, willWrite, willWrite1: std_logic;
	signal waddrInternal,waddrInternal1: unsigned(addrBitsInternal-1 downto 0);
	signal wdata1: std_logic_vector(wordWidth-1 downto 0);
begin
	-- accept writes only when data is present on both address and data bus
	canWrite <= awvalid and wvalid;
	willWrite <= canWrite and bready;
	awready <= willWrite;
	wready <= willWrite;
	
	-- latch all write info
	waddrInternal <= resize(unsigned(awaddr(awaddr'left downto 2)), addrBitsInternal);
	waddrInternal1 <= waddrInternal when rising_edge(aclk);
	willWrite1 <= willWrite when rising_edge(aclk);
	wdata1 <= wdata when rising_edge(aclk);
	
	-- perform writes
	ramWEn <= willWrite1;
	ramWAddr <= waddrInternal1;
	ramWData <= wdata1;

	
	-- issue write response
	bvalid <= canWrite;
	bresp <= "00";

	arready <= '0';
	rvalid <= '0';
end a;



