library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

package dcfifo2_pkg is
	function resizeLeftAligned (val: unsigned; bits: integer) return unsigned;
end package;

package body dcfifo2_pkg is
	function resizeLeftAligned (val: unsigned; bits: integer) return unsigned is
		variable origBits: integer;
	begin
		origBits := val'left - val'right + 1;
		if origBits >= bits then
			return val(val'left downto val'left-bits+1);
		else
			return val & ((bits-origBits)-1 downto 0 => '0');
		end if;
	end function;
	
end package body;

library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
USE ieee.math_real.log2;
USE ieee.math_real.round;
use work.dcfifo2_pkg.all;
use work.dcram2;
use work.greyCDCSync;
use work.axiDelay;
--dual clock show-ahead queue with overflow detection.
-- - to read from queue, whenever the queue is not empty,
--		readvalid will be asserted and data will be present on
--		rddata; to dequeue, assert rdready for one clock cycle
-- - to append to queue, put data on wrdata and assert wrvalid.
--		data will be written on every clock rising edge where
--		wrvalid='1' and wrready='1'
-- READ DELAY: 1 cycle (from readnext being asserted to next word
--		present on dataout)
-- 
entity dcfifo2 is
	generic(widthIn, widthOut: integer := 8;
				-- real depth is 2^depthOrderIn words of widthIn
				depthOrderIn: integer := 9;
				outputRegisters: integer := 1);
	port(rdclk,wrclk: in std_logic;
			
			-- read side; synchronous to rdclk
			rdvalid: out std_logic;
			rdready: in std_logic;
			rddata: out std_logic_vector(widthOut-1 downto 0);
			-- how many input words are left to be read
			rdleft: out unsigned(depthOrderIn+integer(round(log2(real(widthIn)/real(widthOut))))-1 downto 0) := (others=>'X');
			
			--write side; synchronous to wrclk
			wrvalid: in std_logic;
			wrready: out std_logic;
			wrdata: in std_logic_vector(widthIn-1 downto 0);
			-- how much space is available in the queue, in output words
			wrroom: out unsigned(depthOrderIn-1 downto 0) := (others=>'X')
			);
end entity;
architecture a of dcfifo2 is
	constant depthRatioOrder: integer := integer(round(log2(real(widthIn)/real(widthOut))));
	constant depthOrderOut: integer := depthOrderIn + depthRatioOrder;
	
	constant depthIn: integer := 2**depthOrderIn;
	constant depthOut: integer := 2**depthOrderOut;
	constant syncStages: integer := 3;
	--ram
	signal ram1rdaddr: unsigned(depthOrderOut-1 downto 0);
	signal ram1wraddr: unsigned(depthOrderIn-1 downto 0);
	signal ram1wrdata: std_logic_vector(widthIn-1 downto 0);
	signal ram1rddata: std_logic_vector(widthOut-1 downto 0);
	signal ram1wren: std_logic;
	
	
	--################ state registers ################
	
	--read side's view of the current state
	signal rdRpos,rdWpos: unsigned(depthOrderOut-1 downto 0) := (others=>'0'); -- binary integer
	signal rdRposP1: unsigned(depthOrderOut-1 downto 0) := (0=>'1', others=>'0');
	signal rdRposResized: unsigned(depthOrderIn-1 downto 0);
	signal rdRposGrey: std_logic_vector(depthOrderIn-1 downto 0);
	signal rdWposGrey: std_logic_vector(depthOrderOut-1 downto 0);
	
	--write side's view of the current state
	signal wrRpos,wrWpos,wrRposNext: unsigned(depthOrderIn-1 downto 0) := (others=>'0');
	signal wrRposM1: unsigned(depthOrderIn-1 downto 0) := (others=>'1');
	signal wrWposP1: unsigned(depthOrderIn-1 downto 0) := (0=>'1', others=>'0');
	signal wrWposResized: unsigned(depthOrderOut-1 downto 0);
	signal wrWposGrey: std_logic_vector(depthOrderOut-1 downto 0);
	signal wrRposGrey: std_logic_vector(depthOrderIn-1 downto 0);
	
	--################ queue logic ################
	-- empty condition: rpos = wpos
	-- full condition: rpos = wpos + 1
	
	--read side
	signal rdRposNext: unsigned(depthOrderOut-1 downto 0);
	signal rdEmpty, rdAlmostEmpty, rdEmpty1, rdAlmostEmpty1: std_logic := '1';
	signal rdPossible: std_logic := '0'; -- whether we have data to read
	signal rdWillPerform, rdWillPerform1: std_logic := '0'; -- if true, we will actually do a read
	signal rdQueueReady: std_logic; -- whether there is space in output register
	
	--write side
	signal wrWposNext: unsigned(depthOrderIn-1 downto 0);
	signal wrFull, wrAlmostFull, wrFull1, wrAlmostFull1: std_logic := '0';
	signal wrPossible: std_logic := '0'; -- whether we have space to write
	signal wrWillPerform, wrWillPerform1: std_logic := '0'; -- if true, we will actually do a write
