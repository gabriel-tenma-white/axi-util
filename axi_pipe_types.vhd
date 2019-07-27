library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

package axiPipe_types is
	constant memAddrWidth: integer := 32;
	constant bufLengthPagesWidth: integer := 16;
	constant bufLengthBytesWidth: integer := bufLengthPagesWidth + 12;
	constant flagsWidth: integer := 7;

	subtype memAddr_t is unsigned(memAddrWidth-1 downto 0);
	subtype bufLengthPages_t is unsigned(bufLengthPagesWidth-1 downto 0);
	subtype bufLengthBytes_t is unsigned(bufLengthBytesWidth-1 downto 0);

	subtype flags_t is std_logic_vector(flagsWidth-1 downto 0);
	
	type bufferInfo is record
		-- start address in bytes; should be page aligned
		addr: memAddr_t;

		-- how many pages, log2. 0 => 1 page, 1 => 2 pages, 2 => 4 pages, ...
		nPagesOrder: unsigned(3 downto 0);

		-- software supplied user flags
		flags: flags_t;

		-- whether to issue an irq when this buffer is done
		shouldInterrupt: std_logic;
	end record;

	type status is record
		readingAddr, writingAddr: memAddr_t;
		readBuffersDone, writeBuffersDone: unsigned(31 downto 0);
	end record;
	
	function to_bufferInfo(data: memAddr_t) return bufferInfo;
	function to_bufferInfo(data: std_logic_vector) return bufferInfo;
	function bufferInfo_pack(data: bufferInfo) return std_logic_vector;
	function pagesToBytes(p: bufLengthPages_t) return bufLengthBytes_t;

	-- row and column dimensions refer to the output address (physical matrix dimensions)
	function transposeAddress(addr: memAddr_t; burstBits,rowsOrder,colsOrder: integer) return memAddr_t;
	function interleaveAddress(addr: memAddr_t; burstBits,rowsOrder,colsOrder: integer) return memAddr_t;

	function interleaveBits(a,b: unsigned) return unsigned;

	function ceilLog2(val: integer) return integer;
end package;


package body axiPipe_types is

	function to_bufferInfo (data: memAddr_t) return bufferInfo is
		variable res: bufferInfo;
	begin
		res.addr := data(31 downto 12) & (11 downto 0=>'0');
		res.nPagesOrder := data(3 downto 0);
		res.flags := std_logic_vector(data(10 downto 4));
		res.shouldInterrupt := data(11);
		return res;
	end function;

	function to_bufferInfo(data: std_logic_vector) return bufferInfo is
	begin
		return to_bufferInfo(memAddr_t(data));
	end function;

	function bufferInfo_pack(data: bufferInfo) return std_logic_vector is
		variable res: std_logic_vector(31 downto 0) := (others=>'0');
	begin
		res(31 downto 12) := std_logic_vector(data.addr(31 downto 12));
		res(3 downto 0) := std_logic_vector(data.nPagesOrder);
		res(10 downto 4) := std_logic_vector(data.flags);
		res(11) := data.shouldInterrupt;
		return res;
	end function;

	function pagesToBytes(p: bufLengthPages_t) return bufLengthBytes_t is
	begin
		return shift_left(resize(p, bufLengthBytesWidth), 12);
	end function;


	function transposeAddress(addr: memAddr_t; burstBits,rowsOrder,colsOrder: integer) return memAddr_t is
		variable res: memAddr_t;
	begin
		res :=
			addr(addr'left downto burstBits+rowsOrder+colsOrder) &
			addr(burstBits+rowsOrder-1 downto burstBits) &
			addr(burstBits+rowsOrder+colsOrder-1 downto burstBits+rowsOrder) &
			(burstBits-1 downto 0=>'0');
		return res;
	end function;

	function interleaveAddress(addr: memAddr_t; burstBits,rowsOrder,colsOrder: integer) return memAddr_t is
		variable res: memAddr_t;
		variable row: unsigned(rowsOrder-1 downto 0);
		variable col: unsigned(colsOrder-1 downto 0);
		variable nInterleave, nRes, nExtra, nMatrix: integer;
	begin
		-- pick the smaller of the row and col bits as the number of bits to interleave
		nInterleave := rowsOrder;
		if colsOrder < rowsOrder then
			nInterleave := colsOrder;
		end if;

		col := addr(burstBits+colsOrder-1 downto burstBits);
		row := addr(burstBits+colsOrder+rowsOrder-1 downto burstBits+colsOrder);
		for I in 0 to nInterleave-1 loop
			res(burstBits + I*2) := col(I);
			res(burstBits + I*2 + 1) := row(I);
		end loop;

		nRes := burstBits + nInterleave*2;
		nMatrix := rowsOrder + colsOrder + burstBits;
		nExtra := rowsOrder + colsOrder - nInterleave*2;

		-- prepend leftover column or row bits
		if colsOrder > rowsOrder then
			res(nRes+nExtra-1 downto nRes) := col(col'left downto nInterleave);
		else
			res(nRes+nExtra-1 downto nRes) := row(row'left downto nInterleave);
		end if;

		-- prepend matrix address
		res(res'left downto nMatrix) := addr(res'left downto nMatrix);

		res(burstBits-1 downto 0) := (others=>'0');
		return res;
	end function;

	function interleaveBits(a,b: unsigned) return unsigned is
		variable res: unsigned(a'length + b'length - 1 downto 0);
		variable nInterleave, nExtra: integer;
	begin
		-- pick the smaller of the row and col bits as the number of bits to interleave
		nInterleave := a'length;
		if b'length < a'length then
			nInterleave := b'length;
		end if;

		for I in 0 to nInterleave-1 loop
			res(I*2) := b(I);
			res(I*2 + 1) := a(I);
		end loop;

		if b'length > a'length then
			res(res'left downto nInterleave*2) := b(b'left downto nInterleave);
		else
			res(res'left downto nInterleave*2) := a(a'left downto nInterleave);
		end if;

		return res;
	end function;


	
	function ceilLog2(val: integer) return integer is
		variable tmp: integer;
	begin
		for I in 0 to 32 loop
			tmp := 2**I;
			if tmp >= val then
				return I;
			end if;
		end loop;
		return -1;
	end function;
end axiPipe_types;


library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.axiPipe_types.all;

-- delay is 1 cycle
entity axiPipeSizeCalc is
	port(clk: in std_logic;
		nPagesOrder: in unsigned(3 downto 0);
		nPages: out bufLengthPages_t);
end entity;
architecture a of axiPipeSizeCalc is
	signal tmp: bufLengthPages_t;
begin
g1: for I in nPages'range generate
		tmp(I) <= '1' when nPagesOrder=I else '0';
	end generate;
	nPages <= tmp when rising_edge(clk);
end a;

