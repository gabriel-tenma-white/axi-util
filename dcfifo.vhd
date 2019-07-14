library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.dcram;
use work.greyCDCSync;
use work.axiDelay;

--dual clock show-ahead queue with overflow detection
-- - to read from queue, whenever the queue is not empty,
--		readvalid will be asserted and data will be present on
--		rdata; to dequeue, assert readready for one clock cycle
-- - to append to queue, put data on wdata and assert writeen
--		data will be written on every clock rising edge where
--		writevalid='1' and writeready='1'
-- READ DELAY: 1 cycle (from readnext being asserted to next word
--		present on dataout)
-- 
entity dcfifo is
	generic(width: integer := 8;
				-- real depth is 2^depth_order
				depthOrder: integer := 9;
				singleClock: boolean := false);
	port(rdclk,wrclk: in std_logic;
			
			-- read side; synchronous to rdclk
			rdvalid: out std_logic;
			rdready: in std_logic;
			rddata: out std_logic_vector(width-1 downto 0);
			-- how many words is left to be read
			rdleft: out unsigned(depthOrder-1 downto 0) := (others=>'X');
			
			--write side; synchronous to wrclk
			wrvalid: in std_logic;
			wrready: out std_logic;
			wrdata: in std_logic_vector(width-1 downto 0);
			-- how much space is available in the queue, in words
			wrroom: out unsigned(depthOrder-1 downto 0) := (others=>'X')
			);
end entity;
architecture a of dcfifo is
	constant depth: integer := 2**depthOrder;
	constant syncStages: integer := 3;
	--ram
	signal ram1rdaddr,ram1wraddr: unsigned(depthOrder-1 downto 0);
	signal ram1wrdata,ram1rddata: std_logic_vector(width-1 downto 0);
	signal ram1wren: std_logic;
	signal wrdata1: std_logic_vector(width-1 downto 0);

	constant extraWriteRegister: boolean := (depthOrder >= 6);
	
	
	--################ state registers ################
	
	--read side's view of the current state
	signal rdRpos,rdWpos,rdWposNext: unsigned(depthOrder-1 downto 0) := (others=>'0'); -- binary integer
	signal rdRposGrey, rdWposGrey: std_logic_vector(depthOrder-1 downto 0);
	
	--write side's view of the current state
	signal wrRpos,wrRposM1,wrWpos,wrWpos1,wrRposNext: unsigned(depthOrder-1 downto 0) := (others=>'0');
	signal wrRposGrey, wrWposGrey: std_logic_vector(depthOrder-1 downto 0);
	
	--################ queue logic ################
	-- empty condition: rpos = wpos
	-- full condition: rpos = wpos + 1
	
	--read side
	signal rdRposNext: unsigned(depthOrder-1 downto 0);
	signal rdPossible: std_logic; -- whether we have data to read
	signal rdWillPerform: std_logic; -- if true, we will actually do a read
	signal rdQueueReady: std_logic; -- whether there is space in output register
	
	--write side
	signal wrWposNext: unsigned(depthOrder-1 downto 0);
	signal wrPossible: std_logic; -- whether we have space to write
	signal wrWillPerform: std_logic; -- if true, we will actually do a write
begin
	--ram
	ram: entity dcram generic map(width=>width, depthOrder=>depthOrder)
		port map(rdclk=>rdclk,wrclk=>wrclk,								--clocks
			rden=>rdQueueReady,rdaddr=>rdRpos,rddata=>rddata,			--read side
			wren=>'1',wraddr=>wrWpos1,wrdata=>wrdata1);					--write side
	
	wrRposM1 <= wrRpos-1 when rising_edge(wrclk);

g1:
	if singleClock generate
		wrRpos <= rdRpos;
		rdWpos <= wrWpos1 when rising_edge(rdclk);
	end generate;
g2:
	if not singleClock generate
		syncRpos: entity greyCDCSync
			generic map(width=>depthOrder, stages=>syncStages, inputRegistered=>false)
			port map(srcclk=>rdclk, dstclk=>wrclk, datain=>rdRpos, dataout=>wrRpos);
		syncWpos: entity greyCDCSync
			generic map(width=>depthOrder, stages=>syncStages, inputRegistered=>false)
			port map(srcclk=>wrclk, dstclk=>rdclk, datain=>wrWpos1, dataout=>rdWpos);
	end generate;


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
	del: entity axiDelay generic map(width=>width, validDelay=>1, dataDelay=>0)
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
	
g3: if extraWriteRegister generate
		wrWpos1 <= wrWpos when rising_edge(wrclk);
		wrdata1 <= wrdata when rising_edge(wrclk);
	end generate;
g4: if not extraWriteRegister generate
		wrWpos1 <= wrWpos;
		wrdata1 <= wrdata;
	end generate;

	wrroom <= wrRposM1-wrWpos; -- when rising_edge(wrclk);
	
end architecture;
