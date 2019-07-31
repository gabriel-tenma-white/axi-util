library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
USE ieee.math_real.log2;
USE ieee.math_real.ceil;
use work.dcfifo;
use work.oxiToAxiSkid;
use work.axiPipe_types.all;
use work.axiConfigRegisters;
use work.axiPipeAddrGen;
use work.axiPipeDataCount;
use work.axiPipeDataCountSimple;
use work.axiDataGating;
use work.axiDataGatingSimple;

-- given a stream of frame start addresses, stream data in and write to memory.
entity axiPipeWriter is
	generic(burstLength: integer := 4;
			wordWidth: integer := 64;
			userAddrPerm: boolean := false);
	port(
			aclk, reset: in std_logic;

		-- buffers feed in
			buffersFeed_tdata: in bufferInfo;
			buffersFeed_tvalid: in std_logic;
			buffersFeed_tready: out std_logic;

		--axi memory mapped master, write side
			mm_awaddr: out std_logic_vector(memAddrWidth-1 downto 0);
			mm_awprot: out std_logic_vector(2 downto 0);
			mm_awlen: out std_logic_vector(3 downto 0);
			mm_awvalid: out std_logic;
			mm_awready: in std_logic;
			mm_wdata: out std_logic_vector(wordWidth-1 downto 0);
			mm_wlast: out std_logic;
			mm_wvalid: out std_logic;
			mm_wready: in std_logic;
			
			mm_bvalid: in std_logic;
			mm_bready: out std_logic;
		
		-- irq out, synchronous to aclk, one clock cycle pulse width
			irq: out std_logic;

		-- streaming interface, input (write data to memory);
		-- if a word is transferred with tlast=1, the current buffer will be aborted.
			streamIn_tvalid: in std_logic;
			streamIn_tready: out std_logic;
			streamIn_tdata: in std_logic_vector(wordWidth-1 downto 0);
			streamIn_tlast: in std_logic;

		-- user defined address permutation (optional)
			addrPerm_din: out memAddr_t;
			addrPerm_bufferInfo: out bufferInfo;
			addrPerm_dout: in memAddr_t := (others=>'0')
		);
end entity;
architecture a of axiPipeWriter is
	attribute X_INTERFACE_PARAMETER : string;
	attribute X_INTERFACE_PARAMETER of aclk: signal is "ASSOCIATED_BUSIF mm:streamIn:buffersFeed";

	constant addrIncr: integer := burstLength*(wordWidth/8);
	constant bytesPerWord: integer := wordWidth/8;
	constant burstOrder: integer := integer(ceil(log2(real(burstLength))));
	constant wordOrder: integer := integer(ceil(log2(real(bytesPerWord))));
	constant pendingCounterWidth: integer := 20;

	signal reset1, reset2: std_logic;

	-- address generator
	constant wBytesPerBurst: unsigned(memAddrWidth-1 downto 0) := to_unsigned(addrIncr, memAddrWidth);
	signal wBurstIssued, wBurstIssuedNext: std_logic;
	signal mm_awaddr0: std_logic_vector(memAddrWidth-1 downto 0);
	signal mm_awvalid0, mm_r_ce: std_logic;
	signal allowNextFrame, frameDone: std_logic;

	signal aready, avalid: std_logic;
	signal aaddr: memAddr_t;
	signal wBurstPhase, wBurstPhaseNext: unsigned(burstOrder-1 downto 0);

	signal indicator_strobe: std_logic;
	signal indicator_buffer, currBuffer: bufferInfo;

	signal gateIn_tvalid, mm_wvalid0: std_logic;
	signal gateIdle: std_logic;
	signal frameTerminated: std_logic;
	signal wBurstIssued_history: std_logic_vector(3 downto 0) := "0000";

	-- keep count of how many bytes were issued in this frame
	signal currFrameBytes, currFrameBytesNext: bufLengthBytes_t;
	signal wroteWord: std_logic;

	-- data count
	
	-- set this to true if the total latency from write data to write response
	-- is always less than the smallest buffer's duration (usually 4KB);
	-- if false we will push pending buffers into a FIFO to deal with multiple
	-- buffers in the pipeline.
	constant useSimpleDataCount: boolean := true;

	signal prevBuffer: bufferInfo;
	signal prevBufferBytes: bufLengthBytes_t := (others=>'1');
	signal bvalid1: std_logic;

	signal bufsFIFOin, bufsFIFOout: std_logic_vector(memAddrWidth+bufLengthBytesWidth-1 downto 0);
	signal dcnt_tdata: bufferInfo;
	signal dcnt_tdatab: bufLengthBytes_t;
	signal dcnt_tready, dcnt_tvalid: std_logic;
	signal dcnt_bytes: memAddr_t;
	signal dcnt_currBuffer: bufferInfo;
	signal bufComplete: bufferInfo;
	signal bufComplete_strobe: std_logic;
