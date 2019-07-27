library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
USE ieee.math_real.log2;
USE ieee.math_real.ceil;
use work.dcfifo;
use work.oxiToAxiSkid;
use work.axiPipe_types.all;
use work.axiPipeAddrGen;
use work.axiPipeDataCount2;

-- given a stream of frame start addresses, read bursts from memory to streamOut.
entity axiPipeReader is
	generic(burstLength: integer := 4;
			wordWidth: integer := 64;
			userAddrPerm: boolean := false);
	port(
			aclk, reset: in std_logic;

		-- buffers feed in
			buffersFeed_tdata: in bufferInfo;
			buffersFeed_tvalid: in std_logic;
			buffersFeed_tready: out std_logic;

		--axi memory mapped master, read side
			mm_arready: in std_logic;
			mm_arvalid: out std_logic;
			mm_araddr: out std_logic_vector(memAddrWidth-1 downto 0);
			mm_arprot: out std_logic_vector(2 downto 0);
			mm_arlen: out std_logic_vector(3 downto 0);

			mm_rvalid: in std_logic;
			mm_rready: out std_logic;
			mm_rdata: in std_logic_vector(wordWidth-1 downto 0);
		
		-- irq out, synchronous to aclk, one clock cycle pulse width
			irq: out std_logic;

		-- streaming interface, output (read data from memory)
		-- flags is the flags from the buffer associated with the current output word.
			streamOut_flags: out flags_t;
			streamOut_tvalid: out std_logic;
			streamOut_tready: in std_logic;
			streamOut_tdata: out std_logic_vector(wordWidth-1 downto 0);
			streamOut_tlast: out std_logic;

		-- user defined address permutation (optional)
			addrPerm_din: out memAddr_t;
			addrPerm_bufferInfo: out bufferInfo;
			addrPerm_dout: in memAddr_t := (others=>'0')
		);
end entity;
architecture a of axiPipeReader is
	attribute X_INTERFACE_PARAMETER : string;
	attribute X_INTERFACE_PARAMETER of aclk: signal is "ASSOCIATED_BUSIF mm:streamOut:buffersFeed";

	constant addrIncr: integer := burstLength*(wordWidth/8);
	constant bytesPerWord: integer := wordWidth/8;
	constant burstOrder: integer := integer(ceil(log2(real(burstLength))));

	-- address generator
	signal wBytesIssued: unsigned(memAddrWidth-1 downto 0);
	signal mm_araddr0: std_logic_vector(memAddrWidth-1 downto 0);
	signal mm_arvalid0, mm_r_ce: std_logic;

	signal aready, avalid: std_logic;
	signal aaddr: memAddr_t;

	signal indicator_strobe: std_logic;
	signal indicator_buffer, currBuffer: bufferInfo;
	
	-- data count
	signal bufsFIFOin, bufsFIFOout: std_logic_vector(memAddrWidth-1 downto 0);
	signal dcnt_bf_tdata: bufferInfo;
	signal dcnt_bf_tready, dcnt_bf_tvalid: std_logic;
	signal dout_tvalid_and_tready: std_logic;
	signal dcnt_currBuffer: bufferInfo;
	signal dout_tlast, tlast1, irq0: std_logic;
begin
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
		mm_araddr0 <= std_logic_vector(addrPerm_dout) when mm_r_ce='1' and rising_edge(aclk);
		mm_arvalid0 <= avalid when mm_r_ce='1' and rising_edge(aclk);
	end generate;
g2: if not userAddrPerm generate
		mm_araddr0 <= std_logic_vector(aaddr) when mm_r_ce='1' and rising_edge(aclk);
		mm_arvalid0 <= avalid when mm_r_ce='1' and rising_edge(aclk);
	end generate;
	mm_araddr <= mm_araddr0;
	mm_arvalid <= mm_arvalid0;
	mm_r_ce <= mm_arready or not mm_arvalid0;
	aready <= mm_r_ce;

	mm_arprot <= "001";
	mm_arlen <= std_logic_vector(to_unsigned(burstLength-1,4));
	

	-- in-flight buffers FIFO
	--bufsFIFO: entity dcfifo
		--generic map(width=>memAddrWidth, depthOrder=>5, singleClock=>true)
		--port map(rdclk=>aclk, wrclk=>aclk,
				--rdvalid=>dcnt_tvalid, rdready=>dcnt_tready, rddata=>bufsFIFOout,
				--wrvalid=>indicator_strobe, wrready=>open, wrdata=>bufsFIFOin);
	bufsFIFO: entity oxiToAxiSkid
		generic map(width=>memAddrWidth, depthOrder=>4)
		port map(aclk=>aclk,
				dout_tvalid=>dcnt_bf_tvalid, dout_tready=>dcnt_bf_tready, dout_tdata=>bufsFIFOout,
				din_tstrobe=>indicator_strobe, din_tready=>open, din_tdata=>bufsFIFOin);
	bufsFIFOin <= bufferInfo_pack(indicator_buffer);
	dcnt_bf_tdata <= to_bufferInfo(bufsFIFOout);

	-- data count
	dcnt: entity axiPipeDataCount2
		port map(aclk=>aclk,
			buffersFeed_data=>dcnt_bf_tdata,
			buffersFeed_valid=>dcnt_bf_tvalid,
			buffersFeed_ready=>dcnt_bf_tready,
			dout_tvalid_and_tready=>dout_tvalid_and_tready,
			dout_curBuffer=>dcnt_currBuffer, dout_tlast=>dout_tlast);

	dout_tvalid_and_tready <= mm_rvalid and streamOut_tready;

	-- #####################################
	-- read response
	streamOut_tvalid <= mm_rvalid;
	streamOut_tdata <= mm_rdata;
	streamOut_tlast <= dout_tlast;
	mm_rready <= streamOut_tready;
	streamOut_flags <= dcnt_currBuffer.flags;

	tlast1 <= dout_tlast when rising_edge(aclk);
	irq0 <= '1' when dout_tlast='1' and tlast1='0' and dcnt_currBuffer.shouldInterrupt='1' else '0';
	irq <= irq0 when rising_edge(aclk);
end architecture;

