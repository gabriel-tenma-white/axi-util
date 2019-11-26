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
#include <poll.h>
#include <queue>

using namespace std;

namespace OwOComm {

	int openIrq(const char* path) {
		int irqfd = open(path, O_RDWR|O_SYNC|O_NONBLOCK);
		if(irqfd<0) {
			string tmp = string("open irq fd: ") + path;
			perror(tmp.c_str());
			return 1;
		}
		int irqcount,irqen=1;
		write(irqfd,&irqen,sizeof(irqen));
		return irqfd;
	}
	int readIrq(int fd) {
		int irqcount;
		int irqen=1;
		if(read(fd,&irqcount,sizeof(irqcount))>0) {
			write(fd,&irqen,sizeof(irqen));
			return irqcount;
		}
		return -1;
	}
	int waitForIrq(int fd, int timeoutMs) {
		//return _readIrq(fd);
		pollfd pfd;
		pfd.fd = fd;
		pfd.events = POLLIN;
		if(poll(&pfd, 1, 0) > 0) {
			fprintf(stderr,"missed interrupt\n");
			return readIrq(fd);
		}
		if(poll(&pfd, 1, timeoutMs) > 0)
			return readIrq(fd);
		return -1;
	}

	// clear outstanding irqs if any
	void clearIrq(int fd) {
		pollfd pfd;
		pfd.fd = fd;
		pfd.events = POLLIN;
		while(poll(&pfd, 1, 0)>0) {
			readIrq(fd);
		}
	}

	// represents one pending callback
	struct CBInfo {
		uint32_t marker;
		function<void()> cb;
	};
	// invert the comparison so that callbacks with lower marker
	// are higher priority.
	bool operator<(const CBInfo& a, const CBInfo& b) {
		return a.marker > b.marker;
	}
	typedef priority_queue<CBInfo> priority_queue_t;

	AXIPipe::AXIPipe(volatile void* regsAddr, int irqfd) {
		regs = (volatile uint32_t*)regsAddr;
		this->irqfd = irqfd;
		_initStructures();
	}
	AXIPipe::AXIPipe(uint32_t regsAddr, const char* irqDevice) {
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
		
		irqfd = openIrq(irqDevice);
		if(irqfd < 0) {
			throw runtime_error("ERROR: could not open irq device");
		}
		_initStructures();
	}
	AXIPipe::~AXIPipe() {
		priority_queue_t* qR = (priority_queue_t*) this->cbQueueR;
		priority_queue_t* qW = (priority_queue_t*) this->cbQueueW;
		if(qR != nullptr)
			delete qR;
		if(qW != nullptr)
			delete qW;
	}

	void AXIPipe::_initStructures() {
		bufsWritten = regs[AXIPIPE_REG_BUFSWRITTEN];
		bufsRead = regs[AXIPIPE_REG_BUFSREAD];
		cbQueueR = new priority_queue_t();
		cbQueueW = new priority_queue_t();
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
		//fprintf(stderr, "%s acceptance: %d\n", write?"write":"read", regs[reg]);

		uint32_t physAddr = ptrToAddr((void*)buf);
		uint32_t sizeOrder = myLog2(bytes/4096);
		uint32_t tmp = physAddr | sizeOrder | (hwFlags << 4);

		(write?bufsWritten:bufsRead) ++;
		regs[reg] = tmp;
		return (write?bufsWritten:bufsRead);
	}

	uint32_t AXIPipe::submitRW(volatile void* srcBuf, volatile void* dstBuf,
								int srcBytes, int dstBytes, uint32_t srcFlags, uint32_t dstFlags) {
		if(write🅱ufferAcceptance() < 1) throw runtime_error("hw not accepting write 🅱uffers");
		if(read🅱ufferAcceptance() < 1) throw runtime_error("hw not accepting read 🅱uffers");

		uint32_t ret = submit🅱uffer(true, dstBuf, dstBytes, dstFlags | AXIPIPE_FLAG_INTERRUPT);
		submit🅱uffer(false, srcBuf, srcBytes, srcFlags);
		return ret;
	}

	bool AXIPipe::writeCompleted(uint32_t marker) {
		uint16_t bufsCompleted = (uint16_t)regs[AXIPIPE_REG_BUFSWRITTEN];
		int16_t diff = int16_t(bufsCompleted - (uint16_t)marker);
		return (diff >= 0);
	}

	bool AXIPipe::readCompleted(uint32_t marker) {
		uint16_t bufsCompleted = (uint16_t)regs[AXIPIPE_REG_BUFSREAD];
		int16_t diff = int16_t(bufsCompleted - (uint16_t)marker);
		return (diff >= 0);
	}

	// wait for a 🅱uffer to complete
	bool AXIPipe::waitWrite(uint32_t marker, int timeoutMs) {
		while(!writeCompleted(marker)) {
			if(waitForIrq(irqfd, timeoutMs) <= 0) {
				fprintf(stderr, "timeout waiting for irq; current write marker %u, write acceptance %d\n", regs[AXIPIPE_REG_BUFSWRITTEN], write🅱ufferAcceptance());
				return false;
			}
		}
		return true;
	}

	// wait for a buffer to complete
	bool AXIPipe::waitRead(uint32_t marker, int timeoutMs) {
		while(!readCompleted(marker)) {
			if(waitForIrq(irqfd, timeoutMs) <= 0) {
				fprintf(stderr, "timeout waiting for irq; current read marker %u, read bytes %u, read acceptance %d\n",
					regs[AXIPIPE_REG_BUFSREAD], regs[AXIPIPE_REG_BYTESREAD], read🅱ufferAcceptance());
				return false;
			}
		}
		return true;
	}


	// when a write marker is reached, call cb
	void AXIPipe::waitWriteAsync(uint32_t marker, const function<void()>& cb) {
		priority_queue_t* qW = (priority_queue_t*) this->cbQueueW;
		/*if(writeCompleted(marker)) {
			cb();
			return;
		}*/
		qW->push(CBInfo {marker, cb});
	}
	
	// when a read marker is reached, call cb
	void AXIPipe::waitReadAsync(uint32_t marker, const function<void()>& cb) {
		priority_queue_t* qR = (priority_queue_t*) this->cbQueueR;
		if(readCompleted(marker)) {
			cb();
			return;
		}
		qR->push(CBInfo {marker, cb});
	}

	// the user application's event loop should call this function whenever irqfd is readable;
	// this function will consume the interrupt and call all completed async callbacks.
	void AXIPipe::dispatchInterrupt() {
		priority_queue_t* qR = (priority_queue_t*) this->cbQueueR;
		priority_queue_t* qW = (priority_queue_t*) this->cbQueueW;

		readIrq(irqfd);
		while(true) {
			bool didSomething = false;
			if((!qR->empty()) && readCompleted(qR->top().marker)) {
				qR->top().cb();
				qR->pop();
				didSomething = true;
			}
			if((!qW->empty()) && writeCompleted(qW->top().marker)) {
				qW->top().cb();
				qW->pop();
				didSomething = true;
			}
			if(!didSomething) break;
		}
	}
}
