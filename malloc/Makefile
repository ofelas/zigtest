# A simple Makefile for testing allocators

ZIG ?= ~/projects/REPOS/zig/build/bin/zig
CC := gcc-6
COPT ?= -O3 -ggdb -funroll-loops

PROGPREFIX := malltest

PROGS := $(PROGPREFIX)

all: $(PROGS)

$(PROGPREFIX): $(PROGPREFIX).o jemalloc_linux.o  #Makefile
	$(CC) -nostartfiles  $(^) -o $(@)
	ldd $(@)

# make can strip the suffix
$(PROGPREFIX).o: $(PROGPREFIX).zig liballoc.zig printer.zig Makefile
	$(ZIG) build --static --export obj --name $(PROGPREFIX) $(<)

jemalloc_linux.o: jemalloc_linux.c rb.h Makefile
	$(CC) $(COPT) -c $(<) -o $(@)

.PHONY:
test: malltest Makefile
	./malltest
	./malltest joker
	./malltest jemalloc
	./malltest liballoc
	./malltest does_not_exist

.PHONY:
rbtest:
	time -p $(ZIG) test --check-unused rbtest.zig
	time -p $(ZIG) test --release --check-unused rbtest.zig

.PHONY:
clean:
	-rm *.o $(PROGS)
