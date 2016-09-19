# A simple MAkefile for testing zfpconv

ZIG ?= ~/projects/REPOS/zig/build/bin/zig

BASEPREFIX := test_stringalgo
PROGS := $(BASEPREFIX)_dbg $(BASEPREFIX)_rel

all: $(PROGS)

DEPS = bitap.zig levenshtein.zig quicksearch.zig Makefile

$(BASEPREFIX)_dbg: $(BASEPREFIX).zig $(DEPS)
	$(ZIG) build --static --export exe --name $(@) $(<)

$(BASEPREFIX)_rel: $(BASEPREFIX).zig $(DEPS)
	$(ZIG) build --release --static --export exe --name $(@) $(<)

.PHONY:
test: $(PROGS)
	time -p ./$(BASEPREFIX)_dbg > dbg.txt
	time -p ./$(BASEPREFIX)_rel > rel.txt
	diff dbg.txt rel.txt

.PHONY:
clean:
	-rm *.o $(PROGS)
