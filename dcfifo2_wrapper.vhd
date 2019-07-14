library ieee;
library work;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
USE ieee.math_real.log2;
USE ieee.math_real.ceil;
use work.dcfifo2;
entity dcfifo2Wrapper is
	generic(widthIn, widthOut: integer := 8;
				-- real depth is 2^depthOrderIn words of widthIn
				depthOrderIn: integer := 9;
				depthOrderOut: integer := 9);
	port(rd_aclk,wr_aclk: in std_logic;
			
			-- read side; synchronous to rdclk
			rd_tvalid: out std_logic;
			rd_tready: in std_logic;
			rd_tdata: out std_logic_vector(widthOut-1 downto 0);
			
			--write side; synchronous to wrclk
			wr_tvalid: in std_logic;
			wr_tready: out std_logic;
			wr_tdata: in std_logic_vector(widthIn-1 downto 0);
			
			-- how many input words are left to be read
			rdleft: out unsigned(depthOrderOut-1 downto 0);
			
			-- how much space is available in the queue, in output words
			wrroom: out unsigned(depthOrderIn-1 downto 0)
			);
end entity;

architecture a of dcfifo2Wrapper is
begin
	assert depthOrderOut=(depthOrderIn+integer(ceil(log2(real(widthIn)/real(widthOut)))));
	fifo: entity dcfifo2
		generic map(widthIn=>widthIn, widthOut=>widthOut, depthOrderIn=>depthOrderIn)
		port map(rdclk=>rd_aclk, wrclk=>wr_aclk,
			rdvalid=>rd_tvalid, rdready=>rd_tready, rddata=>rd_tdata,
			wrvalid=>wr_tvalid, wrready=>wr_tready, wrdata=>wr_tdata,
			rdleft=>rdleft, wrroom=>wrroom);
end a;

