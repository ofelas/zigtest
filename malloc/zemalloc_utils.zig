const std = @import("std");
const math = std.math;
const io = std.io;
const debug = std.debug;
const assert = debug.assert;
const prt = @import("printer.zig");
const printNamedHex = prt.printNamedHex;

const CHUNK_2POW_DEFAULT = usize(20);

pub const chunksize = (1 << CHUNK_2POW_DEFAULT);
pub var chunksize_mask = chunksize - 1;

/// Return the chunk address for allocation address a.
pub inline fn CHUNK_ADDR2BASE(a: &u8) -> &u8 {
    return ((&u8)(usize(a) & ~chunksize_mask));
}

/// Return the chunk offset of address a.
pub inline fn CHUNK_ADDR2OFFSET(a: &u8) -> usize {
    return usize(a) & chunksize_mask;
}

/// Return the smallest chunk multiple that is >= s.
pub inline fn CHUNK_CEILING(s: usize) -> usize {
    return (((s) + chunksize_mask) & ~chunksize_mask);
}

pub const PAGESIZE_2POW   = usize(12);
pub const QUANTUM_2POW    =  usize(4);
pub const SIZEOF_PTR_2POW =  usize(3);

pub const QUANTUM = (1 << QUANTUM_2POW);
pub const QUANTUM_MASK = (QUANTUM - 1);

/// Return the smallest quantum multiple that is >= a.
pub inline fn QUANTUM_CEILING(a: usize) -> usize {
    return (((a) + QUANTUM_MASK) & ~QUANTUM_MASK);
}

const pagesize = usize(4096);
var pagesize_mask = usize(pagesize - 1);
var pagesize_2pow = usize(12);

/// Return the smallest pagesize multiple that is >= s.
pub inline fn PAGE_CEILING(s: usize) -> usize {
    return (((s) + pagesize_mask) & ~pagesize_mask);
}


// Maximum size of L1 cache line.  This is used to avoid cache line
// aliasing.  In addition, this controls the spacing of
// cacheline-spaced size classes.
pub const CACHELINE_2POW = usize(6);
pub const CACHELINE = (1 << CACHELINE_2POW);
pub const CACHELINE_MASK = (CACHELINE - 1);

/// Return the smallest cacheline multiple that is >= s.
pub inline fn CACHELINE_CEILING(s: usize) -> usize {
    return (((s) + CACHELINE_MASK) & ~CACHELINE_MASK);
}

const SUBPAGE_2POW = usize(8);
const SUBPAGE = (1 << SUBPAGE_2POW);
const SUBPAGE_MASK = (SUBPAGE - 1);

/// Return the smallest subpage multiple that is >= s.
pub inline fn SUBPAGE_CEILING(s: usize) -> usize {
    return (((s) + SUBPAGE_MASK) & ~SUBPAGE_MASK);
}


/// Round up val to the next power of two
pub inline fn next_power_of_two(val: usize) -> usize {
    var lval = val;

    assert(lval > 1);
    assert(lval <= @maxValue(usize));

    lval -= 1;
    lval |= lval >> 1;
    lval |= lval >> 2;
    lval |= lval >> 4;
    lval |= lval >> 8;
    lval |= lval >> 16;
    if (@sizeOf(usize) == 8) {
        lval |= lval >> 32;
    }
    lval += 1;
    return lval;
}

// hmm, seems to be the same as next_power_of_two (above)
/// Compute the smallest power of 2 that is >= x.
pub inline fn pow2_ceil(value: usize) -> usize {
    var x = value;
    x -= 1;
    x |= x >> 1;
    x |= x >> 2;
    x |= x >> 4;
    x |= x >> 8;
    x |= x >> 16;
    if (@sizeOf(usize) == 8) {
        x |= x >> 32;
    }
    x += 1;
    return x;
}

