--  Hello world program
library ieee;
library work;
use std.textio.all; -- Imports the standard textio package.
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.axiPipe_types.all;
use work.axiPipeDataCount2;

--  Defines a design entity, without any ports.
entity test_axiPipeDataCount2 is
end test_axiPipeDataCount2;

architecture behaviour of test_axiPipeDataCount2 is

	signal clk: std_logic;

	-- buffers feed in
	signal buffersFeed_data: bufferInfo;
	signal buffersFeed_valid: std_logic;
	signal buffersFeed_ready: std_logic;

	-- axi stream
	signal ready_and_valid, ready_and_valid1: std_logic := '0';
	signal tlast1: std_logic;
	signal curBuffer: bufferInfo;


	constant inClkHPeriod: time := 0.5 ns;
begin

	inst: entity axiPipeDataCount2
		generic map(wordWidth=>64)
		port map(aclk=>clk,
			buffersFeed_data=>buffersFeed_data,
			buffersFeed_valid=>buffersFeed_valid,
			buffersFeed_ready=>buffersFeed_ready,
			dout_tvalid_and_tready=>ready_and_valid1,
			dout_tlast=>tlast1,
			dout_curBuffer=>curBuffer);

	ready_and_valid1 <= ready_and_valid when rising_edge(clk);

	process
		variable l : line;
		variable bufIndex: integer := 0;
		type bufSizes_t is array(0 to 15) of integer;
		variable bufSizes: bufSizes_t := (0,0,1,0,1,1,0,1, 0,0,1,1,1,0,1,1);
		
		variable expectBufIndex, wordIndex: integer := 0;
		variable expectWords: integer := 512;
		variable expect_tlast: std_logic;
		variable lfsr: unsigned(6 downto 0) := "1101010";
	begin
		wait for inClkHPeriod; clk <= '1'; wait for inClkHPeriod; clk <= '0';
		wait for inClkHPeriod; clk <= '1'; wait for inClkHPeriod; clk <= '0';
		for I in 0 to 10000 loop
			-- feed data in
			buffersFeed_valid <= '1';
			buffersFeed_data.addr <= to_unsigned(bufIndex, memAddrWidth);
			buffersFeed_data.nPagesOrder <= to_unsigned(bufSizes(bufIndex), 4);
			if buffersFeed_ready='1' then
				bufIndex := bufIndex+1;
			end if;

			lfsr := lfsr(0) & (lfsr(6) xor lfsr(0)) & lfsr(5 downto 1);
			ready_and_valid <= lfsr(0);

			if ready_and_valid1='1' then
				assert to_integer(curBuffer.addr) = expectBufIndex;
				if wordIndex = expectWords-1 then
					expectBufIndex := expectBufIndex+1;
					expectWords := (2**bufSizes(expectBufIndex)) * 512;
					assert tlast1='1';
					wordIndex := 0;
				else
					wordIndex := wordIndex+1;
				end if;
			end if;

			wait for inClkHPeriod; clk <= '1'; wait for inClkHPeriod; clk <= '0';
		end loop;
		
		wait;
	end process;
end behaviour;
