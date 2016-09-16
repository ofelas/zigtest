#!/bin/bash
ZIG=~/projects/REPOS/zig/build/bin/zig
SRC=securehash/autotest.zig
VERBOSE=--verbose
${ZIG} build  ${VERBOSE} --static --export exe --name securehash/autotest_debug ${SRC}  2>securehash/stderr_dbg.txt
[ "x${?}" != "x0" ] && exit
./securehash/autotest_debug | tee securehash/dbg.txt
${ZIG} build ${VERBOSE} --release --static --export exe --name securehash/autotest_release ${SRC} 2>securehash/stderr_rel.txt
[ "x${?}" != "x0" ] && exit
./securehash/autotest_release | tee securehash/rel.txt
for f in securehash/stderr_dbg.txt securehash/stderr_rel.txt checksecurehash.sh; do
    for p in sha1sum securehash/autotest_debug securehash/autotest_release; do
	echo "sha1 summing file '${f}' with ${p}"
	for s in $(seq 1 5); do
	    ${p} ${f}
	done
    done
done

for s in $(seq 64); do
    $(which printf) "%*s" ${s} "a" > TESTINPPUT.txt
    echo "sha1 summing file 'TESTINPUT.txt' ${s}"
    for p in sha1sum securehash/autotest_debug securehash/autotest_release; do
	${p} TESTINPPUT.txt
    done
done
