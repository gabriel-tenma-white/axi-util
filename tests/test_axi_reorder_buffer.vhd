--  Hello world program
library ieee;
library work;
use std.textio.all; -- Imports the standard textio package.
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.axiReorderBuffer;

--  Defines a design entity, without any ports.
entity test_axiReorderBuffer is
end test_axiReorderBuffer;

architecture behaviour of test_axiReorderBuffer is
	constant doBitReverse: boolean := true;
	
	subtype data_t is std_logic_vector(15 downto 0);
	subtype dataOut_t is std_logic_vector(15 downto 0);
	
	signal inData: data_t;
	signal inClk, inpValid, inReady,inReady1,inReady2,inReady3: std_logic := '0';
	signal outData: dataOut_t;
	signal outValid, outReady: std_logic := '0';
	signal outFlags: std_logic_vector(1 downto 0);
	
	signal bitPermIn0, bitPermIn1: unsigned(4 downto 0);
	signal bitPermCount0, bitPermCount1: unsigned(0 downto 0);
	signal bitPermOut0, bitPermOut1: unsigned(4 downto 0);
	
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
	function bitReverse(din: unsigned) return unsigned is
		variable dout: unsigned(din'range);
	begin
		for I in din'range loop
			dout(I) := din(din'left-I);
		end loop;
		return dout;
	end function;
begin

	inst: entity axiReorderBuffer
		generic map(wordWidth=>16, tuserWidth=>2, depthOrder=>5, repPeriod=>2)
		port map(inClk, '0',
			inpValid, inReady, inData, inData(6 downto 5),
			outValid, outReady, outData, outFlags,
			bitPermIn0, bitPermIn1,
			bitPermCount0, bitPermCount1,
			bitPermOut0, bitPermOut1);

g1: if doBitReverse generate
		bitPermOut0 <= bitPermIn0 when bitPermCount0(0)='0' else
					bitReverse(bitPermIn0);
		bitPermOut1 <= bitPermIn1 when bitPermCount1(0)='0' else
					bitReverse(bitPermIn1);
	end generate;
g2: if not doBitReverse generate
		bitPermOut0 <= bitPermIn0;
		bitPermOut1 <= bitPermIn1;
	end generate;

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
				if doBitReverse then
					expectData(bitPermIn0'range) := bitReverse(expectData(bitPermIn0'range));
				end if;
				if outValid='1' then
					assert expectData=unsigned(outData)
						report "time " & integer'image(I) & ", expected "
							& integer'image(to_integer(unsigned(expectData))) & ", got "
							& integer'image(to_integer(unsigned(outData)));
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
