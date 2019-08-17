library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.axiMipmap_types.all;
use work.axiMipmap_generator;

entity synthtest_axiMipmap is
	port(
			clk: in std_logic;
			din: in std_logic;
			dout: out std_logic);
end entity;
architecture a of synthtest_axiMipmap is
	constant inBits: integer := 35;
	constant outBits: integer := 66;
	constant selBits: integer := 7;

	signal sr1, srIn: signed(inBits-1 downto 0);
	signal din1, din2, din3, dout1, dout2, dout3: std_logic;

	signal tready: std_logic;
	signal mipmapIn, mipmapOut: minMaxArray(0 downto 0);
	signal mipmapOutStrobe, mipmapOutLast: std_logic;

	signal moduleOut, moduleOut1, srOut, srOutNext: signed(outBits-1 downto 0);
	signal sel: unsigned(selBits-1 downto 0);
begin
	-- input shift register
	din1 <= din when rising_edge(clk);
	din2 <= din1 when rising_edge(clk);
	din3 <= din2 when rising_edge(clk);
	sr1 <= sr1(sr1'left-1 downto 0) & din3 when rising_edge(clk);
	srIn <= sr1 when rising_edge(clk);


	tready <= srIn(34) when rising_edge(clk);
	mipmapIn(0).lower <= srIn(31 downto 0);
	mipmapIn(0).upper <= srIn(31 downto 0);

	inst: entity axiMipmap_generator
		generic map(channels=>1)
		port map(
			aclk=>clk, reset=>'0',
			in_tdata=>mipmapIn,
			in_tstrobe=>srIn(32),
			in_tlast=>srIn(33),
			
			out_tdata=>mipmapOut,
			out_tstrobe=>mipmapOutStrobe,
			out_tlast=>mipmapOutLast,
			out_tready=>tready);

	moduleOut(31 downto 0) <= mipmapOut(0).lower;
	moduleOut(63 downto 32) <= mipmapOut(0).upper;
	moduleOut(64) <= mipmapOutStrobe;
	moduleOut(65) <= mipmapOutLast;


	moduleOut1 <= moduleOut when rising_edge(clk);


	sel <= sel+1 when rising_edge(clk);
	srOutNext <= moduleOut1 when sel=0 else
				"0" & srOut(srOut'left downto 1);
	srOut <= srOutNext when rising_edge(clk);
	dout1 <= srOut(0) when rising_edge(clk);
	dout2 <= dout1 when rising_edge(clk);
	dout3 <= dout2 when rising_edge(clk);
	dout <= dout3 when rising_edge(clk);
end a;
