library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
USE ieee.math_real.log2;
USE ieee.math_real.ceil;

-- allow a set amount of data to pass through a pipe
entity axiDataGatingSimple is
	generic(addrWidth, wordWidth: integer;
			-- how many bytes to allow when allowIssue is pulsed
			incrBytes: integer);
	port(
			aclk, reset: in std_logic;
			
			-- every clock cycle that allowIssue=1, we will allow incrBytes
			-- additional bytes through the pipe
			allowIssue: in std_logic;
			
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
architecture a of axiDataGatingSimple is
    constant wordBytes: integer := wordWidth/8;
	constant wordSizeOrder: integer := integer(ceil(log2(real(wordBytes))));
	constant incrWords: integer := incrBytes/wordBytes;
	constant cntWidth: integer := addrWidth - wordSizeOrder;

	signal delta: integer;
	signal deltaNonzero: std_logic;
	signal allowedWords, allowedWordsNext: unsigned(cntWidth-1 downto 0) := (others=>'0');
	signal empty, empty1: std_logic := '1';
	signal almostEmpty, almostEmpty1: std_logic := '1';

	signal wantIssueData, wantIssueDataNext,willIssueData, insertMode, insertModeNext: std_logic := '0';
	signal wantIssueData_history: std_logic_vector(4 downto 0);
	signal reset2, idle0, newFrame1: std_logic;

	signal incrB, decrB, incrI, decrB1: boolean;
begin
	reset2 <= reset when rising_edge(aclk);
	newFrame1 <= newFrame when rising_edge(aclk);


	--process(aclk)
		--variable tmpAllowBytes: unsigned(addrWidth-1 downto 0);
	--begin
		--if rising_edge(aclk) then
			--tmpAllowBytes := allowedBytes;
			--if incrI then
				--tmpAllowBytes := tmpAllowBytes+incrBytes;
			--end if;
			--if incrB then
				--tmpAllowBytes := tmpAllowBytes+wordBytes;
			--end if;
			--if decrB then
				--tmpAllowBytes := tmpAllowBytes-wordBytes;
			--end if;
			--allowedBytes <= tmpAllowBytes;
		--end if;
	--end process;


	--aB1 <= allowedBytes when allowedBytes = 0 else
			--allowedBytes-wordBytes;
	--aB2 <= aB1+incrBytes when incrI else
			--aB1;
	--allowedBytesNext <= aB2+wordBytes when incrB else aB2;
	--allowedBytes <= allowedBytesNext when rising_edge(aclk);


	--allowedBytesNext <=
		--allowedBytes + incrBytes					when incrI and incrB and decrB else
		--allowedBytes + incrBytes + wordBytes		when incrI and incrB else
		--allowedBytes + incrBytes - wordBytes		when incrI and decrB else
		--allowedBytes + incrBytes					when incrI else
		--allowedBytes								when incrB and decrB else
		--allowedBytes + wordBytes					when incrB else
		--allowedBytes - wordBytes					when decrB else
		--allowedBytes;

	--allowedBytes <= allowedBytesNext when rising_edge(aclk);


	delta <=
		incrWords			when incrI and (incrB = decrB) else
		incrWords + 1		when incrI and incrB else
		incrWords - 1		when incrI else
		1					when incrB else
		-1;					--when decrB;
	deltaNonzero <=
		'0' when incrB and decrB and (not incrI) else
		'0' when (not incrB) and (not decrB) and (not incrI) else
		'1';

	allowedWords <= allowedWords+unsigned(to_signed(delta, allowedWords'length))
						when deltaNonzero='1' and rising_edge(aclk);

	empty <= '1' when allowedWords = 0 else '0';
	almostEmpty <= '1' when allowedWords <= 1 else '0';
	empty1 <= empty when rising_edge(aclk);
	almostEmpty1 <= almostEmpty when rising_edge(aclk);
	decrB1 <= decrB when rising_edge(aclk);

	decrB <= true when almostEmpty1='0' else
			true when empty1='0' and not decrB1 else
			false;

	-- counter
	--delta <=
		--incrBytes					when incrI and incrB and decrB else
		--incrBytes + wordBytes		when incrI and incrB else
		--incrBytes - wordBytes		when incrI and decrB else
		--incrBytes					when incrI else
		--0							when incrB and decrB else
		--wordBytes					when incrB else
		---wordBytes					when decrB else
		--0;
	--allowedBytes <= allowedBytes+unsigned(to_signed(delta, allowedBytes'length)) when rising_edge(aclk);


	incrI <= allowIssue='1';
	incrB <= (wantIssueData and not willIssueData)='1' when rising_edge(aclk);
	--decrB <= allowedBytes /= 0;
	wantIssueDataNext <= '1' when decrB else '0';
	wantIssueData <= wantIssueDataNext when rising_edge(aclk);

	-- connect pipes, gated by wantIssueData
	out_tdata <= in_tdata;
	out_tvalid <= (in_tvalid or insertMode) and wantIssueData;
	in_tready <= out_tready and wantIssueData and (not insertMode);
	willIssueData <= wantIssueData and (in_tvalid or insertMode) and out_tready;

	-- as soon as tlast is issued, enter "insert mode" (insert words into output stream)
	insertModeNext <= '1' when (in_tlast and in_tvalid and out_tready and wantIssueData)='1' else
						'0' when newFrame1='1' else
						insertMode;
	insertMode <= insertModeNext when rising_edge(aclk);
	frameTerminated <= insertMode;

	wantIssueData_history <=
		wantIssueData_history(wantIssueData_history'left-1 downto 0) & wantIssueData when rising_edge(aclk);
	idle0 <= '1' when wantIssueData_history="00000" else '0';
	idle <= idle0 when rising_edge(aclk);
end a;
