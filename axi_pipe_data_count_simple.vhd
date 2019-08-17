library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.axiPipe_types.all;
USE ieee.math_real.log2;
USE ieee.math_real.ceil;

-- given the current buffer size, count data words and assert interrupt
-- when done
entity axipipedatacountsimple is
	generic(addrIncr: integer);
	port(
			aclk: in std_logic;

		-- buffers feed in
			curBytes: in bufLengthBytes_t;
			curBytesStrobe: in std_logic;

		-- data indicator
			bvalid: in std_logic;

			irqOut: out std_logic
		);
end entity;
architecture a of axiPipeDataCountSimple is
	constant addrIncrOrder: integer := integer(ceil(log2(real(addrIncr))));

	signal curBytesTrunc: bufLengthBytes_t;
	signal accum, accumNext, accum1, accum1Next: bufLengthBytes_t := (others=>'0');
	signal eq0, eq1, eq2: std_logic := '1';
begin
	-- round down to the nearest multiple of addrIncr
	curBytesTrunc <= curBytes(curBytes'left downto addrIncrOrder) &
					(addrIncrOrder-1 downto 0=>'0');

	-- accumulator
	accum <= accum+addrIncr when bvalid='1' and rising_edge(aclk);
	accum1 <= accum1+curBytes when curBytesStrobe='1' and rising_edge(aclk);

	eq0 <= '1' when accum=accum1 else '0';
	eq1 <= eq0 when rising_edge(aclk);
	eq2 <= eq1 when rising_edge(aclk);

	irqOut <= eq1 and not eq2 when rising_edge(aclk);
end a;
