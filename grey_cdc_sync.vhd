library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.greycodeEnc;
use work.greycodeDec;
use work.cdcSync;
-- cross clock domain sync with grey coding
entity greycdcsync is
	generic(width: integer := 8;
				stages: integer := 3;
				inputRegistered: boolean := true);
	port(srcclk,dstclk: in std_logic;
			datain: in unsigned(width-1 downto 0);
			dataout: out unsigned(width-1 downto 0));
end entity;
architecture a of greyCDCSync is
	signal datain1,dataout0: unsigned(width-1 downto 0) := (others=>'0');
	signal grey0,greyCDCSyncAsyncSource,greyCDCSyncAsyncTarget: std_logic_vector(width-1 downto 0) := (others=>'0');
begin
g1: if inputRegistered generate
		datain1 <= datain when rising_edge(srcclk);
	end generate;
g2: if not inputRegistered generate
		datain1 <= datain;
	end generate;

	-- apply grey coding
	greyEnc: entity greycodeEnc generic map(width=>width)
		port map(datain1,grey0);
	greyCDCSyncAsyncSource <= grey0 when rising_edge(srcclk);

	-- sample onto dst clk
	greyCDCSyncInst: entity cdcSync generic map(width=>width, stages=>stages)
		port map(dstclk, greyCDCSyncAsyncSource, greyCDCSyncAsyncTarget);
	-- grey decode & sample
	greyDec: entity greycodeDec generic map(width=>width)
		port map(greyCDCSyncAsyncTarget,dataout0);
	dataout <= dataout0 when rising_edge(dstclk);
end a;
