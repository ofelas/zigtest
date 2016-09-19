# A simple MAkefile for testing zfpconv

ZIG ?= ~/projects/REPOS/zig/build/bin/zig
CC ?= gcc
COPT ?= -O3 -ggdb -Wall

PROGPREFIX := testfpconv

PROGS := $(PROGPREFIX)_dbg $(PROGPREFIX)_rel

all: $(PROGS)

$(PROGPREFIX)_dbg: $(PROGPREFIX)_dbg.o fpconv.o fast_atof.o
	$(CC) -nostartfiles  $(^) -o $(@)

$(PROGPREFIX)_rel: $(PROGPREFIX)_rel.o fpconv.o fast_atof.o
	$(CC) -nostartfiles  $(^) -o $(@)

$(PROGPREFIX)_dbg.o: $(PROGPREFIX).zig zfpconv.zig zfast_atof.zig Makefile
	$(ZIG) build --static --export obj --name $(@) $(<)

$(PROGPREFIX)_rel.o: $(PROGPREFIX).zig zfpconv.zig zfast_atof.zig Makefile
	$(ZIG) build --release --static --export obj --name $(@) $(<)

fpconv.o: fpconv.c fpconv.h powers.h Makefile
	$(CC) $(COPT) -c $(<) -o $(@)

fast_atof.o: fast_atof.c Makefile
	$(CC) $(COPT) -c $(<) -o $(@)

.PHONY:
test: $(PROGPREFIX)_dbg $(PROGPREFIX)_rel
	time -p ./$(PROGPREFIX)_dbg > dbg1.txt
	time -p ./$(PROGPREFIX)_dbg x > dbg2.txt
	time -p ./$(PROGPREFIX)_rel > rel1.txt
	time -p ./$(PROGPREFIX)_rel x > rel2.txt
	diff dbg1.txt rel1.txt
	diff dbg2.txt rel2.txt

GENERATED := dbg1.txt dbg2.txt rel1.txt rel2.txt

.PHONY:
clean: Makefile
	-rm *.o $(PROGS) $(GENERATED)
