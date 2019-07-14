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
			-- for one clock cycle will allow N additional bytes through
			allowIssueBytes: in unsigned(addrWidth-1 downto 0);
			
			-- input side
			in_tvalid: in std_logic;
			in_tready: out std_logic;
			in_tdata: in std_logic_vector(wordWidth-1 downto 0);
			
			-- output side
			out_tvalid: out std_logic;
			out_tready: in std_logic;
			out_tdata: out std_logic_vector(wordWidth-1 downto 0)
		);
end entity;
architecture a of axiDataGating is
	constant bytesPerWord: integer := wordWidth/8;
	constant wordSizeOrder: integer := integer(ceil(log2(real(bytesPerWord))));
	
	-- allowedBytes: the integral of allowIssueBytes
	-- missedBytes: number of bytes that were marked as issued, but
	-- 		either in_tvalid or out_tready was 0 during that cycle
	signal allowedBytes, allowedBytesTrunc, missedBytes: unsigned(addrWidth-1 downto 0);
	
	signal bytesIssued, bytesIssuedNext: unsigned(addrWidth-1 downto 0);
	signal bytesGoal: unsigned(addrWidth-1 downto 0);
	
	signal wantIssueData,wantIssueDataNext,willIssueData: std_logic;
	signal reset2: std_logic;
begin
	reset2 <= reset when rising_edge(aclk);
	
	-- accumulate allowIssueBytes
	allowedBytes <= allowedBytes+allowIssueBytes when rising_edge(aclk);
	
	-- round down to nearest multiple of the word size
	allowedBytesTrunc <= allowedBytes(allowedBytes'left downto wordSizeOrder) & (wordSizeOrder-1 downto 0 => '0');
	
	-- calculate goal
	bytesGoal <= allowedBytesTrunc+missedBytes when rising_edge(aclk);
	
	-- connect pipes, gated by wantIssueData
	out_tdata <= in_tdata;
	out_tvalid <= in_tvalid and wantIssueData;
	in_tready <= out_tready and wantIssueData;
	
	-- keep count of number of bytes issued; this isn't bytes actually issued but
	-- bytes we attempted to issue
	wantIssueDataNext <= '1' when bytesIssued /= bytesGoal else '0';
	bytesIssuedNext <= bytesGoal when reset2='1' else
						bytesIssued+bytesPerWord when wantIssueDataNext='1' else bytesIssued;
	bytesIssued <= bytesIssuedNext when rising_edge(aclk);
	
	wantIssueData <= wantIssueDataNext when rising_edge(aclk);
	willIssueData <= wantIssueData and in_tvalid and out_tready;
	
	-- keep count of the number of bytes marked as issued but weren't actually
	-- issued because either sender had no data or receiver was not ready
	missedBytes <= missedBytes+bytesPerWord when wantIssueData='1' and willIssueData='0' and rising_edge(aclk);
	
end a;
