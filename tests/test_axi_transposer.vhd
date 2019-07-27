--  Hello world program
library ieee;
library work;
use std.textio.all; -- Imports the standard textio package.
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.axiTransposer;

--  Defines a design entity, without any ports.
entity test_axiTransposer is
end test_axiTransposer;

architecture behaviour of test_axiTransposer is
	constant rowsOrder: integer := 2;
	constant colsOrder: integer := 3;
	constant depthOrder: integer := rowsOrder+colsOrder;
	subtype data_t is std_logic_vector(15 downto 0);
	subtype dataOut_t is std_logic_vector(15 downto 0);
	
	signal inData: data_t;
	signal inClk, inpValid, inReady,inReady1,inReady2,inReady3: std_logic := '0';
	signal outData: dataOut_t;
	signal inFlags, outFlags: std_logic_vector(3 downto 0);
	signal outValid, outReady: std_logic := '0';
	
	constant inClkHPeriod: time := 0.5 ns;
	
	function inputSpeed(I: integer) return integer is
	begin
		if I<200 then
			return 5;
		elsif I<400 then
			return 1;
		elsif I<600 then
			return 7;
		elsif I<800 then
			return 1;
		else
			return 1;
		end if;
	end function;
	function outputSpeed(I: integer) return integer is
	begin
		if I<200 then
			return 5;
		elsif I<400 then
			return 6;
		elsif I<600 then
			return 1;
		elsif I<800 then
			return 2;
		else
			return 1;
		end if;
	end function;
	function bitPermute(din: unsigned) return unsigned is
	begin
		return rotate_left(din, colsOrder);
	end function;
begin

	inst: entity axiTransposer
		generic map(wordWidth=>16, tuserWidth=>4, rowsOrder=>rowsOrder, colsOrder=>colsOrder)
		port map(inClk, '0',
			inpValid, inReady, inData, inFlags,
			outValid, outReady, outData, outFlags);
	inFlags <= inData(depthOrder+1 downto depthOrder) & "01";


	-- feed data in
	process
		variable l : line;
		variable inpValue: integer := 0;
		variable expectValue: integer := 0;
		variable expectData: unsigned(15 downto 0);
	begin
		wait for inClkHPeriod; inClk <= '1'; wait for inClkHPeriod; inClk <= '0';
		wait for inClkHPeriod; inClk <= '1'; wait for inClkHPeriod; inClk <= '0';
		for I in 0 to 1000 loop
			-- feed data in
			inpValid <= '0';
			if (I mod inputSpeed(I)) = 0 then
				inpValid <= '1';
				inData <= data_t(to_unsigned(inpValue,16));
				if inReady='1' then
					inpValue := inpValue+1;
				end if;
			end if;
			
			-- retrieve data
			if ((I+2) mod outputSpeed(I)) = 0 then
				outReady <= '1';
				expectData := to_unsigned(expectValue, 16);
				expectData(depthOrder-1 downto 0) := bitPermute(expectData(depthOrder-1 downto 0));
				if outValid='1' then
					assert expectData=unsigned(outData)
						report "index " & integer'image(expectValue) & ", expected "
							& integer'image(to_integer(unsigned(expectData))) & ", got "
							& integer'image(to_integer(unsigned(outData)));
					assert outFlags(3 downto 2) = outData(depthOrder+1 downto depthOrder);
					expectValue := expectValue+1;
				end if;
			else
				outReady <= '0';
			end if;
			
			wait for inClkHPeriod; inClk <= '1'; wait for inClkHPeriod; inClk <= '0';
		end loop;
		
		wait;
	end process;
end behaviour;
