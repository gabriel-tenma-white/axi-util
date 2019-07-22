#include <stdio.h>
#include <stdint.h>
#include <math.h>
#include <assert.h>

using namespace std;


// driver library for the OwOComm AXI pipe module

//-- register map (32 bit words)
//-- 0		total number of bytes written to memory
//-- 1		current writing address
//-- 2		total number of bytes read from memory
//-- 3		current reading address
//-- 4		write buffers fifo (write to this address to enqueue;
//--				reads return number of fifo entries free)
//-- 5		read buffers fifo

// these register addresses are word addresses (4-byte words)
#define AXIPIPE_REG_BYTESWRITTEN		0
#define AXIPIPE_REG_CURRWRITEADDR		1
#define AXIPIPE_REG_BYTESREAD			2
#define AXIPIPE_REG_CURRREADADDR		3
#define AXIPIPE_REG_WFIFO				4
#define AXIPIPE_REG_RFIFO				5

// reorder the bursts to transpose a matrix (size set in hardware)
#define AXIPIPE_FLAG_TRANSPOSE			(1<<0)

// reorder the bursts and interleave row/col number
#define AXIPIPE_FLAG_INTERLEAVE			(1<<1)


namespace OwOComm {
	inline int myLog2(int n) {
		int res = (int)ceil(log2(n));
		assert(int(pow(2, res)) == n);
		return res;
	}


	class AXIPipe {
	public:
		volatile uint32_t* regs;
		uint32_t bytesRead = 0, bytesWritten = 0;

		// if not null, these determine the memory region that all buffers
		// supplied are relative to.
		volatile uint8_t* reservedMem = nullptr;
		volatile uint8_t* reservedMemEnd = nullptr;
		uint32_t reservedMemAddr = 0;

		AXIPipe(volatile void* regsAddr);
		AXIPipe(uint32_t regsAddr);
		void initCounters();

		// returns how many read 🅱uffers may be submitted at this time
		int read🅱ufferAcceptance();
		
		// returns how many write 🅱uffers may be submitted at this time
		int write🅱ufferAcceptance();

		uint32_t ptrToAddr(void* ptr);

		// submit a read or write 🅱uffer
		uint32_t submit🅱uffer(bool write, volatile void* buf, int bytes, uint32_t hwFlags);

		// wait for a write 🅱uffer to complete
		void waitWrite(uint32_t marker);

		// wait for a read 🅱uffer to complete
		void waitRead(uint32_t marker);
	};
}
