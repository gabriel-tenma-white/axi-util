library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.axiPipe_types.all;

-- assuming the address of an entry in a matrix is of the form:
-- [MAddr][RowAddr][ColAddr][burstAddr],
-- interleave the row and column addresses.
entity axipipeaddrinterleaver is
	generic(addrBits, rowBits, colBits, burstBits: integer);
	port(addrIn: in unsigned(addrBits-1 downto 0);
		addrOut: out unsigned(addrBits-1 downto 0);
		doTranspose: in std_logic := '0';
		doInterleave: in std_logic := '1');
end entity;
architecture a of axiPipeAddrInterleaver is
	constant rowAddrBegin: integer := burstBits+rowBits*2;
	signal addrTransposed, addr1: unsigned(addrBits-1 downto 0);
	signal addrInterleaved: unsigned(addrBits-1 downto 0);
begin
	--addrTransposed <=
		--addrIn(addrIn'left downto burstBits+rowBits*2) &
		--addrIn(burstBits+rowBits-1 downto burstBits) &
		--addrIn(burstBits+rowBits*2-1 downto burstBits+rowBits) &
		--(burstBits-1 downto 0=>'0');
	addrTransposed <= transposeAddress(addrIn, burstBits, rowBits, colBits);

	addr1 <= addrTransposed when doTranspose='1' else addrIn;

--g1: for I in 0 to rowBits-1 generate
		--addrInterleaved(burstBits + I*2) <= addr1(burstBits + I);
		--addrInterleaved(burstBits + I*2 + 1) <= addr1(burstBits + I + rowBits);
	--end generate;
	--addrInterleaved(addrBits-1 downto rowAddrBegin) <= addr1(addrBits-1 downto rowAddrBegin);
	addrInterleaved <= interleaveAddress(addr1, burstBits, rowBits, colBits);


	addrOut <= addrInterleaved when doInterleave='1' else addr1;
end a;
