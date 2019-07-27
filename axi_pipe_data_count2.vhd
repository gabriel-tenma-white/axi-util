library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.axiPipe_types.all;
use work.axiPipeSizeCalc;

-- given a feed of buffers and byte counts, issue an indicator whenever
-- a buffer was finished.
entity axiPipeDataCount2 is
	generic(wordWidth: integer := 64);
	port(
			aclk: in std_logic;

		-- buffers feed in
			buffersFeed_data: in bufferInfo;
			buffersFeed_valid: in std_logic;
			buffersFeed_ready: out std_logic;

		-- set this to (tvalid and tready)
			dout_tvalid_and_tready: in std_logic;

		-- asserted for the last word in each buffer
			dout_tlast: out std_logic;

		-- the buffer associated with the current output word
			dout_curBuffer: out bufferInfo
		);
end entity;
architecture a of axiPipeDataCount2 is
	constant wordSizeOrder: integer := ceilLog2(wordWidth/8);
	constant counterWidth: integer := bufLengthBytesWidth - wordSizeOrder;

	signal wordsGoal: unsigned(counterWidth-1 downto 0) := to_unsigned(0, counterWidth) - 2;
	signal wordsIssued: unsigned(counterWidth-1 downto 0) := (others=>'0');
	signal tlastNext, tlast, outCE, shiftAct, shiftActPrev: std_logic;

	signal nextBuffer, curBuffer: bufferInfo;
	signal nextBuffer_valid, curBuffer_valid: std_logic := '0';

	-- state 🅱achine
	type state_t is (FETCHING, FETCHED, WAITSHIFT, SHIFTED);
	signal state, stateNext: state_t := FETCHING;
	signal incrementGoal: std_logic;

	signal nextBufferPages: bufLengthPages_t;
	signal nextBufferBytes: bufLengthBytes_t;
	signal nextBufferWords: unsigned(counterWidth-1 downto 0);
begin

	-- counter pipeline
	wordsGoal <= wordsGoal+nextBufferWords when incrementGoal='1' and rising_edge(aclk);
	wordsIssued <= wordsIssued+1 when outCE='1' and rising_edge(aclk);
	tlastNext <= '1' when wordsGoal=wordsIssued else '0';
	tlast <= tlastNext when outCE='1' and rising_edge(aclk);
	outCE <= dout_tvalid_and_tready;

	-- buffer swapping logic
	shiftAct <= (outCE and tlast) or (not curBuffer_valid);
	shiftActPrev <= shiftAct when rising_edge(aclk);
	curBuffer <= nextBuffer when shiftAct='1' and rising_edge(aclk);
	curBuffer_valid <= nextBuffer_valid when shiftAct='1' and rising_edge(aclk);

	-- state 🅱achine
	state <= stateNext when rising_edge(aclk);
	stateNext <=
		FETCHED when state=FETCHING and buffersFeed_valid='1' else
		WAITSHIFT when state=FETCHED else
		SHIFTED when state=WAITSHIFT and shiftActPrev='1' else
		FETCHING when state=SHIFTED else
		state;

	buffersFeed_ready <= '1' when state=FETCHING else '0';
	nextBuffer <= buffersFeed_data when state=FETCHING and rising_edge(aclk);
	nextBuffer_valid <= '1' when state=FETCHED else
						'1' when state=WAITSHIFT else
						'0';
	incrementGoal <= '1' when state=SHIFTED else '0';

	-- calculate buffer words
	sc: entity axiPipeSizeCalc
		port map(clk=>aclk, nPagesOrder=>nextBuffer.nPagesOrder, nPages=>nextBufferPages);
	nextBufferBytes <= pagesToBytes(nextBufferPages);
	nextBufferWords <= nextBufferBytes(nextBufferBytes'left downto wordSizeOrder);

	-- outputs
	dout_tlast <= tlast;
	dout_curBuffer <= curBuffer;
end a;