fn dump_proc_maps() -> %void {
    var buf: [16 * 1024]u8 = zeroes; // undefined?
    var is: io.InStream = undefined;
    is.open("/proc/self/maps") %% |err| {
        %%io.stderr.printf("Unable to open file: ");
        %%io.stderr.printf(@errorName(err));
        %%io.stderr.printf("\n");
        return err;
    };
    defer is.close() %% |err| {
        %%io.stderr.write("Unable to close file: ");
        %%io.stderr.write(@errorName(err));
        %%io.stderr.printf("\n");
        return err;
    };
    const sz = is.read(buf) %% |err| {
        %%io.stderr.write("Unable to read file: ");
        %%io.stderr.write(@errorName(err));
        %%io.stderr.printf("\n");
        return err;
    };
    %%io.stdout.printf(buf[0...sz]);
}

pub fn getProcFile(filename: []u8, buf: []u8) -> usize {
        var is: io.InStream = undefined;
        is.open(filename) %% |err| {
            %%io.stderr.printf("Unable to open file: ");
            %%io.stderr.printf(@errorName(err));
            %%io.stderr.printf("\n");
            return 0;
        };
        defer is.close() %% |err| {
            %%io.stderr.write("Unable to close file: ");
            %%io.stderr.write(@errorName(err));
            %%io.stderr.printf("\n");
            return 0;
        };
        const sz = is.read(buf) %% |err| {
            %%io.stderr.write("Unable to read file: ");
            %%io.stderr.write(@errorName(err));
            %%io.stderr.printf("\n");
            return 0;
        };

        return sz;
}

const qs = @import("../stringalgo/quicksearch.zig");

pub fn getPageSize(have_threads: bool) -> %usize {
    var result = usize(4096);
    var mapped = usize(0);
    var nrpages = usize(0);
    if (have_threads) {
        result = 4096; // sysconf(_SC_PAGESIZE);
        var buf: [16 * 1024]u8 = zeroes;
        var sz = getProcFile("/proc/meminfo", buf);
        var searcher: qs.QuickSearch = undefined;
        %%searcher.init("\nMapped:");
        var where = searcher.search("\nMapped:", buf);
        if (where > 0) {
            var idx = usize(where) + 8;
            //%%printNamedHex("mapped=", where, io.stdout);
            while (true) {
                if (buf[idx] == ' ' || buf[idx] == '\t') {
                    idx += 1;
                    continue;
                }
                break;
            }
            //%%io.stdout.printf(buf[idx...idx + 10]);
            while (true) {
                switch (buf[idx]) {
                    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                        mapped = %return math.mulOverflow(usize, mapped, 10);
                        mapped = %return math.addOverflow(usize, mapped, usize(buf[idx] - '0'));
                        idx += 1;
                    },
                    else => { break;},
                }
            }
        }
        sz = getProcFile("/proc/vmstat", buf);
        %%searcher.init("\nnr_mapped");
        where = searcher.search("\nnr_mapped", buf);
        if (where > 0) {
            var idx = usize(where) + 10;
            //%%printNamedHex("nr_mapped at ", where, io.stdout);
            while (true) {
                if (buf[idx] == ' ' || buf[idx] == '\t') {
                    idx += 1;
                    continue;
                }
                break;
            }
            //%%io.stdout.printf(buf[idx...idx + 10]);
            while (true) {
                switch (buf[idx]) {
                    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                        nrpages = %return math.mulOverflow(usize, nrpages, 10);
                        nrpages = %return math.addOverflow(usize, nrpages, usize(buf[idx] - '0'));
                        idx += 1;
                    },
                    else => { break;},
                }
            }
        }
        //%%printNamedHex("mapped=", mapped, io.stdout);
        //%%printNamedHex("nrpages=", nrpages, io.stdout);
        if (mapped > nrpages) {
            result = (mapped / nrpages) * 1024;
        }
    }

    //%%printNamedHex("result=", result, io.stdout);
    return result;
}

