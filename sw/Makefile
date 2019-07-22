
CXX := clang++-7
CFLAGS ?= -O2

REQUIRED_CXXFLAGS := --std=c++0x -finput-charset=UTF-8 -fextended-identifiers -I./include

CXXFLAGS2 := $(REQUIRED_CXXFLAGS) $(INCLUDES) $(CFLAGS)

%.o: %.C
	$(CXX) -c $(CXXFLAGS2) $< -o $@


axi_pipe.a: axi_pipe.o
	ar rcs $@ $^

clean:
	rm -f *.a *.o
