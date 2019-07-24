library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

package axiMipmap_types is
	constant minMaxWidth: integer := 32;

	-- represents a range from lower to upper
	type minMax_t is record
		lower: signed(minMaxWidth-1 downto 0);
		upper: signed(minMaxWidth-1 downto 0);
	end record;

	type minMaxArray is array(integer range<>) of minMax_t;

    function to_minMax (lower,upper: signed) return minMax_t;
end package;

package body axiMipmap_types is
	function to_minMax (lower,upper: signed) return minMax_t is
		variable res: minMax_t;
	begin
		res.upper := resize(upper, minMaxWidth);
		res.lower := resize(lower, minMaxWidth);
		return res;
	end function;
end package body;

library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.axiMipmap_types.all;

entity axiMipmap_minMax is
	generic(channels, decimationOrder: integer);
	port(
			aclk, reset: in std_logic;
			in_tdata: in minMaxArray(channels-1 downto 0);
			in_tstrobe: in std_logic;
			
			out_tdata: out minMaxArray(channels-1 downto 0);
			out_tstrobe: out std_logic
		);
end entity;
architecture a of axiMipmap_minMax is
	signal reset1: std_logic;
	signal cnt, cntNext: unsigned(decimationOrder-1 downto 0) := (others=>'0');
	signal bounds: minMaxArray(channels-1 downto 0);
	signal lowerEnable, upperEnable: std_logic_vector(channels-1 downto 0);
	signal ostrobe, ostrobeNext: std_logic := '0';
begin
	reset1 <= reset when rising_edge(aclk);

	-- state machine
	cntNext <= (others=>'0') when reset1='1' else
	           cnt + 1 when in_tstrobe='1' else
	           cnt;
	cnt <= cntNext when rising_edge(aclk);

	-- find min/max
g1: for I in 0 to channels-1 generate
		lowerEnable(I) <= '0' when in_tstrobe='0' else
						'1' when cnt=0 else
						'1' when in_tdata(I).lower < bounds(I).lower else
						'0';
		upperEnable(I) <= '0' when in_tstrobe='0' else
						'1' when cnt=0 else
						'1' when in_tdata(I).upper > bounds(I).upper else
						'0';
		bounds(I).lower <= in_tdata(I).lower when lowerEnable(I)='1' and rising_edge(aclk);
		bounds(I).upper <= in_tdata(I).upper when upperEnable(I)='1' and rising_edge(aclk);
	end generate;

	out_tdata <= bounds;

	ostrobeNext <= '1' when cnt=(cnt'range=>'1') and in_tstrobe='1' else '0';
	ostrobe <= ostrobeNext when rising_edge(aclk);
	out_tstrobe <= ostrobe;
end a;
