library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
USE ieee.math_real.log2;
USE ieee.math_real.ceil;
use work.axiPipe_types.all;
use work.axiPipeSizeCalc;

-- given a feed of buffers and byte counts, issue an indicator whenever
-- a buffer was finished.
entity axipipedatacount is
	port(
			aclk: in std_logic;

		-- buffers feed in
			buffersFeed_data: in bufferInfo;
			buffersFeed_sizeBytes: in bufLengthBytes_t;
			buffersFeed_valid: in std_logic;
			buffersFeed_ready: out std_logic;

		-- byte indicator in
			bytesIssued: in memAddr_t;

		-- current buffer
			currBuffer: out bufferInfo;
			currBuffer_valid: out std_logic;

		-- frame indicator; when asserted indicates a new frame was finished.
			indicator_strobe: out std_logic;
			indicator_buffer: out bufferInfo
		);
end entity;
architecture a of axiPipeDataCount is
	signal accum, accumAdd, accumSub, accumSubNext, accumDelta: memAddr_t := (others=>'0');
	signal curLength: bufLengthBytes_t;
	signal curPages: bufLengthPages_t;
	signal curBuffer: bufferInfo;

	-- state 🅱achine
	type state_t is (FETCHING, FETCHED, RUNNING, DONE);
	signal state, stateNext: state_t := FETCHING;
begin
	-- accumulator
	accumDelta <= accumAdd - accumSub when rising_edge(aclk);
	accum <= accum + accumDelta when rising_edge(aclk);

	accumAdd <= bytesIssued when rising_edge(aclk);

	-- state 🅱achine
	state <= stateNext when rising_edge(aclk);
	stateNext <=
			FETCHED when state=FETCHING and buffersFeed_valid='1' else
			RUNNING when state=FETCHED else
			DONE when state=RUNNING and accum >= curLength else
			FETCHING when state=DONE else
			state;

	buffersFeed_ready <= '1' when state=FETCHING else '0';
	curBuffer <= buffersFeed_data when state=FETCHING and rising_edge(aclk);
	accumSubNext <= resize(curLength,accumSub'length) when state=DONE else
					to_unsigned(0, accumSub'length);
	accumSub <= accumSubNext when rising_edge(aclk);

	--sc: entity axiPipeSizeCalc
	--	port map(clk=>aclk, nPagesOrder=>curBuffer.nPagesOrder, nPages=>curPages);
	--curLength <= pagesToBytes(curPages);
	curLength <= buffersFeed_sizeBytes when state=FETCHING and rising_edge(aclk);


	currBuffer <= curBuffer;
	currBuffer_valid <= '0' when state=FETCHING else '1';
	indicator_strobe <= '1' when state=DONE else '0';
	indicator_buffer <= curBuffer;

end a;