// TODO: %usize
pub fn getNumCpus(have_threads: bool) -> usize {
    var ncpus = usize(1);
    if (have_threads) {
        var buf: [16 * 1024]u8 = zeroes;
        const sz = getProcFile("/proc/cpuinfo", buf);
        var ix = usize(0);
        var qsearch: qs.QuickSearch = undefined;
        const needle = "processor\t:";
        %%qsearch.init(needle);
        // sysconf(3) would be the preferred method for determining the number
        // of CPUs, but it uses malloc internally, which causes untennable
        // recursion during malloc initialization.
        while (ix < buf.len) {
            const ofs = qsearch.search(needle, buf);
            if (ofs < 0) break; // nothing more found
            ix += usize(ofs) + usize(qsearch.patternlen);
            ncpus += 1;
        }
        if (ncpus > 1) {
            ncpus -= 1;         // we already had 1 cpu
        }
    }

    return ncpus;
}

fn convertValue(n: usize) -> usize {
    %%io.stdout.printInt(usize, n);
    %%io.stdout.printf(" -> ");
    const ans = next_power_of_two(n);
    %%io.stdout.printInt(usize, ans);
    %%io.stdout.printf("\n");

    return ans;
}

fn testGetPageSize() {
    @setFnTest(this, true);
    var pgsize = %%getPageSize(false);
    assert(pgsize == 4096);
    pgsize = %%getPageSize(true);
}

fn testGetNumCpus() {
    @setFnTest(this, true);
    var ncpus = getNumCpus(false);
    %%printNamedHex("ncpus=", ncpus, io.stdout);
    assert(ncpus == 1);
    ncpus = getNumCpus(true);
    %%printNamedHex("ncpus=", ncpus, io.stdout);
    assert(ncpus > 1);
}

fn testCHUNKCALC() {
    @setFnTest(this, true);

    var a: &u8 = (&u8)(usize(333) + chunksize);
    var b = CHUNK_ADDR2BASE(a);
    var c = CHUNK_ADDR2OFFSET(a);
    var d = CHUNK_CEILING(usize(a));
    var qc = QUANTUM_CEILING(c);
    var cc = CACHELINE_CEILING(c);
    var spc = SUBPAGE_CEILING(c);
    var pc = PAGE_CEILING(c);

    %%printNamedHex("chunksize=", chunksize, io.stdout);
    %%printNamedHex("chunksize_mask=", chunksize_mask, io.stdout);
    %%printNamedHex("QUANTUM=", QUANTUM, io.stdout);
    %%printNamedHex("QUANTUM_MASK=", QUANTUM_MASK, io.stdout);
    %%printNamedHex("a=", usize(a), io.stdout);
    %%printNamedHex("b=", usize(b), io.stdout);
    %%printNamedHex("c=", usize(c), io.stdout);
    %%printNamedHex("d=", usize(d), io.stdout);
    %%printNamedHex("qc=", usize(qc), io.stdout);
    %%printNamedHex("cc=", usize(cc), io.stdout);
    %%printNamedHex("spc=", usize(spc), io.stdout);
    %%printNamedHex("pc=", usize(pc), io.stdout);

    //assert(usize(a) == c);
}

fn testNPOW2() {
    @setFnTest(this, true);
    // @setFnStaticEval(this, false);

    var ans = convertValue(usize(@maxValue(isize) - @maxValue(i8)));
    ans = convertValue(usize(@maxValue(isize) - @maxValue(i16)));
    ans = convertValue(usize(@maxValue(isize) - @maxValue(i32)));
    ans = convertValue(usize(514));
    ans = convertValue(usize(2 * 514));
    assert(next_power_of_two(2) == 2);
    assert(next_power_of_two(3) == 4);
    assert(next_power_of_two(4) == 4);
    assert(next_power_of_two(5) == 8);
    assert(next_power_of_two(6) == 8);
    assert(next_power_of_two(7) == 8);
    assert(next_power_of_two(8) == 8);
    assert(next_power_of_two(9) == 16);
    assert(next_power_of_two(15) == 16);
    assert(next_power_of_two(233) == 256);

    assert(next_power_of_two(511) == next_power_of_two(512));
    assert(next_power_of_two(513) == next_power_of_two(514));
}
