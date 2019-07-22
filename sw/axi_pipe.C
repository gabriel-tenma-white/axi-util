#include <owocomm/axi_pipe.H>

#include <stdio.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <math.h>
#include <assert.h>
#include <errno.h>
#include <string.h>
#include <string>
#include <stdexcept>

namespace OwOComm {

	AXIPipe::AXIPipe(volatile void* regsAddr) {
		regs = (volatile uint32_t*)regsAddr;
		initCounters();
	}
	AXIPipe::AXIPipe(uint32_t regsAddr) {
		int regsMapSize = 4096;
		int memfd;
		if((memfd = open("/dev/mem", O_RDWR | O_SYNC)) < 0) {
			throw runtime_error(string("ERROR: could not open /dev/mem: ") + strerror(errno));
		}
		regs = (volatile uint32_t*) mmap(NULL, regsMapSize, ( PROT_READ | PROT_WRITE ), MAP_SHARED, memfd, regsAddr);
		if(regs == NULL) {
			close(memfd);
			throw runtime_error(string("ERROR: could not map axi pipe registers: ") + strerror(errno));
		}
		close(memfd);
		initCounters();
	}

	void AXIPipe::initCounters() {
		bytesWritten = regs[AXIPIPE_REG_BYTESWRITTEN];
		bytesRead = regs[AXIPIPE_REG_BYTESREAD];
	}

	// returns how many read 🅱uffers may be submitted at this time
	int AXIPipe::read🅱ufferAcceptance() {
		return regs[AXIPIPE_REG_RFIFO];
	}

	// returns how many write 🅱uffers may be submitted at this time
	int AXIPipe::write🅱ufferAcceptance() {
		return regs[AXIPIPE_REG_WFIFO];
	}

	uint32_t AXIPipe::ptrToAddr(void* ptr) {
		if(reservedMem == nullptr)
			throw runtime_error("please set reservedMem before using AXIPipe");

		uint8_t* ptr1 = (uint8_t*)ptr;
		uint8_t* maxBuf = (uint8_t*)reservedMemEnd;
		assert(ptr1 >= reservedMem && ptr <= maxBuf);
		return reservedMemAddr + uint32_t(ptr1-reservedMem);
	}

	// submit a read or write 🅱uffer
	uint32_t AXIPipe::submit🅱uffer(bool write, volatile void* buf, int bytes, uint32_t hwFlags) {
		int reg = write?AXIPIPE_REG_WFIFO:AXIPIPE_REG_RFIFO;
		if(regs[reg] == 0)
			throw runtime_error("hw not accepting" + string(write?"write 🅱uffers":"read 🅱uffers"));

		uint32_t physAddr = ptrToAddr((void*)buf);
		uint32_t sizeOrder = myLog2(bytes/4096);
		uint32_t tmp = physAddr | sizeOrder | (hwFlags << 4);

		(write?bytesWritten:bytesRead) += bytes;
		regs[reg] = tmp;
		return (write?bytesWritten:bytesRead);
	}

	// wait for a 🅱uffer to complete
	void AXIPipe::waitWrite(uint32_t marker) {
		while((regs[AXIPIPE_REG_BYTESWRITTEN] - marker) > (1U<<31)) {
			//usleep(300);
		}
	}

	// wait for a buffer to complete
	void AXIPipe::waitRead(uint32_t marker) {
		while((regs[AXIPIPE_REG_BYTESREAD] - marker) > (1U<<31)) {
			//usleep(300);
		}
	}
}
