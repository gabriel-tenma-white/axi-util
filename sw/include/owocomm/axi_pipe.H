#pragma once
#include <stdio.h>
#include <stdint.h>
#include <math.h>
#include <assert.h>
#include <functional>
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
#define AXIPIPE_REG_BUFSWRITTEN			1
#define AXIPIPE_REG_BYTESREAD			2
#define AXIPIPE_REG_BUFSREAD			3
#define AXIPIPE_REG_WFIFO				4
#define AXIPIPE_REG_RFIFO				5

// issue an interrupt after the completion of this buffer
#define AXIPIPE_FLAG_INTERRUPT			(1<<7)

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

	// opens a irq fd given a uio device path
	int openIrq(const char* path);

	// wait for an irq on a uio device
	int waitForIrq(int fd, int timeoutMs=-1);

	// clear outstanding irqs if any
	void clearIrq(int fd);


	class AXIPipe {
	public:
		volatile uint32_t* regs;
		int irqfd = -1;
		uint32_t bufsRead = 0, bufsWritten = 0;

		// if not null, these determine the memory region that all buffers
		// supplied are relative to.
		volatile uint8_t* reservedMem = nullptr;
		volatile uint8_t* reservedMemEnd = nullptr;
		uint32_t reservedMemAddr = 0;

		void* cbQueueR = nullptr;
		void* cbQueueW = nullptr;

		// takes ownership of irqfd; irqfd must have O_NONBLOCK set!!!
		AXIPipe(volatile void* regsAddr, int irqfd);
		AXIPipe(uint32_t regsAddr, const char* irqDevice);
		AXIPipe(const AXIPipe& other)=delete;
		~AXIPipe();

		void _initStructures();

		// returns how many read 🅱uffers may be submitted at this time
		int read🅱ufferAcceptance();
		
		// returns how many write 🅱uffers may be submitted at this time
		int write🅱ufferAcceptance();

		uint32_t ptrToAddr(void* ptr);

		// submit a read or write 🅱uffer and return a marker (for waitRead/waitWrite)
		// to use waitRead/waitWrite you must enable the interrupt flag (AXIPIPE_FLAG_INTERRUPT)
		uint32_t submit🅱uffer(bool write, volatile void* buf, int bytes, uint32_t hwFlags);

		// convenience functions
		uint32_t submitWrite(volatile void* buf, int bytes, uint32_t hwFlags) {
			return submit🅱uffer(true, buf, bytes, hwFlags);
		}

		uint32_t submitRead(volatile void* buf, int bytes, uint32_t hwFlags) {
			return submit🅱uffer(false, buf, bytes, hwFlags);
		}

		// submit a read and a write 🅱uffer (useful for block processors);
		// returns the write buffer marker (for waitWrite).
		// AXIPIPE_FLAG_INTERRUPT is not needed in srcFlags or dstFlags because
		// this function adds it to dstFlags.
		uint32_t submitRW(volatile void* srcBuf, volatile void* dstBuf,
								int srcBytes, int dstBytes, uint32_t srcFlags, uint32_t dstFlags);

		// check if a write completed
		bool writeCompleted(uint32_t marker);

		// check if a read completed
		bool readCompleted(uint32_t marker);

		// wait for a write 🅱uffer to complete
		bool waitWrite(uint32_t marker, int timeoutMs=1000);

		// wait for a read 🅱uffer to complete
		bool waitRead(uint32_t marker, int timeoutMs=1000);

		/********************
		 * ASYNC API
		 ********************/

		// when a write marker is reached, call cb
		void waitWriteAsync(uint32_t marker, const function<void()>& cb);

		// when a read marker is reached, call cb
		void waitReadAsync(uint32_t marker, const function<void()>& cb);

		// the user application's event loop should call this function whenever irqfd is readable;
		// this function will consume all pending interrupts and call all completed async callbacks.
		void dispatchInterrupt();
	};
}
