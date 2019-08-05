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
	constant period: integer := 4*4*4*4*16;

	signal bytesIssued: unsigned(31 downto 0);
	
	subtype data_t is minMaxArray(0 downto 0);
	
	signal inData: data_t;
	signal clk, inpValid, inLast: std_logic := '0';
	signal outData: data_t;
	signal outStrobe, outReady, outLast: std_logic := '0';

	function getTlast(frameI: integer) return boolean is
	begin
		return (frameI mod 3) = 2;
	end function;
begin
	inst: entity axiMipmap_generator
		generic map(channels=>1)
		port map(aclk=>clk, reset=>'0',
			in_tdata=>inData, in_tstrobe=>inpValid, in_tlast=>inLast,
			out_tdata=>outData, out_tstrobe=>outStrobe, out_tready=>outReady, out_tlast=>outLast);

	process
		variable l : line;
		variable inpValue, expectValue: integer := 0;
		variable expectData: signed(31 downto 0) := (others=>'0');
	begin
		wait for 0.5 ns; clk <= '1'; wait for 0.5 ns; clk <= '0';
		wait for 0.5 ns; clk <= '1'; wait for 0.5 ns; clk <= '0';
		for I in 0 to 1024*32 loop
		
			-- input data
			inpValid <= '0';
			inLast <= '0';
			if (I mod 5) /= 4 then
				inpValid <= '1';
				inData(0).lower <= to_signed(inpValue,32);
				inData(0).upper <= to_signed(inpValue,32);
				if ((inpValue+1) mod period) = 0 and getTlast(inpValue/period) then
					inLast <= '1';
				end if;
				inpValue := inpValue+1;
			else
				inpValid <= '0';
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
	process
		procedure verifyChunk (
			constant lower,step,count: integer;
			constant isLast: boolean;
			signal clk,strobe,last: in std_logic;
			signal data: in data_t
		) is
			variable expectLower,expectUpper: integer;
			variable expectLast: std_logic;
		begin
			for I in 0 to count-1 loop
				while strobe /= '1' loop
					wait until rising_edge(clk);
				end loop;
				
				expectLower := lower + I*step;
				expectUpper := lower + (I+1)*step - 1;
				expectLast := '0';
				if I = (count-1) and isLast then
					expectLast := '1';
				end if;
				
				assert to_integer(data(0).lower) = expectLower
					report "expected .lower " & integer'image(expectLower)
							& " got " & integer'image(to_integer(data(0).lower));
				assert to_integer(data(0).upper) = expectUpper
					report "expected .upper " & integer'image(expectUpper)
							& " got " & integer'image(to_integer(data(0).upper));
				assert last = expectLast report "incorrect tlast";
				wait until rising_edge(clk);
			end loop;
		end verifyChunk;
		variable lower, upper, lower1, lower2, lower3: integer;
		constant chunkSize: integer := 16;
		variable frameI: integer := 0;
	begin
		lower := 0;
		while true loop
			lower3 := lower;
			for I in 0 to 3 loop
				lower2 := lower;
				for J in 0 to 3 loop
					lower1 := lower;
					for K in 0 to 3 loop
						upper := lower + 4*chunkSize;
						verifyChunk(lower=>lower, step=>4, count=>chunkSize, isLast=>false,
									clk=>clk, strobe=>outStrobe, data=>outData, last=>outLast);
						lower := upper;
					end loop;
	
					verifyChunk(lower=>lower1, step=>4*4, count=>chunkSize, isLast=>false,
							clk=>clk, strobe=>outStrobe, data=>outData, last=>outLast);
				end loop;
	
				verifyChunk(lower=>lower2, step=>4*4*4, count=>chunkSize, isLast=>false,
							clk=>clk, strobe=>outStrobe, data=>outData, last=>outLast);
				write(output, "verified chunk" & LF);
			end loop;
			
			verifyChunk(lower=>lower3, step=>4*4*4*4, count=>chunkSize, isLast=>getTlast(frameI),
							clk=>clk, strobe=>outStrobe, data=>outData, last=>outLast);
			write(output, "verified outer chunk" & LF);

			frameI := frameI + 1;
		end loop;
		wait;
	end process;
end behaviour;
