library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
USE ieee.math_real.log2;
USE ieee.math_real.ceil;
use work.dcfifo;
use work.axiPipe_types.all;
use work.axiConfigRegisters_types.all;
use work.axiConfigRegisters;
use work.greyCDCSync;
use work.axiMMFIFO;
use work.axiPipeReader;
use work.axiPipeWriter;
use work.axiPipeAddrInterleaver;

-- allows streaming data to/from hps

-- register map (32 bit words)
-- 0		total number of bytes written to memory
-- 1		current writing address
-- 2		total number of bytes read from memory
-- 3		current reading address
-- 4		write buffers fifo (write to this address to enqueue;
--				reads return number of fifo entries free)
-- 5		read buffers fifo

-- if customReadAddrPermutation/customWriteAddrPermutation is false,
-- by default flags(1..0) is used to select a built in address permutation;
-- flags(1) enables interleaving and flags(0) enables transpose;
-- matrix width and height are set by interleaveRowBits.
-- This only affects the ordering of the bursts;
-- data within a burst is never reordered.
entity axiPipeRW is
	generic(burstLength: integer := 4;
			wordWidth: integer := 64;
			-- when in interleaved address mode, this sets the row size
			interleaveRowBits: integer := 9;
			customReadAddrPermutation: boolean := false;
			customWriteAddrPermutation: boolean := false);
	port(
			irqOut: out std_logic; -- synchronous to aclk, one pulse per interrupt

		--axi memory mapped slave, read side
			ctrl_aclk,ctrl_rst: in std_logic;
			ctrl_arready: out std_logic;
			ctrl_arvalid: in std_logic;
			ctrl_araddr: in std_logic_vector(7 downto 0);
			ctrl_arprot: in std_logic_vector(2 downto 0);

			ctrl_rvalid: out std_logic;
			ctrl_rready: in std_logic;
			ctrl_rdata: out std_logic_vector(31 downto 0);

		--axi memory mapped slave, write side
			ctrl_awaddr: in std_logic_vector(7 downto 0);
			ctrl_awprot: in std_logic_vector(2 downto 0);
			ctrl_awvalid: in std_logic;
			ctrl_awready: out std_logic;
			ctrl_wdata: in std_logic_vector(31 downto 0);
			ctrl_wvalid: in std_logic;
			ctrl_wready: out std_logic;

			ctrl_bvalid: out std_logic;
			ctrl_bready: in std_logic;
			ctrl_bresp: out std_logic_vector(1 downto 0);

		--axi memory mapped master, read side
			mm_aclk,mm_rst: in std_logic;
			mm_arready: in std_logic;
			mm_arvalid: out std_logic;
			mm_araddr: out std_logic_vector(memAddrWidth-1 downto 0);
			mm_arprot: out std_logic_vector(2 downto 0);
			mm_arlen: out std_logic_vector(3 downto 0);

			mm_rvalid: in std_logic;
			mm_rready: out std_logic;
			mm_rdata: in std_logic_vector(wordWidth-1 downto 0);

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

		-- axi stream input
			inp_tready: out std_logic;
			inp_tvalid: in std_logic;
			inp_tdata: in std_logic_vector(wordWidth-1 downto 0);

		-- axi stream output
			outp_tready: in std_logic;
			outp_tvalid: out std_logic;
			outp_tdata: out std_logic_vector(wordWidth-1 downto 0);
			outp_tuser: out std_logic_vector(flagsWidth-1 downto 0);

		-- read/write address permutation
			readAddrPermIn: out std_logic_vector(memAddrWidth-1 downto 0);
			readAddrPermFlags: out std_logic_vector(flagsWidth-1 downto 0);
			readAddrPermOut: in std_logic_vector(memAddrWidth-1 downto 0) := (others=>'0');
			writeAddrPermIn: out std_logic_vector(memAddrWidth-1 downto 0);
			writeAddrPermFlags: out std_logic_vector(flagsWidth-1 downto 0);
			writeAddrPermOut: in std_logic_vector(memAddrWidth-1 downto 0) := (others=>'0')
		);
