--  Hello world program
library ieee;
library work;
use std.textio.all; -- Imports the standard textio package.
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.dcfifo2;


--  Defines a design entity, without any ports.
entity test_dcfifo2 is
end test_dcfifo2;

architecture behaviour of test_dcfifo2 is
	signal bytesIssued: unsigned(31 downto 0);
	
	subtype data_t is std_logic_vector(15 downto 0);
	subtype dataOut_t is std_logic_vector(31 downto 0);
	
	signal inData: data_t;
	signal inClk, inpValid, inReady: std_logic := '0';
	signal outData: dataOut_t;
	signal outClk, outValid, outReady: std_logic := '0';
	
begin
	inst: entity dcfifo2 generic map(16,32,4)
		port map(outClk,inClk,
			outValid, outReady, outData, open,
			inpValid, inReady, inData, open);
	
	-- feed data in
	process
		variable l : line;
		variable inpValue: integer := 0;
	begin
		wait for 1 ns; inClk <= '1'; wait for 1 ns; inClk <= '0';
		wait for 1 ns; inClk <= '1'; wait for 1 ns; inClk <= '0';
		for I in 0 to 500 loop
			inpValid <= '0';
			if (I mod 3) = 0 then
				inpValid <= '1';
				inData <= data_t(to_unsigned(inpValue,16));
				if inReady='1' then
					inpValue := inpValue+1;
				end if;
			else
				inpValid <= '0';
			end if;
			wait for 1 ns; inClk <= '1'; wait for 1 ns; inClk <= '0';
		end loop;
		
		wait;
	end process;
	
	-- retrieve data
	process
		variable l : line;
		variable expectValue: integer := 0;
		variable expectData: unsigned(31 downto 0) := (others=>'0');
	begin
		wait for 1 ns; outClk <= '1'; wait for 1 ns; outClk <= '0';
		wait for 1 ns; outClk <= '1'; wait for 1 ns; outClk <= '0';
		for I2 in 2 to 500 loop
			if (I2 mod 3) = 0 then
				outReady <= '1';
				expectData := to_unsigned(expectValue+1, 16) & to_unsigned(expectValue, 16);
				if outValid='1' then
					assert expectData=unsigned(outData);
					expectValue := expectValue+2;
				end if;
			else
				outReady <= '0';
			end if;
			wait for 1.5 ns; outClk <= '1'; wait for 1.5 ns; outClk <= '0';
		end loop;
		
		wait;
	end process;
end behaviour;
