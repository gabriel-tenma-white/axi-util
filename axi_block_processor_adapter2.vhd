library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
USE ieee.math_real.log2;
USE ieee.math_real.ceil;
use work.dcfifo;

entity axiBlockProcessorAdapter2 is
	generic(frameSizeOrder: integer := 10;
			wordWidth: integer := 64;
			processorDelay: integer := 100);
	port(
			aclk: in std_logic;

			-- if asserted during a frame, flush the processor after this frame
			doFlush: in std_logic;

			-- when asserted, forces data phase to 0
			reset: in std_logic;

			-- axi stream input
			inp_tready: out std_logic;
			inp_tvalid: in std_logic;
			inp_tdata: in std_logic_vector(wordWidth-1 downto 0);

			-- axi stream output
			outp_tready: in std_logic;
			outp_tvalid: out std_logic;
			outp_tdata: out std_logic_vector(wordWidth-1 downto 0);

			-- block processor
			-- the processor accepts data when ce=1, and outputs data when ostrobe=1.
			-- ostrobe must be equal to ce or a delayed version of ce.
			bp_ce: out std_logic;
			bp_indata: out std_logic_vector(wordWidth-1 downto 0);
			bp_inphase: out unsigned(frameSizeOrder-1 downto 0);
			bp_ostrobe: in std_logic;
			bp_outdata: in std_logic_vector(wordWidth-1 downto 0)
		);
end entity;
architecture a of axiBlockProcessorAdapter2 is
	constant frameDuration: integer := 2**frameSizeOrder;
	constant armingDuration: integer := 32;

	-- istate and icounter together form the state of the input state machine.
	-- in some state groups the counter is ignored.
	type istate_t is (unarmed, arming, armed, running, flushing, wait0, wait1);
	--                   0        1      2       3        4        5      6
	signal istate, istateNext: istate_t := unarmed;
	signal icounter, icounterNext: unsigned(frameSizeOrder-1 downto 0);
	signal idoAdvance_running, idoAdvance_flushing: std_logic;


	-- ostate and ocounter together form the state of the output state machine.
	-- in some state groups the counter is ignored.
	type ostate_t is (unarmed, wait_arming, wait_pipeline, writing);
	--                   0        1              2            3
	signal ostate, ostateNext: ostate_t := unarmed;
	signal ocounter, ocounterNext: unsigned(frameSizeOrder-1 downto 0);
	signal odoAdvance: std_logic;

	signal reset2: std_logic;

	-- inter-state-machine signals
	signal frame_indicator, frame_indicator2, latchedFrmInd, flowcontrol_allow, flowcontrol_allow2: std_logic;

	-- fifo
	signal fifo_wready, fifo_wvalid, fifo_rvalid, fifo_rready: std_logic;
	signal fifo_wdata, fifo_rdata: std_logic_vector(wordWidth-1 downto 0);
begin
	reset2 <= reset when rising_edge(aclk);

	-- ####### input state machine
	istate <= istateNext when rising_edge(aclk);
	icounter <= icounterNext when rising_edge(aclk);
	istateNext <= unarmed when reset2='1' else
					arming when istate=unarmed and inp_tvalid='1' else
					running when istate=arming and icounter=(icounter'range=>'1') else
					flushing when istate=running and icounter=(icounter'range=>'1')
									and doFlush='1' and idoAdvance_running='1' else
					wait0 when istate=flushing and icounter=processorDelay-1
									and idoAdvance_flushing='1' else
					wait1 when istate=wait0 else
					unarmed when istate=wait1 else
					istate;

	icounterNext <= to_unsigned(frameDuration-armingDuration, frameSizeOrder) when istate=unarmed else
					icounter+1 when istate=arming else
					icounter+1 when istate=running and idoAdvance_running='1' else
					icounter+1 when istate=flushing and idoAdvance_flushing='1' else
					icounter;

	idoAdvance_running <= inp_tvalid and flowcontrol_allow2;
	idoAdvance_flushing <= flowcontrol_allow2;


	bp_ce <= '1' when istate=arming else
				idoAdvance_running when istate=running else
				idoAdvance_flushing when istate=flushing else
				'0';
	inp_tready <= flowcontrol_allow2 when istate=running else
					'0';
	frame_indicator <= not frame_indicator when istate=wait0 and rising_edge(aclk);
	frame_indicator2 <= frame_indicator when rising_edge(aclk);
	bp_indata <= inp_tdata;
	bp_inphase <= icounter;



	-- ####### output state machine
	ostate <= ostateNext when rising_edge(aclk);
	ocounter <= ocounterNext when rising_edge(aclk);
	ostateNext <= unarmed when reset2='1' else
					wait_arming when ostate=unarmed else
					wait_pipeline when ostate=wait_arming and ocounter=(ocounter'range=>'1')
										and odoAdvance='1' else
					writing when ostate=wait_pipeline and ocounter=processorDelay-1
									and odoAdvance='1' else
					unarmed when ostate=writing and ocounter=0
									and frame_indicator2 /= latchedFrmInd else
					ostate;
	ocounterNext <= to_unsigned(frameDuration-armingDuration, frameSizeOrder) when ostate=unarmed else
					to_unsigned(0, frameSizeOrder) when ostate=wait_pipeline and ocounter=processorDelay-1
														and odoAdvance='1' else
					ocounter+1 when odoAdvance='1' else
					ocounter;
	odoAdvance <= bp_ostrobe;
	latchedFrmInd <= frame_indicator2 when ostate=wait_pipeline and rising_edge(aclk);
	fifo_wvalid <= '1' when ostate=writing and odoAdvance='1' else
					'0';
	fifo_wdata <= bp_outdata;

	-- ####### FIFO
	fifo: entity dcfifo
		generic map(width=>wordWidth, depthOrder=>5, singleClock=>true)
		port map(rdclk=>aclk, wrclk=>aclk,
			rdvalid=>fifo_rvalid, rdready=>fifo_rready, rddata=>fifo_rdata,
			wrvalid=>fifo_wvalid, wrready=>fifo_wready, wrdata=>fifo_wdata);
	outp_tvalid <= fifo_rvalid;
	outp_tdata <= fifo_rdata;
	fifo_rready <= outp_tready;
	flowcontrol_allow <= outp_tready or (not fifo_rvalid);
	flowcontrol_allow2 <= flowcontrol_allow when rising_edge(aclk);
end a;
