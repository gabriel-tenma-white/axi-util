library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
-- dual clock dual port ram
-- DELAY: 1 cycle if outputRegistered=false, 2 cycles if outputRegistered=true
entity dcram is
	generic(width: integer := 8;
				-- real depth is 2^depth_order
				depthOrder: integer := 9;
				outputRegistered: boolean := false;
				-- 0: auto; 1: block; 2: lut
				ramType: integer := 0);
	port(rdclk,wrclk: in std_logic;
			-- read side; synchronous to rdclk
			rden: in std_logic;
			rdaddr: in unsigned(depthOrder-1 downto 0);
			rddata: out std_logic_vector(width-1 downto 0);
			
			--write side; synchronous to wrclk
			wren: in std_logic;
			wraddr: in unsigned(depthOrder-1 downto 0);
			wrdata: in std_logic_vector(width-1 downto 0)
			);
end entity;
architecture a of dcram is
	constant depth: integer := 2**depthOrder;
	
	--ram
	type ram1t is array(depth-1 downto 0) of
		std_logic_vector(width-1 downto 0);
	signal ram1: ram1t;
	
	signal tmpdata: std_logic_vector(width-1 downto 0);

	function ram_style_str(t,depthOrder: integer) return string is
	begin
		if t=0 then
			if depthOrder <= 5 then
				return "distributed";
			end if;
			return "";
		elsif t=1 then
			return "block";
		else
			return "distributed";
		end if;
	end function;
	--type ramStr_t is array(0 to 2) of string(10 downto 0);
	--constant ramTypeStr : ramStr_t := ("           ", "block      ", "distributed");
	attribute ram_style : string;
	attribute ram_style of ram1 : signal is ram_style_str(ramType, depthOrder);
begin
	--inferred ram
	process(rdclk)
	begin
		if rising_edge(rdclk) then
			if rden='1' then
				tmpdata <= ram1(to_integer(rdaddr));
			end if;
		end if;
	end process;
	
g1:	if outputRegistered generate
		rddata <= tmpdata when rden='1' and rising_edge(rdclk);
	end generate;
g2:	if not outputRegistered generate
		rddata <= tmpdata;
	end generate;
	
	process(wrclk)
	begin
		 if(rising_edge(wrclk)) then
			  if(wren='1') then
					ram1(to_integer(wraddr)) <= wrdata;
			  end if;
		 end if;
	end process;
end a;
