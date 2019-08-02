--  Hello world program
library ieee;
library work;
use std.textio.all; -- Imports the standard textio package.
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.axiDataGatingSimple;
use work.axiDataGatingSimple2;
use work.axiToOxiToAxiSkid;

--  Defines a design entity, without any ports.
entity test_axiDataGating is
end test_axiDataGating;

architecture behaviour of test_axiDataGating is
	
	subtype data_t is std_logic_vector(15 downto 0);
	subtype dataOut_t is std_logic_vector(15 downto 0);
	
	signal gateAllow: std_logic := '0';

	signal din, din1: data_t;
	signal inClk, dinValid, dinReady, din1Valid, din1Ready: std_logic := '0';
	signal dout, dout0: dataOut_t;
	signal doutValid, doutReady, dout0Valid, dout0Ready: std_logic := '0';
	
	constant inClkHPeriod: time := 0.5 ns;
	
	function inputSpeed(I: integer) return integer is
	begin
		if I<200 then
			return 1;
		elsif I<400 then
			return 5;
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
begin
	inst: entity axiDataGatingSimple
		generic map(addrWidth=>32,
				wordWidth=>16,
				incrBytes=>2)
		port map(aclk=>inClk, reset=>'0',
				allowIssue=>gateAllow,
				in_tvalid=>din1Valid,
				in_tready=>din1Ready,
				in_tdata=>din1,
				in_tlast=>'0',
				out_tvalid=>dout0Valid,
				out_tready=>dout0Ready,
				out_tdata=>dout0);

	--din1 <= din when dinReady='1' and rising_edge(inClk);
	--din1Valid <= dinValid when dinReady='1' and rising_edge(inClk);
	--dinReady <= din1Ready or (not din1Valid);
	skidIn: entity axiToOxiToAxiSkid
		generic map(width=>16)
		port map(aclk=>inClk,
			din_tvalid=>dinValid,
			din_tready=>dinReady,
			din_tdata=>din,
			dout_tvalid=>din1Valid,
			dout_tready=>din1Ready,
			dout_tdata=>din1);

	dout <= dout0 when dout0Ready='1' and rising_edge(inClk);
	doutValid <= dout0Valid when dout0Ready='1' and rising_edge(inClk);
	dout0Ready <= doutReady or (not doutValid);

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
			dinValid <= '0';
			if (I mod inputSpeed(I)) = 0 then
				dinValid <= '1';
				din <= data_t(to_unsigned(inpValue,16));
				if dinReady='1' then
					inpValue := inpValue+1;
				end if;
			end if;
			
			-- retrieve data
			if ((I+2) mod outputSpeed(I)) = 0 then
				doutReady <= '1';
				expectData := to_unsigned(expectValue, 16);
				if doutValid='1' then
					assert expectData=unsigned(dout)
						report "time " & integer'image(I) & ", expected "
							& integer'image(to_integer(unsigned(expectData))) & ", got "
							& integer'image(to_integer(unsigned(dout)));
					expectValue := expectValue+1;
				end if;
			else
				doutReady <= '0';
			end if;
			
			wait for inClkHPeriod; inClk <= '1'; wait for inClkHPeriod; inClk <= '0';
		end loop;
		
		wait;
	end process;

	-- data gating
	process
		variable bufIndex: integer := 0;
		type bufSizes_t is array(0 to 15) of integer;
		variable bufSizes: bufSizes_t := (1,12,34,21,33,20,16,32,80,128,8,2,1,1,1,8);
		variable passedWords: integer;
	begin
		for I in 0 to 31 loop
			wait until rising_edge(inClk);
		end loop;

		for I in 0 to 15 loop
			wait until rising_edge(inClk);

			passedWords := 0;
			gateAllow <= '1';
			for J in 0 to bufSizes(I) - 1 loop
				if doutValid='1' and doutReady='1' then
					passedWords := passedWords+1;
				end if;
				wait until rising_edge(inClk);
			end loop;
			gateAllow <= '0';
			
			for J in 0 to bufSizes(I) - passedWords - 1 loop
				while doutValid='0' or doutReady='0' loop
					wait until rising_edge(inClk);
				end loop;
				wait until rising_edge(inClk);
			end loop;
			
			for J in 0 to 8 loop
				assert doutValid='0';
			end loop;
			
			bufIndex := bufIndex+1;
		end loop;
		wait;
	end process;
end behaviour;