begin
	reset1 <= reset when rising_edge(aclk);
	reset2 <= reset1 when rising_edge(aclk);

	-- #####################################
	-- address generator
	rAddrGen: entity axiPipeAddrGen
		generic map(burstLength=>burstLength, wordWidth=>wordWidth)
		port map(aclk=>aclk, reset=>reset,
			buffersFeed_data=>buffersFeed_tdata,
			buffersFeed_valid=>buffersFeed_tvalid,
			buffersFeed_ready=>buffersFeed_tready,
			aready=>aready,
			avalid=>avalid,
			aaddr=>aaddr,
			indicator_strobe=>indicator_strobe,
			indicator_buffer=>indicator_buffer,
			allowNextFrame=>allowNextFrame,
			frameDone=>frameDone,
			abort=>frameTerminated);

	wBurstIssuedNext <= aready and avalid;
	wBurstIssued <= wBurstIssuedNext when rising_edge(aclk);
	wBurstIssued_history <= wBurstIssued_history(wBurstIssued_history'left-1 downto 0)
							& wBurstIssued when rising_edge(aclk);

	currBuffer <= indicator_buffer when indicator_strobe='1' and rising_edge(aclk);

	-- permute addresses
	addrPerm_din <= aaddr;
	addrPerm_bufferInfo <= currBuffer;
g1: if userAddrPerm generate
		mm_awaddr0 <= std_logic_vector(addrPerm_dout) when mm_r_ce='1' and rising_edge(aclk);
		mm_awvalid0 <= avalid when mm_r_ce='1' and rising_edge(aclk);
	end generate;
g2: if not userAddrPerm generate
		mm_awaddr0 <= std_logic_vector(aaddr) when mm_r_ce='1' and rising_edge(aclk);
		mm_awvalid0 <= avalid when mm_r_ce='1' and rising_edge(aclk);
	end generate;
	mm_awaddr <= mm_awaddr0;
	mm_awvalid <= mm_awvalid0;
	mm_r_ce <= mm_awready or not mm_awvalid0;
	aready <= mm_r_ce;

	mm_awprot <= "001";
	mm_awlen <= std_logic_vector(to_unsigned(burstLength-1,4));

	wBurstPhaseNext <= (others=>'0') when wBurstPhase=burstLength-1 else
					wBurstPhase+1;
	wBurstPhase <= wBurstPhaseNext when mm_wvalid0='1' and mm_wready='1' and rising_edge(aclk);
	mm_wlast <= '1' when wBurstPhase=burstLength-1 else '0';
	mm_bready <= '1';



	-- #####################################
	-- data input side; only let data through when addresses are issued.
	-- we do not reset this module because doing so will violate axi transaction rules.
	--gate_write: entity axiDataGatingSimple
		--generic map(addrWidth=>memAddrWidth, wordWidth=>wordWidth)
		--port map(aclk=>aclk, reset=>'0', allowIssueBytes=>wBytesPerBurst, allowIssueEn=>wBurstIssued,
				--in_tvalid=>gateIn_tvalid, in_tready=>streamIn_tready, in_tdata=>streamIn_tdata, in_tlast=>streamIn_tlast,
				--out_tvalid=>mm_wvalid0, out_tready=>mm_wready, out_tdata=>mm_wdata,
				--idle=>gateIdle, frameTerminated=>frameTerminated, newFrame=>indicator_strobe);
	gate_write: entity axiDataGatingSimple
		generic map(addrWidth=>pendingCounterWidth, wordWidth=>wordWidth, incrBytes=>addrIncr)
		port map(aclk=>aclk, reset=>'0',
				allowIssue=>wBurstIssued,
				in_tvalid=>gateIn_tvalid, in_tready=>streamIn_tready, in_tdata=>streamIn_tdata, in_tlast=>streamIn_tlast,
				out_tvalid=>mm_wvalid0, out_tready=>mm_wready, out_tdata=>mm_wdata,
				idle=>gateIdle, frameTerminated=>frameTerminated, newFrame=>indicator_strobe);
	mm_wvalid <= mm_wvalid0;
	
	-- let the address generator move on to the next buffer if the data channel is idle
	-- and no addresses have been issued for 4 cycles
	allowNextFrame <= '1' when wBurstIssued_history="0000" and gateIdle='1' else '0';

	-- keep count of how many data words were issued for the current buffer
	wroteWord <= mm_wvalid0 and mm_wready when rising_edge(aclk);
	currFrameBytesNext <=
			to_unsigned(0, bufLengthBytesWidth) when indicator_strobe='1' else
			currFrameBytes + (wordWidth/8) when wroteWord='1' else
			currFrameBytes;
	currFrameBytes <= currFrameBytesNext when rising_edge(aclk);


	-- during reset we will issue junk data into axi write data pipe
	-- to match the number of addresses we already issued.
	-- the reset must last longer than the "write address acceptance"
	-- of the axi slave.
	gateIn_tvalid <= streamIn_tvalid or reset2;


	bvalid1 <= mm_bvalid when rising_edge(aclk);

g3: if useSimpleDataCount generate
		prevBuffer <= indicator_buffer when frameDone='1' and rising_edge(aclk);
		prevBufferBytes <= currFrameBytes when frameDone='1' and rising_edge(aclk);
		dcnt: entity axiPipeDataCountSimple
			generic map(addrIncr=>addrIncr)
			port map(aclk=>aclk,
					curBytes=>prevBufferBytes,
					bvalid=>bvalid1,
					irqOut=>irq);
	end generate;
g4: if not useSimpleDataCount generate
		-- when the current buffer is done push the bufferInfo and number of bytes issued
		-- to the buffers fifo
		bufsFIFOin <= bufferInfo_pack(indicator_buffer) &
				std_logic_vector(currFrameBytes);

		-- in-flight buffers FIFO
		bufsFIFO: entity oxiToAxiSkid
			generic map(width=>bufsFIFOin'length, depthOrder=>4)
			port map(aclk=>aclk,
					dout_tvalid=>dcnt_tvalid, dout_tready=>dcnt_tready, dout_tdata=>bufsFIFOout,
					din_tstrobe=>frameDone, din_tready=>open, din_tdata=>bufsFIFOin);
		
		dcnt_tdata <= to_bufferInfo(bufsFIFOout(bufsFIFOout'left downto bufsFIFOout'left-memAddrWidth+1));
		dcnt_tdatab <= unsigned(bufsFIFOout(dcnt_tdatab'range));

		-- data count
		dcnt: entity axiPipeDataCount
			port map(aclk=>aclk,
				buffersFeed_data=>dcnt_tdata,
				buffersFeed_sizeBytes=>dcnt_tdatab,
				buffersFeed_valid=>dcnt_tvalid,
				buffersFeed_ready=>dcnt_tready,
				currBuffer=>dcnt_currBuffer,
				currBuffer_valid=>open,
				bytesIssued=>dcnt_bytes,
				indicator_strobe=>bufComplete_strobe,
				indicator_buffer=>bufComplete);

		dcnt_bytes <= to_unsigned(bytesPerWord, memAddrWidth) when bvalid1='1' else
						to_unsigned(0, memAddrWidth);



		--streamIn_flags <= currBuffer.flags;
		irq <= bufComplete_strobe and bufComplete.shouldInterrupt when rising_edge(aclk);
	end generate;
end architecture;