end entity;
architecture a of axiPipeRW is
	attribute X_INTERFACE_PARAMETER : string;
	attribute X_INTERFACE_PARAMETER of mm_aclk: signal is "ASSOCIATED_BUSIF mm:inp:outp";
	attribute X_INTERFACE_INFO : string;
	attribute X_INTERFACE_INFO of inp_tvalid: signal is "xilinx.com:interface:axis_rtl:1.0 inp tvalid";
	attribute X_INTERFACE_INFO of inp_tready: signal is "xilinx.com:interface:axis_rtl:1.0 inp tready";
	attribute X_INTERFACE_INFO of inp_tdata: signal is "xilinx.com:interface:axis_rtl:1.0 inp tdata";
	attribute X_INTERFACE_INFO of outp_tvalid: signal is "xilinx.com:interface:axis_rtl:1.0 outp tvalid";
	attribute X_INTERFACE_INFO of outp_tready: signal is "xilinx.com:interface:axis_rtl:1.0 outp tready";
	attribute X_INTERFACE_INFO of outp_tdata: signal is "xilinx.com:interface:axis_rtl:1.0 outp tdata";
	attribute X_INTERFACE_INFO of outp_tuser: signal is "xilinx.com:interface:axis_rtl:1.0 outp tuser";

	constant wordSizeOrder: integer := 3;
	constant addrIncr: integer := burstLength*(wordWidth/8);
	constant bytesPerWord: integer := wordWidth/8;
	constant burstOrder: integer := integer(ceil(log2(real(burstLength))));

	-- config registers
	signal regdata,regdataRead: regdata_t(7 downto 0);
	signal ctrl_awready0, ctrl_wready0: std_logic;
	signal totalWritten, totalWritten_ctrlClk, totalRead: unsigned(memAddrWidth-1 downto 0) := (others=>'0');
	
	-- control feed pipes
	signal readBuffersFeed_data0, writeBuffersFeed_data0: std_logic_vector(memAddrWidth-1 downto 0);
	signal readBuffersFeed_data, writeBuffersFeed_data: bufferInfo;
	signal readBuffersFeed_valid,writeBuffersFeed_valid: std_logic;
	signal readBuffersFeed_ready,writeBuffersFeed_ready: std_logic;
	signal wFIFOwrroom, rFIFOwrroom: unsigned(31 downto 0);
	signal wFIFOwrroom_ctrlClk, rFIFOwrroom_ctrlClk: unsigned(31 downto 0);
	
	-- memory write address generator
	signal mm_awaddr0: std_logic_vector(memAddrWidth-1 downto 0);
	signal mm_awaddr_ctrlClk: unsigned(memAddrWidth-1 downto 0);
	signal wBytesIssued,totalIssued: unsigned(memAddrWidth-1 downto 0);
	
	signal wBurstPhase, wBurstPhaseNext: unsigned(burstOrder-1 downto 0);
	
	signal mm_wvalid0: std_logic;
	
	-- address permutation
	signal ap1_din, ap2_din, ap1_dout, ap2_dout: memAddr_t;
	signal ap1_bufferInfo, ap2_bufferInfo: bufferInfo;

	-- irq
	signal readerIRQ, writerIRQ: std_logic;
