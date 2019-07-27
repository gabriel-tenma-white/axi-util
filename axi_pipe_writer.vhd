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
use work.axiDataGating;

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

		-- streaming interface, input (write data to memory)
			streamIn_tvalid: in std_logic;
			streamIn_tready: out std_logic;
			streamIn_tdata: in std_logic_vector(wordWidth-1 downto 0);

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

	signal reset1, reset2: std_logic;

	-- address generator
	signal wBytesIssued: unsigned(memAddrWidth-1 downto 0);
	signal mm_awaddr0: std_logic_vector(memAddrWidth-1 downto 0);
	signal mm_awvalid0, mm_r_ce: std_logic;

	signal aready, avalid: std_logic;
	signal aaddr: memAddr_t;
	signal wBurstPhase, wBurstPhaseNext: unsigned(burstOrder-1 downto 0);

	signal indicator_strobe: std_logic;
	signal indicator_buffer, currBuffer: bufferInfo;

	signal gateIn_tvalid, mm_wvalid0: std_logic;
	
	-- data count
	signal bufsFIFOin, bufsFIFOout: std_logic_vector(memAddrWidth-1 downto 0);
	signal dcnt_tdata: bufferInfo;
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
			bytesIssued=>wBytesIssued, 
			buffersFeed_data=>buffersFeed_tdata,
			buffersFeed_valid=>buffersFeed_tvalid,
			buffersFeed_ready=>buffersFeed_tready,
			aready=>aready,
			avalid=>avalid,
			aaddr=>aaddr,
			indicator_strobe=>indicator_strobe,
			indicator_buffer=>indicator_buffer);

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


	-- in-flight buffers FIFO
	--bufsFIFO: entity dcfifo
		--generic map(width=>memAddrWidth, depthOrder=>5, singleClock=>true)
		--port map(rdclk=>aclk, wrclk=>aclk,
				--rdvalid=>dcnt_tvalid, rdready=>dcnt_tready, rddata=>bufsFIFOout,
				--wrvalid=>indicator_strobe, wrready=>open, wrdata=>bufsFIFOin);
	bufsFIFO: entity oxiToAxiSkid
		generic map(width=>memAddrWidth, depthOrder=>4)
		port map(aclk=>aclk,
				dout_tvalid=>dcnt_tvalid, dout_tready=>dcnt_tready, dout_tdata=>bufsFIFOout,
				din_tstrobe=>indicator_strobe, din_tready=>open, din_tdata=>bufsFIFOin);
	bufsFIFOin <= bufferInfo_pack(indicator_buffer);
	dcnt_tdata <= to_bufferInfo(bufsFIFOout);

	-- data count
	dcnt: entity axiPipeDataCount
		port map(aclk=>aclk,
			buffersFeed_data=>dcnt_tdata, buffersFeed_valid=>dcnt_tvalid, buffersFeed_ready=>dcnt_tready,
			currBuffer=>dcnt_currBuffer, currBuffer_valid=>open,
			bytesIssued=>dcnt_bytes, indicator_strobe=>bufComplete_strobe, indicator_buffer=>bufComplete);

	dcnt_bytes <= to_unsigned(bytesPerWord, memAddrWidth) when mm_bvalid='1' else
					to_unsigned(0, memAddrWidth);

	-- #####################################
	-- data input side; only let data through when addresses are issued.
	-- we do not reset this module because doing so will violate axi transaction rules.
	gate_write: entity axiDataGating
		generic map(addrWidth=>memAddrWidth, wordWidth=>wordWidth)
		port map(aclk=>aclk, reset=>'0', allowIssueBytes=>wBytesIssued,
				in_tvalid=>gateIn_tvalid, in_tready=>streamIn_tready, in_tdata=>streamIn_tdata,
				out_tvalid=>mm_wvalid0, out_tready=>mm_wready, out_tdata=>mm_wdata);
	mm_wvalid <= mm_wvalid0;

	-- during reset we will issue junk data into axi write data pipe
	-- to match the number of addresses we already issued.
	-- the reset must last longer than the "write address acceptance"
	-- of the axi slave.
	gateIn_tvalid <= streamIn_tvalid or reset2;


	--streamIn_flags <= currBuffer.flags;
	irq <= bufComplete_strobe and bufComplete.shouldInterrupt when rising_edge(aclk);
end architecture;

