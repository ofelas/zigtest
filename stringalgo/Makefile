# A simple MAkefile for testing zfpconv

ZIG ?= ~/projects/REPOS/zig/build/bin/zig

BASEPREFIX := test_stringalgo
PROGS := $(BASEPREFIX)_dbg $(BASEPREFIX)_rel

all: $(PROGS)

DEPS = bitap.zig levenshtein.zig quicksearch.zig Makefile $(ZIG)

$(BASEPREFIX)_dbg: $(BASEPREFIX).zig $(DEPS)
	$(ZIG) build_exe --static --name $(@) $(<)

$(BASEPREFIX)_rel: $(BASEPREFIX).zig $(DEPS)
	$(ZIG) build_exe --release-fast --static --name $(@) $(<)

.PHONY:
test: $(PROGS)
	time -p ./$(BASEPREFIX)_dbg > dbg.txt
	time -p ./$(BASEPREFIX)_rel > rel.txt
	diff dbg.txt rel.txt

.PHONY:
clean:
	-rm *.o $(PROGS)
