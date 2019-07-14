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
				depthOrderIn: integer := 9);
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
	signal rdRpos,rdWpos,rdWposNext: unsigned(depthOrderOut-1 downto 0) := (others=>'0'); -- binary integer
	signal rdRposResized: unsigned(depthOrderIn-1 downto 0);
	signal rdRposGrey: std_logic_vector(depthOrderIn-1 downto 0);
	signal rdWposGrey: std_logic_vector(depthOrderOut-1 downto 0);
	
	--write side's view of the current state
	signal wrRpos,wrRposM1,wrWpos,wrRposNext: unsigned(depthOrderIn-1 downto 0) := (others=>'0');
	signal wrWposResized: unsigned(depthOrderOut-1 downto 0);
	signal wrWposGrey: std_logic_vector(depthOrderOut-1 downto 0);
	signal wrRposGrey: std_logic_vector(depthOrderIn-1 downto 0);
	
	--################ queue logic ################
	-- empty condition: rpos = wpos
	-- full condition: rpos = wpos + 1
	
	--read side
	signal rdRposNext: unsigned(depthOrderOut-1 downto 0);
	signal rdPossible: std_logic := '0'; -- whether we have data to read
	signal rdWillPerform: std_logic := '0'; -- if true, we will actually do a read
	signal rdQueueReady: std_logic; -- whether there is space in output register
	
	--write side
	signal wrWposNext: unsigned(depthOrderIn-1 downto 0);
	signal wrPossible: std_logic := '0'; -- whether we have space to write
	signal wrWillPerform: std_logic := '0'; -- if true, we will actually do a write
begin
	--ram
	ram: entity dcram2
		generic map(widthRead=>widthOut, widthWrite=>widthIn,
					depthOrderWrite=>depthOrderIn)
		port map(rdclk=>rdclk,wrclk=>wrclk,								--clocks
			rden=>rdQueueReady,rdaddr=>rdRpos,rddata=>rddata,			--read side
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

	--cross wpos from write side to read side
	syncWpos: entity greyCDCSync
		generic map(width=>wrWposResized'length, stages=>syncStages, inputRegistered=>false)
		port map(srcclk=>wrclk, dstclk=>rdclk, datain=>wrWposResized, dataout=>rdWpos);

	--queue logic: read side
	--		check if we should do a read
	rdPossible <= '0' when rdRpos = rdWpos else '1'; -- if not empty, then can read
	--rdvalid <= rdPossible;
	rdWillPerform <= rdPossible and rdQueueReady;
	--		calculate new rpos pointer
	rdRposNext <= rdRpos+1 when rdWillPerform='1' else rdRpos;
	rdRpos <= rdRposNext when rising_edge(rdclk);
	rdleft <= rdWpos-rdRpos;
	
	-- the ram adds 1 cycle of delay, so we have to delay valid
	-- to compensate; however, to preserve correct AXI semantics we
	-- need some extra logic
	del: entity axiDelay generic map(width=>widthOut, validDelay=>1, dataDelay=>0)
		port map(clk=>rdclk,inReady=>rdQueueReady,
		inValid=>rdPossible,inData=>(others=>'0'),
		outReady=>rdready,outValid=>rdvalid,outData=>open);
	
	--queue logic: write side
	--		check if we should do a write
	wrPossible <= '0' when wrRposM1 = wrWpos else '1';
	wrready <= wrPossible;
	wrWillPerform <= wrPossible and wrvalid;
	--		calculate new wpos pointer
	wrWposNext <= wrWpos+1 when wrWillPerform='1' else wrWpos;
	wrWpos <= wrWposNext when rising_edge(wrclk);
	wrroom <= wrRposM1-wrWpos; -- when rising_edge(wrclk);
	
end architecture;
