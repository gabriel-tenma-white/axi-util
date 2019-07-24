--  Hello world program
library ieee;
library work;
use std.textio.all; -- Imports the standard textio package.
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.axiMipmap_generator;
use work.axiMipmap_types.all;


--  Defines a design entity, without any ports.
entity test_axiMipmap_generator is
end entity;

architecture behaviour of test_axiMipmap_generator is
	signal bytesIssued: unsigned(31 downto 0);
	
	subtype data_t is minMaxArray(0 downto 0);
	
	signal inData: data_t;
	signal clk, inpValid: std_logic := '0';
	signal outData: data_t;
	signal outStrobe, outReady: std_logic := '0';
begin
	inst: entity axiMipmap_generator
		generic map(channels=>1)
		port map(aclk=>clk, reset=>'0',
			in_tdata=>inData, in_tstrobe=>inpValid,
			out_tdata=>outData, out_tstrobe=>outStrobe, out_tready=>outReady);

	process
		variable l : line;
		variable inpValue, expectValue: integer := 0;
		variable expectData: signed(31 downto 0) := (others=>'0');
	begin
		wait for 0.5 ns; clk <= '1'; wait for 0.5 ns; clk <= '0';
		wait for 0.5 ns; clk <= '1'; wait for 0.5 ns; clk <= '0';
		for I in 0 to 8192 loop
		
			-- input data
			inpValid <= '0';
			if (I mod 5) /= 4 then
				inpValid <= '1';
				inData(0).lower <= to_signed(inpValue,32);
				inData(0).upper <= to_signed(inpValue,32);
				inpValue := inpValue+1;
			else
				inpValid <= '0';
			end if;
			
			-- output data
			--expectData := to_signed(expectValue, 32);
			if outStrobe='1' then
				--assert expectData=outData(0).upper;
				--expectValue := expectValue+1;
			end if;

			if (I mod 4) /= 3 then
				outReady <= '1';
			else
				outReady <= '0';
			end if;
			
			wait for 0.5 ns; clk <= '1'; wait for 0.5 ns; clk <= '0';
		end loop;
		
		wait;
	end process;
end behaviour;
