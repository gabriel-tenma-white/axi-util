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

		-- data indicator
			bvalid: in std_logic;

			irqOut: out std_logic
		);
end entity;
architecture a of axiPipeDataCountSimple is
	constant addrIncrOrder: integer := integer(ceil(log2(real(addrIncr))));

	signal curBytesTrunc: bufLengthBytes_t;
	signal accum, accumNext, resetVal: bufLengthBytes_t;
	signal compEqual, irq0: std_logic;

	-- state 🅱achine
	type state_t is (FETCHING, FETCHED, RUNNING, DONE);
	signal state, stateNext: state_t := FETCHING;
begin
	-- round down to the nearest multiple of addrIncr
	curBytesTrunc <= curBytes(curBytes'left downto addrIncrOrder) &
					(addrIncrOrder-1 downto 0=>'0');

	-- accumulator
	resetVal <= to_unsigned(0, bufLengthBytesWidth) when bvalid='0' else
				to_unsigned(addrIncr, bufLengthBytesWidth);
	compEqual <= '1' when accum=curBytesTrunc else '0';

	accumNext <= resetVal		when compEqual='1' else
				accum+addrIncr	when bvalid='1' else
				accum;
	accum <= accumNext when rising_edge(aclk);

	irq0 <= compEqual when rising_edge(aclk);
	irqOut <= irq0 when rising_edge(aclk);
end a;
