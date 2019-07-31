library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
USE ieee.math_real.log2;
USE ieee.math_real.ceil;

-- allow a set amount of data to pass through a pipe;
-- allowIssueBytes must always be a multiple of the word size in bytes
entity axiDataGating is
	generic(addrWidth: integer := 32;
			wordWidth: integer := 64);
	port(
			aclk, reset: in std_logic;
			
			-- this value is accumulated to determine how many bytes to
			-- let through the pipe; for example setting allowIssueBytes to N
			-- and allowIssueEn to '1' for one clock cycle will allow
			-- N additional bytes through
			allowIssueBytes: in unsigned(addrWidth-1 downto 0);
			allowIssueEn: in std_logic := '1';
			
			-- input side
			in_tvalid: in std_logic;
			in_tready: out std_logic;
			in_tdata: in std_logic_vector(wordWidth-1 downto 0);
			in_tlast: in std_logic;
			
			-- output side
			out_tvalid: out std_logic;
			out_tready: in std_logic;
			out_tdata: out std_logic_vector(wordWidth-1 downto 0);
			
			-- outputs high when all allowed bytes have passed
			idle: out std_logic;

			-- outputs high if we have received a tlast and are in blank insertion mode
			frameTerminated: out std_logic;

			-- setting this high forces exit from blank insertion mode; currently pending
			-- words are affected and will become sourced from the input stream
			newFrame: in std_logic := '1'
		);
end entity;
architecture a of axiDataGating is
	constant bytesPerWord: integer := wordWidth/8;
	constant wordSizeOrder: integer := integer(ceil(log2(real(bytesPerWord))));
	
	-- allowedBytes: the integral of allowIssueBytes
	-- missedBytes: number of bytes that were marked as issued, but
	-- 		either in_tvalid or out_tready was 0 during that cycle
	signal allowedBytes, allowedBytesNext, allowedBytesTrunc, missedBytes, missedBytesNext: unsigned(addrWidth-1 downto 0);
	
	signal bytesIssued, bytesIssuedNext: unsigned(addrWidth-1 downto 0);
	signal bytesGoal: unsigned(addrWidth-1 downto 0);
	
	signal wantIssueData,wantIssueDataNext,willIssueData, insertMode, insertModeNext: std_logic;
	signal wantIssueData_history: std_logic_vector(4 downto 0);
	signal reset1, reset2, idle0, newFrame1: std_logic;
begin
	reset1 <= reset when rising_edge(aclk);
	reset2 <= reset1 when rising_edge(aclk);
	newFrame1 <= newFrame when rising_edge(aclk);
	
	-- accumulate allowIssueBytes
	allowedBytesNext <= (others=>'0') when reset1='1' else
						allowedBytes+allowIssueBytes when allowIssueEn='1' else
						allowedBytes;
	allowedBytes <= allowedBytesNext when rising_edge(aclk);

	-- round down to nearest multiple of the word size
	allowedBytesTrunc <= allowedBytes(allowedBytes'left downto wordSizeOrder) & (wordSizeOrder-1 downto 0 => '0');
	
	-- calculate goal
	bytesGoal <= allowedBytesTrunc+missedBytes when rising_edge(aclk);
	
	-- connect pipes, gated by wantIssueData
	out_tdata <= in_tdata;
	out_tvalid <= (in_tvalid or insertMode) and wantIssueData;
	in_tready <= out_tready and wantIssueData and (not insertMode);

	-- as soon as tlast is issued, enter "insert mode" (insert words into output stream)
	insertModeNext <= '1' when (in_tlast and in_tvalid and out_tready and wantIssueData)='1' else
						'0' when newFrame1='1' else
						insertMode;
	insertMode <= insertModeNext when rising_edge(aclk);
	frameTerminated <= insertMode;

	-- keep count of number of bytes issued; this isn't bytes actually issued but
	-- bytes we attempted to issue
	wantIssueDataNext <= '1' when bytesIssued /= bytesGoal else '0';
	bytesIssuedNext <= (others=>'0') when reset2='1' else
						bytesIssued+bytesPerWord when wantIssueDataNext='1' else
						bytesIssued;
	bytesIssued <= bytesIssuedNext when rising_edge(aclk);
	
	wantIssueData <= wantIssueDataNext when rising_edge(aclk);
	willIssueData <= wantIssueData and (in_tvalid or insertMode) and out_tready;
	
	-- keep count of the number of bytes marked as issued but weren't actually
	-- issued because either sender had no data or receiver was not ready
	missedBytesNext <= (others=>'0') when reset1='1' else
						missedBytes+bytesPerWord when wantIssueData='1' and willIssueData='0' else
						missedBytes;
	missedBytes <= missedBytesNext when rising_edge(aclk);

	wantIssueData_history <=
		wantIssueData_history(wantIssueData_history'left-1 downto 0) & wantIssueData when rising_edge(aclk);
	idle0 <= '1' when wantIssueData_history="00000" else '0';
	idle <= idle0 when rising_edge(aclk);
end a;
