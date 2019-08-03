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
	signal rdRposP1: unsigned(depthOrder-1 downto 0) := (0=>'1', others=>'0');
	signal rdRposGrey, rdWposGrey: std_logic_vector(depthOrder-1 downto 0);
	
	--write side's view of the current state
	signal wrRpos,wrRposM1,wrWpos,wrWpos1,wrRposNext: unsigned(depthOrder-1 downto 0) := (others=>'0');
	signal wrWposP1: unsigned(depthOrder-1 downto 0) := (0=>'1', others=>'0');
	signal wrRposGrey, wrWposGrey: std_logic_vector(depthOrder-1 downto 0);
	
	--################ queue logic ################
	-- empty condition: rpos = wpos
	-- full condition: rpos = wpos + 1
	
	--read side
	signal rdEmpty, rdAlmostEmpty, rdEmpty1, rdAlmostEmpty1: std_logic := '1';
	signal rdPossible: std_logic := '0'; -- whether we have data to read
	signal rdWillPerform, rdWillPerform1: std_logic := '0'; -- if true, we will actually do a read
	signal rdQueueReady: std_logic := '0'; -- whether there is space in output register
	
	--write side
	signal wrFull, wrAlmostFull, wrFull1, wrAlmostFull1: std_logic := '0';
	signal wrPossible: std_logic := '0'; -- whether we have space to write
	signal wrWillPerform, wrWillPerform1: std_logic := '0'; -- if true, we will actually do a write
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
	del: entity axiDelay generic map(width=>width, validDelay=>1, dataDelay=>0)
		port map(clk=>rdclk,inReady=>rdQueueReady,
		inValid=>rdPossible,inData=>(others=>'0'),
		outReady=>rdready,outValid=>rdvalid,outData=>open);
	
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
