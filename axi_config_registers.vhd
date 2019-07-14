library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
package axiConfigRegisters_types is
	type regdata_t is array(integer range<>) of std_logic_vector(31 downto 0);
end package;

library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
USE ieee.math_real.log2;
USE ieee.math_real.ceil;
use work.axiConfigRegisters_types.all;
entity axiConfigRegisters is
	generic(nWords: integer := 8;
			memAddrWidth: integer := 8;
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
		
		-- register data
			regdata: out regdata_t(nWords-1 downto 0);
			regdataIn: in regdata_t(nWords-1 downto 0)
		);
end entity;

architecture a of axiConfigRegisters is
	constant addrBitsInternal: integer := integer(ceil(log2(real(nWords))));
	
	signal canWrite, willWrite, willWrite1: std_logic;
	signal waddrInternal,waddrInternal1: unsigned(addrBitsInternal-1 downto 0);
	signal wdata1: std_logic_vector(wordWidth-1 downto 0);
	
	signal willRead,rvalid0,rpipeEnable: std_logic;
	signal raddrInternal: unsigned(addrBitsInternal-1 downto 0);
	
	signal registers,registersIn: regdata_t(nWords-1 downto 0) := (others=>(others=>'0'));
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
g1:	for I in 0 to nWords-1 generate
		registers(I) <= wdata1 when waddrInternal1=I and willWrite1='1' and rising_edge(aclk);
		--registers(I) <= (others=>'0') when rst='1' and rising_edge(aclk);
	end generate;
	
	-- issue write response
	bvalid <= canWrite;
	bresp <= "00";
	
	
	-- accept reads only when rready is 1
	arready <= rready;
	
	rpipeEnable <= '1' when rready='1' or rvalid0='0' else '0';
	
	willRead <= arvalid when rpipeEnable='1' and rising_edge(aclk);
	raddrInternal <= resize(unsigned(araddr(araddr'left downto 2)), addrBitsInternal) when rpipeEnable='1' and rising_edge(aclk);
	
	rdata <= registersIn(to_integer(raddrInternal)) when rpipeEnable='1' and rising_edge(aclk);
	rvalid0 <= willRead when rpipeEnable='1' and rising_edge(aclk);
	
	rvalid <= rvalid0;
	
	-- output/input register data
	regdata <= registers;
	registersIn <= regdataIn;

end a;



