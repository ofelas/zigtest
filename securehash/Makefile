# Makefile for securehash test
ZIG ?= ~/projects/REPOS/zig/build/bin/zig
SRC = autotest.zig
VERBOSE ?=
#--verbose

all: autotest_debug autotest_release

autotest_debug: $(SRC) securehash.zig Makefile
	${ZIG} build ${VERBOSE} --static --export exe --name $(@) ${<}

autotest_release: $(SRC) securehash.zig Makefile
	${ZIG} build ${VERBOSE} --release --static --export exe --name $(@) ${<}

TESTINPUT = dbg.txt rel.txt securehash.zig autotest.zig autotest_debug.o autotest_release.o $(ZIG)
test: autotest_debug autotest_release
	./autotest_debug | tee dbg.txt
	./autotest_release | tee rel.txt
	diff dbg.txt rel.txt
	sha1sum $(TESTINPUT)
	./autotest_debug $(TESTINPUT)
	./autotest_release $(TESTINPUT)

# ./securehash/autotest_release | tee securehash/rel.txt
# for f in securehash/stderr_dbg.txt securehash/stderr_rel.txt checksecurehash.sh; do
#     for p in sha1sum securehash/autotest_debug securehash/autotest_release; do
# 	echo "sha1 summing file '${f}' with ${p}"
# 	for s in $(seq 1 3); do
# 	    ${p} ${f}
# 	done
#     done
# done

# for s in $(seq 64); do
#     $(which printf) "%*s" ${s} "a" > TESTINPPUT.txt
#     echo "sha1 summing file 'TESTINPUT.txt' ${s}"
#     for p in sha1sum securehash/autotest_debug securehash/autotest_release; do
# 	${p} TESTINPPUT.txt
#     done
# done
