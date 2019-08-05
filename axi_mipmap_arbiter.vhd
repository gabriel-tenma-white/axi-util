library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
package axiMipmap_arbiter_types is
	function encode(val: std_logic_vector) return integer;
end package;

package body axiMipmap_arbiter_types is
	-- lower indices have higher priority
	function encode(val: std_logic_vector) return integer is
		variable I: integer;
	begin
		for I in 0 to val'length-1 loop
			if val(I) = '1' then
				return I;
			end if;
		end loop;
		return 0;
	end function;
end package body;

library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
USE ieee.math_real.log2;
USE ieee.math_real.ceil;
use work.axiMipmap_types.all;
use work.axiMipmap_arbiter_types.all;

entity axiMipmap_arbiter is
	generic(channels,streams: integer);
	port(
			aclk, reset: in std_logic;
			in_tdata: in minMaxArray(channels*streams-1 downto 0);
			in_tvalid, in_tlast: in std_logic_vector(streams-1 downto 0);
			in_tready: out std_logic_vector(streams-1 downto 0);
			
			out_tdata: out minMaxArray(channels-1 downto 0);
			out_tstrobe, out_tlast: out std_logic;
			out_tready: in std_logic
		);
end entity;
architecture a of axiMipmap_arbiter is
	constant selBits: integer := integer(ceil(log2(real(streams))));
	signal iEncode: unsigned(selBits-1 downto 0);
	signal iEncodeValid, iEncodeValidNext: std_logic;

	type muxDataIn_t is array(streams-1 downto 0) of minMaxArray(channels-1 downto 0);
	signal muxDataIn: muxDataIn_t;
	signal muxData: minMaxArray(channels-1 downto 0);
	signal muxValid, muxStrobe, muxLast: std_logic;
	
	-- state machine
	type state_t is (idle, running);
	signal state, stateNext: state_t := idle;
	signal runningStream, runningStreamNext: unsigned(selBits-1 downto 0);
	
	signal muxSel: unsigned(selBits-1 downto 0);
	signal muxEnable: std_logic;
	signal out_tready1: std_logic;
begin
	-- input tvalid encoder
	iEncode <= to_unsigned(encode(in_tvalid), iEncode'length) when rising_edge(aclk);
	iEncodeValidNext <= '0' when in_tvalid=(in_tvalid'range=>'0') else '1';
	iEncodeValid <= iEncodeValidNext when rising_edge(aclk);

	-- state machine
	stateNext <= running when state=idle and iEncodeValid='1' else
				idle when state=running and muxValid='0' else
				state;
	runningStreamNext <=
				iEncode when state=idle and iEncodeValid='1' else
				runningStream;
	state <= stateNext when rising_edge(aclk);
	runningStream <= runningStreamNext when rising_edge(aclk);

	muxSel <= runningStream;
	muxEnable <= '1' when state=running and out_tready1='1' else '0';

	-- mux
	muxValid <= in_tvalid(to_integer(muxSel));
	muxStrobe <= muxValid and muxEnable;
g1: for I in 0 to streams-1 generate
		muxDataIn(I) <= in_tdata((I+1)*channels-1 downto I*channels);
		--muxData(I) <= in_tdata(to_integer(muxSel)*channels + I);
	end generate;
	muxData <= muxDataIn(to_integer(muxSel));
	muxLast <= '1' when in_tlast(in_tlast'left)='1' and muxSel=in_tlast'left else '0';

	-- decoder
g2: for I in 0 to streams-1 generate
		in_tready(I) <= '1' when muxEnable='1' and muxSel=I else '0';
	end generate;

	-- output
	out_tdata <= muxData when muxStrobe='1' and rising_edge(aclk);
	out_tstrobe <= muxStrobe when rising_edge(aclk);
	out_tlast <= muxLast when muxStrobe='1' and rising_edge(aclk);

	-- flow control
	out_tready1 <= out_tready when rising_edge(aclk);
end a;
