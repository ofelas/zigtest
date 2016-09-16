#!/bin/sh
ZIG=~/projects/REPOS/zig/build/bin/zig
SRC=securehash/autotest.zig
${ZIG} build  --verbose --static --export exe --name securehash/autotest_debug ${SRC}  2>securehash/stderr_dbg.txt
[ "x${?}" != "x0" ] && exit
./securehash/autotest_debug | tee securehash/dbg.txt
${ZIG} build --verbose --release --static --export exe --name securehash/autotest_release ${SRC} 2>securehash/stderr_rel.txt
[ "x${?}" != "x0" ] && exit
./securehash/autotest_release | tee securehash/rel.txt
