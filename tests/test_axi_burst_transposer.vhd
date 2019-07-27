--  Hello world program
library ieee;
library work;
use std.textio.all; -- Imports the standard textio package.
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.oxiToAxiBurstTransposer;
use work.axiBurstTransposer;

--  Defines a design entity, without any ports.
entity test_axiBurstTransposer is
end test_axiBurstTransposer;

architecture behaviour of test_axiBurstTransposer is
	constant withAxiWrapper: boolean := true;
	signal bytesIssued: unsigned(31 downto 0);
	
	subtype data_t is std_logic_vector(15 downto 0);
	subtype dataOut_t is std_logic_vector(15 downto 0);
	
	signal inData: data_t;
	signal inFlags, outFlags: std_logic_vector(0 downto 0);
	signal inClk, inpValid, inReady,inReady1,inReady2,inReady3: std_logic := '0';
	signal outData: dataOut_t;
	signal outValid, outReady: std_logic := '0';
	
	constant inClkHPeriod: time := 20.5 ns;
	
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
	function enableTranspose(index: integer) return boolean is
	begin
		return ((index/4)**3 mod 5) < 3;
	end function;
begin

g1: if withAxiWrapper generate
		inst: entity axiBurstTransposer generic map(width=>16)
			port map(inClk,
				inpValid, inReady, inData, inFlags,
				outValid, outReady, outData, outFlags);
	end generate;
g2: if not withAxiWrapper generate
		inst: entity oxiToAxiBurstTransposer generic map(width=>16,depthOrder=>5)
			port map(inClk,
				inpValid, inReady, inData,
				outValid, outReady, outData,
				inFlags(0));
	end generate;
	
	

	inReady1 <= inReady when rising_edge(inClk);
	inReady2 <= inReady1 when rising_edge(inClk);
	inReady3 <= inReady2 when rising_edge(inClk);


	-- feed data in
	process
		variable l : line;
		variable inpValue: integer := 0;
		variable expectValue: integer := 0;
		variable expectData: unsigned(15 downto 0);
	begin
		wait for inClkHPeriod; inClk <= '1'; wait for inClkHPeriod; inClk <= '0';
		wait for inClkHPeriod; inClk <= '1'; wait for inClkHPeriod; inClk <= '0';
		for I in 0 to 500 loop
		
			-- feed data in
			inpValid <= '0';
			
			if (I mod inputSpeed(I)) = 0 then
				inpValid <= '1';
				inData <= data_t(to_unsigned(inpValue,16));
				if enableTranspose(inpValue) then
					inFlags <= "1";
				else
					inFlags <= "0";
				end if;
				if withAxiWrapper then
					if inReady='1' then
						inpValue := inpValue+1;
					end if;
				else
					if inReady3='1' then
						inpValue := inpValue+1;
					end if;
				end if;
			end if;
			
			
			-- retrieve data
			if ((I+2) mod outputSpeed(I)) = 0 then
				outReady <= '1';
				expectData := to_unsigned(expectValue, 16);
				if enableTranspose(expectValue) then
					expectData := expectData(expectData'left downto 2) &
									expectData(0) & expectData(1);
				end if;
				if outValid='1' then
					assert expectData=unsigned(outData);
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