begin
	--ram
	ram: entity dcram2
		generic map(widthRead=>widthOut, widthWrite=>widthIn,
					depthOrderWrite=>depthOrderIn)
		port map(rdclk=>rdclk,wrclk=>wrclk,								--clocks
			rden=>rdQueueReady,rdaddr=>rdRpos,rddata=>ram1rddata,		--read side
			wren=>'1',wraddr=>wrWpos,wrdata=>wrdata);					--write side
	
	--grey code
	rdRposResized <= resizeLeftAligned(rdRpos, depthOrderIn);
	wrWposResized <= resizeLeftAligned(wrWpos, depthOrderOut);

--	rdRposGrey <= std_logic_vector(rdRpos);
--	wrWposGrey <= std_logic_vector(wrWpos);
--	wrRpos <= unsigned(wrRposGrey);
--	rdWpos <= unsigned(rdWposGrey);

	--cross rpos from read side to write side
	syncRpos: entity greyCDCSync
		generic map(width=>rdRposResized'length, stages=>syncStages, inputRegistered=>false)
		port map(srcclk=>rdclk, dstclk=>wrclk, datain=>rdRposResized, dataout=>wrRpos);
	wrRposM1 <= wrRpos-1 when rising_edge(wrclk);

	--cross wpos from write side to read side
	syncWpos: entity greyCDCSync
		generic map(width=>wrWposResized'length, stages=>syncStages, inputRegistered=>false)
		port map(srcclk=>wrclk, dstclk=>rdclk, datain=>wrWposResized, dataout=>rdWpos);

	--queue logic: read side
	--		check if we should do a read
	rdEmpty <= '1' when rdRpos = rdWpos else '0';
	rdAlmostEmpty <= '1' when rdRposP1 = rdWpos else '0';
	rdEmpty1 <= rdEmpty when rising_edge(rdclk);
	rdAlmostEmpty1 <= rdAlmostEmpty when rising_edge(rdclk);
	rdPossible <= '1' when rdAlmostEmpty1='0' and rdEmpty1='0' else
					'1' when rdEmpty1='0' and rdWillPerform1='0' else
					'0';

	--rdvalid <= rdPossible;
	rdWillPerform <= rdPossible and rdQueueReady;
	rdWillPerform1 <= rdWillPerform when rising_edge(rdclk);
	--		calculate new rpos pointer
	rdRposP1 <= rdRposP1+1 when rdWillPerform='1' and rising_edge(rdclk);
	rdRpos <= rdRposP1 when rdWillPerform='1' and rising_edge(rdclk);
	rdleft <= rdWpos-rdRpos;
	
	-- the ram adds 1 cycle of delay, so we have to delay valid
	-- to compensate; however, to preserve correct AXI semantics we
	-- need some extra logic
	del: entity axiDelay
		generic map(width=>widthOut,
					validDelay=>outputRegisters+1, dataDelay=>outputRegisters)
		port map(clk=>rdclk,inReady=>rdQueueReady,
			inValid=>rdPossible,inData=>ram1rddata,
			outReady=>rdready,outValid=>rdvalid,outData=>rddata);

	--queue logic: write side
	--		check if we should do a write
	wrFull <= '1' when wrRposM1 = wrWpos else '0';
	wrAlmostFull <= '1' when wrRposM1 = wrWposP1 else '0';
	wrFull1 <= wrFull when rising_edge(wrclk);
	wrAlmostFull1 <= wrAlmostFull when rising_edge(wrclk);
	wrPossible <= '1' when wrAlmostFull1='0' and wrFull1='0' else
					'1' when wrFull1='0' and wrWillPerform1='0' else
					'0';
	wrready <= wrPossible;
	wrWillPerform <= wrPossible and wrvalid;
	wrWillPerform1 <= wrWillPerform when rising_edge(wrclk);
	--		calculate new wpos pointer
	wrWposP1 <= wrWposP1+1 when wrWillPerform='1' and rising_edge(wrclk);
	wrWpos <= wrWposP1 when wrWillPerform='1' and rising_edge(wrclk);
	wrroom <= wrRposM1-wrWpos; -- when rising_edge(wrclk);
	
end architecture;
