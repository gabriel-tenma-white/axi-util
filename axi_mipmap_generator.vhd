library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.axiMipmap_types.all;
use work.axiMipmap_minMax;
use work.axiMipmap_buffer;
use work.axiMipmap_arbiter;

entity axiMipmap_generator is
	generic(channels: integer);
	port(
			aclk, reset: in std_logic;
			in_tdata: in minMaxArray(channels-1 downto 0);
			in_tstrobe: in std_logic;
			
			out_tdata: out minMaxArray(channels-1 downto 0);
			out_tstrobe: out std_logic;
			out_tready: in std_logic);
end entity;
architecture a of axiMipmap_generator is
	constant streams: integer := 4;
	constant depthOrder: integer := 4;

	type streamArray is array(streams-1 downto 0) of minMaxArray(channels-1 downto 0);

	signal mipmaps_data: streamArray;
	signal mipmaps_strobe: std_logic_vector(streams-1 downto 0);
	
	signal buffered_tdata: streamArray;
	signal buffered_tvalid, buffered_tready: std_logic_vector(streams-1 downto 0);

	signal arbIn_tdata: minMaxArray(channels*streams-1 downto 0);
begin
	-- reduce
	r0: entity axiMipmap_minMax
		generic map(channels=>channels, decimationOrder=>2)
		port map(aclk=>aclk, reset=>reset,
				in_tdata=>in_tdata, in_tstrobe=>in_tstrobe,
				out_tdata=>mipmaps_data(0), out_tstrobe=>mipmaps_strobe(0));

	r1: entity axiMipmap_minMax
		generic map(channels=>channels, decimationOrder=>2)
		port map(aclk=>aclk, reset=>reset,
				in_tdata=>mipmaps_data(0), in_tstrobe=>mipmaps_strobe(0),
				out_tdata=>mipmaps_data(1), out_tstrobe=>mipmaps_strobe(1));

	r2: entity axiMipmap_minMax
		generic map(channels=>channels, decimationOrder=>2)
		port map(aclk=>aclk, reset=>reset,
				in_tdata=>mipmaps_data(1), in_tstrobe=>mipmaps_strobe(1),
				out_tdata=>mipmaps_data(2), out_tstrobe=>mipmaps_strobe(2));

	r3: entity axiMipmap_minMax
		generic map(channels=>channels, decimationOrder=>2)
		port map(aclk=>aclk, reset=>reset,
				in_tdata=>mipmaps_data(2), in_tstrobe=>mipmaps_strobe(2),
				out_tdata=>mipmaps_data(3), out_tstrobe=>mipmaps_strobe(3));

	-- buffer
g1: for I in 0 to streams-1 generate
		buf: entity axiMipmap_buffer
			generic map(channels=>channels, depthOrder=>depthOrder)
			port map(aclk=>aclk, reset=>reset,
					in_tdata=>mipmaps_data(I), in_tstrobe=>mipmaps_strobe(I),
					out_tdata=>buffered_tdata(I), out_tvalid=>buffered_tvalid(I),
					out_tready=>buffered_tready(I));
	end generate;

	-- arbiter
g2: for I in 0 to streams-1 generate
		arbIn_tdata((I+1)*channels-1 downto I*channels) <= buffered_tdata(I);
	end generate;

	arb: entity axiMipmap_arbiter
		generic map(channels=>channels, streams=>streams)
		port map(aclk=>aclk, reset=>reset,
				in_tdata=>arbIn_tdata, in_tvalid=>buffered_tvalid, in_tready=>buffered_tready,
				out_tdata=>out_tdata, out_tstrobe=>out_tstrobe, out_tready=>out_tready);
end a;