begin
	--coreClk <= aclk;
	
	
	-- #####################################
	-- config registers and read/write buffers queue
	ctrl_awready <= ctrl_awready0;
	ctrl_wready <= ctrl_wready0;
	regs: entity axiConfigRegisters
		port map(ctrl_aclk, ctrl_rst, ctrl_arready, ctrl_arvalid,
			ctrl_araddr, ctrl_arprot, ctrl_rvalid, ctrl_rready,
			ctrl_rdata, ctrl_awaddr, ctrl_awprot, ctrl_awvalid,
			ctrl_awready, ctrl_wdata, ctrl_wvalid, ctrl_wready,
			ctrl_bvalid, ctrl_bready, ctrl_bresp, regdata, regdataRead);
	
	cdc1: entity greyCDCSync generic map(width=>32)
		port map(mm_aclk, ctrl_aclk, unsigned(mm_awaddr0), mm_awaddr_ctrlClk);
	cdc3: entity greyCDCSync generic map(width=>32)
		port map(mm_aclk, ctrl_aclk, totalWritten, totalWritten_ctrlClk);
	
	regdataread(0) <= std_logic_vector(totalWritten_ctrlClk);
	regdataRead(1) <= std_logic_vector(mm_awaddr_ctrlClk);
	regdataRead(4) <= std_logic_vector(wFIFOwrroom_ctrlClk);
	regdataRead(5) <= std_logic_vector(rFIFOwrroom_ctrlClk);
	
	wFIFOwrroom_ctrlClk <= wFIFOwrroom when rising_edge(ctrl_aclk);
	rFIFOwrroom_ctrlClk <= rFIFOwrroom when rising_edge(ctrl_aclk);
	
	wBufFIFO: entity axiMMFIFO generic map(myAddress=>4)
		port map(ctrl_aclk, ctrl_awaddr, ctrl_awvalid, ctrl_awready0,
			ctrl_wdata, ctrl_wvalid, ctrl_wready0, wFIFOwrroom,
			mm_aclk, writeBuffersFeed_ready, writeBuffersFeed_valid,
			writeBuffersFeed_data0);
	rBufFIFO: entity axiMMFIFO generic map(myAddress=>5)
		port map(ctrl_aclk, ctrl_awaddr, ctrl_awvalid, ctrl_awready0,
			ctrl_wdata, ctrl_wvalid, ctrl_wready0, rFIFOwrroom,
			mm_aclk, readBuffersFeed_ready, readBuffersFeed_valid,
			readBuffersFeed_data0);

	writeBuffersFeed_data <= to_bufferInfo(writeBuffersFeed_data0);
	readBuffersFeed_data <= to_bufferInfo(readBuffersFeed_data0);



	-- #####################################
	-- AXI memory reader and writer
	
	reader: entity axiPipeReader
		generic map(burstLength=>burstLength, wordWidth=>wordWidth, userAddrPerm=>true)
		port map(aclk=>mm_aclk, reset=>mm_rst,
			buffersFeed_tdata=>readBuffersFeed_data,
			buffersFeed_tvalid=>readBuffersFeed_valid,
			buffersFeed_tready=>readBuffersFeed_ready,
			mm_arready=>mm_arready, mm_arvalid=>mm_arvalid, mm_araddr=>mm_araddr,
			mm_arprot=>mm_arprot, mm_arlen=>mm_arlen,
			mm_rvalid=>mm_rvalid, mm_rready=>mm_rready, mm_rdata=>mm_rdata,
			
			addrPerm_din=>ap1_din,
			addrPerm_bufferInfo=>ap1_bufferInfo,
			addrPerm_dout=>ap1_dout,
			
			irq=>readerIRQ,
			
			streamOut_flags=>outp_tuser,
			streamOut_tvalid=>outp_tvalid,
			streamOut_tready=>outp_tready,
			streamOut_tdata=>outp_tdata);
	
	writer: entity axiPipeWriter
		generic map(burstLength=>burstLength, wordWidth=>wordWidth, userAddrPerm=>true)
		port map(aclk=>mm_aclk, reset=>mm_rst,
			buffersFeed_tdata=>writeBuffersFeed_data,
			buffersFeed_tvalid=>writeBuffersFeed_valid,
			buffersFeed_tready=>writeBuffersFeed_ready,
			mm_awaddr=>mm_awaddr, mm_awprot=>mm_awprot, mm_awlen=>mm_awlen,
			mm_awvalid=>mm_awvalid, mm_awready=>mm_awready, mm_wdata=>mm_wdata,
			mm_wlast=>mm_wlast, mm_wvalid=>mm_wvalid, mm_wready=>mm_wready,
			mm_bvalid=>mm_bvalid, mm_bready=>mm_bready,
			
			addrPerm_din=>ap2_din,
			addrPerm_bufferInfo=>ap2_bufferInfo,
			addrPerm_dout=>ap2_dout,
			
			irq=>writerIRQ,

			streamIn_tvalid=>inp_tvalid,
			streamIn_tready=>inp_tready,
			streamIn_tdata=>inp_tdata);
	
	totalWritten <= totalWritten+addrIncr when mm_bvalid='1' and rising_edge(mm_aclk);

	readAddrPermIn <= std_logic_vector(ap1_din);
	readAddrPermFlags <= ap1_bufferInfo.flags;
g1: if not customReadAddrPermutation generate
		interleaver1: entity axiPipeAddrInterleaver
			generic map(addrBits=>memAddrWidth, rowBits=>interleaveRowBits,
				burstBits=>(burstOrder+wordSizeOrder))
			port map(addrIn=>ap1_din, addrOut=>ap1_dout,
				doTranspose=>ap1_bufferInfo.flags(0),
				doInterleave=>ap1_bufferInfo.flags(1));
	end generate;
g2: if customReadAddrPermutation generate
		ap1_dout <= memAddr_t(readAddrPermOut);
	end generate;

	writeAddrPermIn <= std_logic_vector(ap2_din);
	writeAddrPermFlags <= ap2_bufferInfo.flags;
g3: if not customWriteAddrPermutation generate
		interleaver2: entity axiPipeAddrInterleaver
			generic map(addrBits=>memAddrWidth, rowBits=>interleaveRowBits,
				burstBits=>(burstOrder+wordSizeOrder))
			port map(addrIn=>ap2_din, addrOut=>ap2_dout,
				doTranspose=>ap2_bufferInfo.flags(0),
				doInterleave=>ap2_bufferInfo.flags(1));
	end generate;
g4: if customWriteAddrPermutation generate
		ap2_dout <= memAddr_t(writeAddrPermOut);
	end generate;

end architecture;

