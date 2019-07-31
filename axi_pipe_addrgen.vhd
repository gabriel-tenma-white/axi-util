library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
USE ieee.math_real.log2;
USE ieee.math_real.ceil;
use work.axiPipe_types.all;
use work.axiPipeSizeCalc;

-- given a feed of frame addresses, generate bursts
entity axiPipeAddrGen is
	generic(burstLength: integer := 4;
			wordWidth: integer := 64);
	port(
			aclk, reset: in std_logic;

		--buffers feed in
			buffersFeed_data: in bufferInfo;
			buffersFeed_valid: in std_logic;
			buffersFeed_ready: out std_logic;

		--address out
			aready: in std_logic;
			avalid: out std_logic;
			aaddr: out memAddr_t;

		--when nonzero, indicates a transaction of this number of bytes
		--was issued; can be used to gate the AXI data bus for writes.
			bytesIssued: out unsigned(memAddrWidth-1 downto 0);

		-- frame indicator; when asserted indicates a new frame was started
		-- indicator_buffer always refers to the current frame regardless of indicator_strobe.
			indicator_strobe: out std_logic;
			indicator_buffer: out bufferInfo;
		
		-- after the end of each frame (including when aborted), the state machine
		-- will wait for this signal to go high before starting another frame
			allowNextFrame: in std_logic := '1';
		
		-- asserted after the end of a frame and stays high until allowNextFrame is 1
			frameWait: out std_logic;

		-- asserted for 1 cycle after the end of a frame (after checking allowNextFrame)
			frameDone: out std_logic;

		-- asserting this during a frame will abort the current frame, assert
		-- frameWait, and wait for allowNextFrame to become 1
			abort: in std_logic := '0'
		);
end entity;
architecture a of axiPipeAddrGen is
	constant addrIncr: integer := burstLength*(wordWidth/8);
	constant burstOrder: integer := integer(ceil(log2(real(burstLength))));

	signal reset1, reset2, reset2_2: std_logic;
	
	-- memory write address generator
	type addrGenState_t is (fetching,fetched1,fetched2,fetched3,issuing,wait1,wait2,wait3,done1,done2);
	signal state,stateNext: addrGenState_t := fetching;
	
	signal currWritingBuffer: bufferInfo;
	signal currWritingAddress,currWritingAddressNext, currWritingBufferEnd, currWritingBufferEnd2: memAddr_t;
	signal currWritingBufferNPages: unsigned(15 downto 0);

	signal wantFetchWriteBuffer,wantFetchWriteBuffer1,doFetchWriteBuffer: std_logic;
	signal wantIssueWrite, doIssueWrite: std_logic;
	
	signal bytesIssuedNext: unsigned(memAddrWidth-1 downto 0);

	signal indicator_strobe0: std_logic;
begin
	reset1 <= reset when rising_edge(aclk);
	reset2 <= reset1 when rising_edge(aclk);
	reset2_2 <= reset1 when rising_edge(aclk);

	-- fetch new buffer if current buffer is about to be completed;
	-- whenever state=issuing awvalid is high, so we must exit
	-- the issuing state before currWritingAddress becomes out of range, so
	-- we use currWritingBufferEnd2 here.
	stateNext <=
		fetching when reset2_2='1' else
		fetched1 when state=fetching and doFetchWriteBuffer='1' else
		fetched2 when state=fetched1 else
		fetched3 when state=fetched2 else
		issuing when state=fetched3 else
		wait1 when state=issuing and currWritingAddress>=currWritingBufferEnd2 and doIssueWrite='1' else
		wait1 when state=issuing and abort='1' else
		wait2 when state=wait1 else
		wait3 when state=wait2 else
		done1 when state=wait3 and allowNextFrame='1' else
		done2 when state=done1 else
		fetching when state=done2 else
		state;
	state <= stateNext when rising_edge(aclk);

	-- when reset is high we will also drain the buffers feed
	wantFetchWriteBuffer <= '1' when state=fetching else '0';
	buffersFeed_ready <= wantFetchWriteBuffer or reset2;
	doFetchWriteBuffer <= wantFetchWriteBuffer and buffersFeed_valid;

	-- latch fetched buffer info
	currWritingBuffer <= buffersFeed_data when doFetchWriteBuffer='1' and rising_edge(aclk);
	--currWritingBufferEnd <= currWritingBuffer.addr + pagesToBytes(currWritingBufferNPages) when rising_edge(aclk);
	--currWritingBufferEnd2 <= currWritingBufferEnd - addrIncr when rising_edge(aclk);
	currWritingBufferEnd2 <= currWritingBuffer.addr + pagesToBytes(currWritingBufferNPages) - addrIncr when rising_edge(aclk);
	sc: entity axiPipeSizeCalc
		port map(clk=>aclk, nPagesOrder=>currWritingBuffer.nPagesOrder, nPages=>currWritingBufferNPages);

	-- issue writes whenever state=issuing
	currWritingAddressNext <=
		currWritingBuffer.addr when state=fetched1 else
		currWritingAddress+addrIncr when state=issuing and doIssueWrite='1' else
		currWritingAddress;
	currWritingAddress <= currWritingAddressNext when rising_edge(aclk);
	wantIssueWrite <= '1' when state=issuing else '0';
	avalid <= wantIssueWrite;
	aaddr <= currWritingAddress;
	doIssueWrite <= wantIssueWrite and aready;

	bytesIssuedNext <= to_unsigned(addrIncr, memAddrWidth) when doIssueWrite='1' else (others=>'0');
	bytesIssued <= bytesIssuedNext when rising_edge(aclk);


	indicator_buffer <= currWritingBuffer;
	indicator_strobe0 <= '1' when state=fetched1 else '0';
	indicator_strobe <= indicator_strobe0 when rising_edge(aclk);

	frameWait <= '1' when state=wait3 else '0';
	frameDone <= '1' when state=done1 else '0';
end architecture;

