# A simple Makefile for testing allocators

ZIG ?= ~/projects/REPOS/zig/build/bin/zig
CC ?= gcc
COPT ?= -O2 -ggdb

PROGPREFIX := malltest

PROGS := $(PROGPREFIX)

all: $(PROGS)

$(PROGPREFIX): $(PROGPREFIX).o jemalloc_linux.o  #Makefile
	$(CC) -nostartfiles  $(^) -o $(@)
	ldd $(@)

# make can strip the suffix
$(PROGPREFIX).o: $(PROGPREFIX).zig printer.zig Makefile
	$(ZIG) build --static --export obj --name $(PROGPREFIX) $(<)

jemalloc_linux.o: jemalloc_linux.c rb.h Makefile
	$(CC) $(COPT) -static -c $(<) -o $(@)

.PHONY:
test: malltest Makefile
	./malltest
	./malltest joker
	./malltest jemalloc
	./malltest does_not_exist

.PHONY:
clean:
	-rm *.o $(PROGS)
