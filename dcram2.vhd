library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
package dcram2_types is
	function min1(a: integer; b: integer) return integer;
	function max1(a: integer; b: integer) return integer;
	function iif(cond: boolean; if_true, if_false: integer) return integer;
end package;
package body dcram2_types is
	function min1(a: integer; b: integer) return integer is
	begin
		if a>b then
			return b;
		else
			return a;
		end if;
	end function;
	function max1(a: integer; b: integer) return integer is
	begin
		if a<b then
			return b;
		else
			return a;
		end if;
	end function;
	
	function iif(cond: boolean; if_true,if_false: integer) return integer is
	begin
		if cond then
			return if_true;
		else
			return if_false;
		end if;
	end function;
end dcram2_types;

library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
USE ieee.math_real.log2;
USE ieee.math_real.round;
use work.dcram2_types.all;

-- dual clock dual port ram
-- DELAY: 1 cycle if outputRegistered=false, 2 cycles if outputRegistered=true
entity dcram2 is
	generic(widthRead, widthWrite: integer := 8;
				-- real depth is 2^depthOrderWrite words of widthWrite bits
				depthOrderWrite: integer := 9;
				outputRegistered: boolean := false;
				-- 0: auto; 1: block; 2: lut
				ramType: integer := 0);
	port(rdclk,wrclk: in std_logic;
			-- read side; synchronous to rdclk
			rden: in std_logic;
			rdaddr: in unsigned(depthOrderWrite+integer(round(log2(real(widthWrite)/real(widthRead))))-1 downto 0);
			rddata: out std_logic_vector(widthRead-1 downto 0);
			
			--write side; synchronous to wrclk
			wren: in std_logic;
			wraddr: in unsigned(depthOrderWrite-1 downto 0);
			wrdata: in std_logic_vector(widthWrite-1 downto 0)
			);
end entity;
architecture a of dcram2 is
	constant depthRatioOrder: integer := integer(round(log2(real(widthWrite)/real(widthRead))));
	constant depthOrderRead: integer := depthOrderWrite + depthRatioOrder;
	
	constant depthWrite: integer := 2**depthOrderWrite;
	constant depthRead: integer := 2**depthOrderRead;
	constant largerDepth: integer := max1(depthWrite, depthRead);
	constant ramWidth: integer := min1(widthWrite, widthRead);
	constant readAggregation: integer := widthRead/ramWidth;
	constant writeAggregation: integer := widthWrite/ramWidth;
	constant writeAggregationOrder: integer := integer(round(log2(real(writeAggregation))));

	--ram
	type ram1t is array(largerDepth-1 downto 0) of
		std_logic_vector(ramWidth-1 downto 0);
	signal ram1: ram1t;
	
	signal tmpdata: std_logic_vector(widthRead-1 downto 0);

	function ram_style_str(t, depthOrderWrite: integer) return string is
	begin
		if t=0 then
			if depthOrderWrite >= 8 then
				return "block";
			end if;
			if depthOrderWrite <= 5 then
				return "distributed";
			end if;
			return "";
		elsif t=1 then
			return "block";
		else
			return "distributed";
		end if;
	end function;
	attribute ram_style : string;
	attribute ram_style of ram1 : signal is ram_style_str(ramType, depthOrderWrite);
begin
	--inferred ram
	process(rdclk)
		variable i: integer;
	begin
		if rising_edge(rdclk) then
			if rden='1' then
				if readAggregation = 1 then
					tmpdata <= ram1(to_integer(rdaddr));
				else
					for i in 0 to readAggregation-1 loop
						tmpdata((i+1)*ramWidth-1 downto i*ramWidth)
							<= ram1(to_integer(rdaddr)*readAggregation + i);
					end loop;
				end if;
			end if;
		end if;
	end process;

g1:	if outputRegistered generate
		rddata <= tmpdata when rising_edge(rdclk);
	end generate;
g2:	if not outputRegistered generate
		rddata <= tmpdata;
	end generate;
	
	process(wrclk)
	begin
		if(rising_edge(wrclk)) then
			if(wren='1') then
				if writeAggregation = 1 then
					ram1(to_integer(wraddr)) <= wrdata;
				else
					for i in 0 to writeAggregation-1 loop
						ram1(to_integer(wraddr & to_unsigned(i, writeAggregationOrder)))
							<= wrdata((i+1)*ramWidth-1 downto i*ramWidth);
					end loop;
				end if;
			end if;
		end if;
	end process;
	
end a;
