// /* From https://github.com/openwebos/jemalloc */
// /*-
//  * Copyright (C) 2008 Jason Evans <jasone@FreeBSD.org>.
//  * Copyright (c) 2008-2013 LG Electronics, Inc.
//  * All rights reserved.
//  *
//  * Redistribution and use in source and binary forms, with or without
//  * modification, are permitted provided that the following conditions
//  * are met:
//  * 1. Redistributions of source code must retain the above copyright
//  *    notice(s), this list of conditions and the following disclaimer as
//  *    the first lines of this file unmodified other than the possible
//  *    addition of one or more copyright notices.
//  * 2. Redistributions in binary form must reproduce the above copyright
//  *    notice(s), this list of conditions and the following disclaimer in
//  *    the documentation and/or other materials provided with the
//  *    distribution.
//  *
//  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) ``AS IS'' AND ANY
//  * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
//  * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT HOLDER(S) BE
//  * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
//  * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
//  * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
//  * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
//  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//  *
//  *******************************************************************************
//  *
//  * This allocator implementation is designed to provide scalable performance
//  * for multi-threaded programs on multi-processor systems.  The following
//  * features are included for this purpose:
//  *
//  *   + Multiple arenas are used if there are multiple CPUs, which reduces lock
//  *     contention and cache sloshing.
//  *
//  *   + Thread-specific caching is used if there are multiple threads, which
//  *     reduces the amount of locking.
//  *
//  *   + Cache line sharing between arenas is avoided for internal data
//  *     structures.
//  *
//  *   + Memory is managed in chunks and runs (chunks can be split into runs),
//  *     rather than as individual pages.  This provides a constant-time
//  *     mechanism for associating allocations with particular arenas.
//  *
//  * Allocation requests are rounded up to the nearest size class, and no record
//  * of the original request size is maintained.  Allocations are broken into
//  * categories according to size class.  Assuming runtime defaults, 4 kB pages
//  * and a 16 byte quantum on a 32-bit system, the size classes in each category
//  * are as follows:
//  *
//  *   |=======================================|
//  *   | Category | Subcategory      |    Size |
//  *   |=======================================|
//  *   | Small    | Tiny             |       2 |
//  *   |          |                  |       4 |
//  *   |          |                  |       8 |
//  *   |          |------------------+---------|
//  *   |          | Quantum-spaced   |      16 |
//  *   |          |                  |      32 |
//  *   |          |                  |      48 |
//  *   |          |                  |     ... |
//  *   |          |                  |      96 |
//  *   |          |                  |     112 |
//  *   |          |                  |     128 |
//  *   |          |------------------+---------|
//  *   |          | Cacheline-spaced |     192 |
//  *   |          |                  |     256 |
//  *   |          |                  |     320 |
//  *   |          |                  |     384 |
//  *   |          |                  |     448 |
//  *   |          |                  |     512 |
//  *   |          |------------------+---------|
//  *   |          | Sub-page         |     760 |
//  *   |          |                  |    1024 |
//  *   |          |                  |    1280 |
//  *   |          |                  |     ... |
//  *   |          |                  |    3328 |
//  *   |          |                  |    3584 |
//  *   |          |                  |    3840 |
//  *   |=======================================|
//  *   | Large                       |    4 kB |
//  *   |                             |    8 kB |
//  *   |                             |   12 kB |
//  *   |                             |     ... |
//  *   |                             | 1012 kB |
//  *   |                             | 1016 kB |
//  *   |                             | 1020 kB |
//  *   |=======================================|
//  *   | Huge                        |    1 MB |
//  *   |                             |    2 MB |
//  *   |                             |    3 MB |
//  *   |                             |     ... |
//  *   |=======================================|
//  *
//  * A different mechanism is used for each category:
//  *
//  *   Small : Each size class is segregated into its own set of runs.  Each run
//  *           maintains a bitmap of which regions are free/allocated.
//  *
//  *   Large : Each allocation is backed by a dedicated run.  Metadata are stored
//  *           in the associated arena chunk header maps.
//  *
//  *   Huge : Each allocation is backed by a dedicated contiguous set of chunks.
//  *          Metadata are stored in a separate red-black tree.
//  *
//  *******************************************************************************
//  */

// /*
//  * Set to false if single-threaded.  Even better, rip out all of the code that
//  * doesn't get used if __isthreaded is false, so that libpthread isn't
//  * necessary.
//  */
const system = @import("std").linux;

const std = @import("std");
const assert = std.debug.assert;
const io = std.io;
//#include "rb.h"
const rb = @import("redblack.zig");

pub error ErrNoMem;

// defines
var HEAP_TRACKING = false;
var __isthreaded = false;
var HAVE_THREADS = false;
var NO_TLS = true;
var MALLOC_DSS = false;

// MALLOC_PRODUCTION disables assertions and statistics gathering.  It
// also defaults the A and J runtime options to off.  These settings
// are appropriate for production systems.
const MALLOC_PRODUCTION = false;

// MALLOC_DEBUG enables assertions and other sanity checks, and
// disables inline functions.
//var MALLOC_DEBUG = false;
var MALLOC_DEBUG = true; // if (MALLOC_PRODUCTION == false) true else false;
// MALLOC_STATS enables statistics calculation.
var MALLOC_STATS = true; //  if (MALLOC_PRODUCTION == false) true else false;
// var MALLOC_STATS = false;


// if (MALLOC_PRODUCTION == false) {
//     MALLOC_DEBUG = true;
//     MALLOC_STATS = true;
// }

// MALLOC_TINY enables support for tiny objects, which are smaller
// than one quantum.
var MALLOC_TINY = true;

// MALLOC_MAG enables a magazine-based thread-specific caching layer
// for small objects.  This makes it possible to allocate/deallocate
// objects without any locking when the cache is in the steady state.
//
// If MALLOC_MAG is enabled, make sure that _malloc_thread_cleanup()
// is called by each thread just before it exits.
var MALLOC_MAG = false;

// MALLOC_BALANCE enables monitoring of arena lock contention and dynamically
// re-balances arena load if exponentially averaged contention exceeds a
// certain threshold.
// var MALLOC_BALANCE = false; // true

// MALLOC_DSS enables use of sbrk(2) to allocate chunks from the data storage
// segment (DSS).  In an ideal world, this functionality would be completely
// unnecessary, but we are burdened by history and the lack of resource limits
// for anonymous mapped memory.
// var MALLOC_DSS = false;

var _GNU_SOURCE = true; // For mremap(2)
inline fn issetugid() -> usize { 0 }
//#define __DECONST(type, var)    ((type)(uintptr_t)(const void *)(var))

const SIZE_T_MAX = @maxValue(usize);

// #ifdef MALLOC_DEBUG
//    /* Disable inlining to make debugging easier. */
// #  define inline
// #endif

//* Size of stack-allocated buffer passed to strerror_r(). */
const STRERROR_BUF = 64;

// The const_size2bin table is sized according to PAGESIZE_2POW, but for
// correctness reasons, we never assume that
// (pagesize == (1U << * PAGESIZE_2POW)).
//
// Minimum alignment of allocations is 2^QUANTUM_2POW bytes.
// #ifdef __i386__
// #  define PAGESIZE_2POW         12
// #  define QUANTUM_2POW          4
// #  define SIZEOF_PTR_2POW       2
// #  define CPU_SPINWAIT          __asm__ volatile("pause")
// #endif
// #ifdef __ia64__
// #  define PAGESIZE_2POW         12
// #  define QUANTUM_2POW          4
// #  define SIZEOF_PTR_2POW       3
// #endif
// #ifdef __alpha__
// #  define PAGESIZE_2POW         13
// #  define QUANTUM_2POW          4
// #  define SIZEOF_PTR_2POW       3
// #  define NO_TLS
// #endif
// #ifdef __sparc64__
// #  define PAGESIZE_2POW         13
// #  define QUANTUM_2POW          4
// #  define SIZEOF_PTR_2POW       3
// #  define NO_TLS
// #endif
// #ifdef __amd64__
const PAGESIZE_2POW   = usize(12);
const QUANTUM_2POW    =  usize(4);
const SIZEOF_PTR_2POW =  usize(3);
//const CPU_SPINWAIT = asm volatile("pause");

inline fn cpuSpinWait() {
    switch (@compileVar("arch")) {
        i386 => asm volatile("pause"),
        else => {},
    }
}

// #endif
// #ifdef __arm__
// #  define PAGESIZE_2POW         12
// #  define QUANTUM_2POW          3
// #  define SIZEOF_PTR_2POW       2
// #  define NO_TLS
// #endif
// #ifdef __mips__
// #  define PAGESIZE_2POW         12
// #  define QUANTUM_2POW          3
// #  define SIZEOF_PTR_2POW       2
// #  define NO_TLS
// #endif
// #ifdef __powerpc__
// #  define PAGESIZE_2POW         12
// #  define QUANTUM_2POW          4
// #  define SIZEOF_PTR_2POW       2
// #endif

// #ifndef NO_TLS
// #pragma message "! NO_TLS"
// #endif

const QUANTUM = (1 << QUANTUM_2POW);
const QUANTUM_MASK = (QUANTUM - 1);

const SIZEOF_PTR = (1 << SIZEOF_PTR_2POW);

//* sizeof(int) == (1U << SIZEOF_INT_2POW). */
// #ifndef SIZEOF_INT_2POW
// #  define SIZEOF_INT_2POW       2
// #endif
const SIZEOF_INT_2POW = usize(2);

// We can't use TLS in non-PIC programs, since TLS relies on loader magic.
// #if (!defined(PIC) && !defined(NO_TLS))
// #  define NO_TLS
// #endif

var MALLOC_BALANCE = false;// if (NO_TLS) false else true;
// if (NO_TLS) {
//     //* MALLOC_BALANCE requires TLS. */
//     MALLOC_BALANCE = false;
// }
// Size and alignment of memory chunks that are allocated by the OS's
// virtual memory system.
const CHUNK_2POW_DEFAULT = usize(20);

// Maximum number of dirty pages per arena.
const DIRTY_MAX_DEFAULT = usize(1 << 9);

// Maximum size of L1 cache line.  This is used to avoid cache line
// aliasing.  In addition, this controls the spacing of
// cacheline-spaced size classes.
const CACHELINE_2POW = usize(6);
const CACHELINE = (1 << CACHELINE_2POW);
const CACHELINE_MASK = (CACHELINE - 1);

// Subpages are an artificially designated partitioning of pages.
// Their only purpose is to support subpage-spaced size classes.
//
// There must be at least 4 subpages per page, due to the way size
// classes are handled.
const SUBPAGE_2POW = 8;
const SUBPAGE = (1 << SUBPAGE_2POW);
const SUBPAGE_MASK = (SUBPAGE - 1);

//* Smallest size class to support. */
var TINY_MIN_2POW = usize(1); // if (MALLOC_TINY) 1 else 0;
// if (MALLOC_TINY) {
//     TINY_MIN_2POW = 1;
// }

// Maximum size class that is a multiple of the quantum, but not
// (necessarily) a power of 2.  Above this size, allocations are
// rounded up to the nearest power of 2.
const QSPACE_MAX_2POW_DEFAULT = usize(7);

// Maximum size class that is a multiple of the cacheline, but not
// (necessarily) a power of 2.  Above this size, allocations are
// rounded up to the nearest power of 2.
const CSPACE_MAX_2POW_DEFAULT = usize(9);

// RUN_MAX_OVRHD indicates maximum desired run header overhead.  Runs
// are sized as small as possible such that this setting is still
// honored, without violating other constraints.  The goal is to make
// runs as small as possible without exceeding a per run external
// fragmentation threshold.
//
// We use binary fixed point math for overhead computations, where the
// binary point is implicitly RUN_BFP bits to the left.
//
// Note that it is possible to set RUN_MAX_OVRHD low enough that it
// cannot be honored for some/all object sizes, since there is one bit
// of header overhead per object (plus a constant).  This constraint
// is relaxed (ignored) for runs that are so small that the per-region
// overhead is greater than:
//
// (RUN_MAX_OVRHD / (reg_size << (3+RUN_BFP))
const RUN_BFP = usize(12);
//*                                   \/   Implicit binary fixed point. */
const RUN_MAX_OVRHD = usize(0x0000003d);
const RUN_MAX_OVRHD_RELAX = usize(0x00001800);

// Put a cap on small object run size.  This overrides RUN_MAX_OVRHD.
const RUN_MAX_SMALL =  (12 * DEFAULT_PAGE_SIZE);

// Hyper-threaded CPUs may need a special instruction inside spin
// loops in order to yield to another virtual CPU.  If no such
// instruction is defined above, make CPU_SPINWAIT a no-op.
// #ifndef CPU_SPINWAIT
// #  define CPU_SPINWAIT
// #endif

// Adaptive spinning must eventually switch to blocking, in order to
// avoid the potential for priority inversion deadlock.  Backing off
// past a certain point can actually waste time.
const SPIN_LIMIT_2POW = 11;

// Conversion from spinning to blocking is expensive; we use (1U <<
// BLOCK_COST_2POW) to estimate how many more times costly blocking is than
// worst-case spinning.
const BLOCK_COST_2POW = 4;

//  * We use an exponential moving average to track recent lock contention,
//  * where the size of the history window is N, and alpha=2/(N+1).
//  *
//  * Due to integer math rounding, very small values here can cause
//  * substantial degradation in accuracy, thus making the moving average decay
//  * faster than it would with precise calculation.
const BALANCE_ALPHA_INV_2POW = usize(0); // if (MALLOC_BALANCE) 9 else 0;
// Threshold value for the exponential moving contention average at which to
// re-assign a thread.
const BALANCE_THRESHOLD_DEFAULT = usize(0); //if (MALLOC_BALANCE) (1 << (SPIN_LIMIT_2POW - 4)) else 0;
// #ifdef MALLOC_BALANCE
// #  define BALANCE_ALPHA_INV_2POW        9
// #  define BALANCE_THRESHOLD_DEFAULT     (1 << (SPIN_LIMIT_2POW-4))
// #endif

inline fn ffs(v: var) -> @typeOf(v) {
    //  int ret = sizeof(unsigned long) * CHAR_BIT - 1;
    //	return x ? ret - __builtin_clzl(x) : ret;
    return ((@sizeOf(@typeOf(v)) * 8) - 1) -  @clz(@typeOf(v), v);
}


//******************************************************************************/
// #if HAVE_THREADS != 0
// typedef pthread_mutex_t malloc_mutex_t;
// typedef pthread_mutex_t malloc_spinlock_t;
// #else
// typedef int malloc_mutex_t;
// typedef int malloc_spinlock_t;
// #endif

// These are fakes so that we can keep the API

const malloc_mutex_t = isize;
const malloc_spinlock_t = isize;
const pthread_mutex_t = isize;

// Set to true once the allocator has been initialized.
var malloc_initialized = false;

// Used to avoid initialization races.
// #if HAVE_THREADS == 0
// #define PTHREAD_ADAPTIVE_MUTEX_INITIALIZER_NP 0
// #endif
const PTHREAD_ADAPTIVE_MUTEX_INITIALIZER_NP = isize(0);
var init_lock = malloc_mutex_t(PTHREAD_ADAPTIVE_MUTEX_INITIALIZER_NP);


//******************************************************************************
// Statistics data structures.
const stats = @import("zemalloc_stats.zig");
const malloc_bin_stats_t = stats.malloc_bin_stats_t;
const arena_stats_t = stats.arena_stats_t;
const chunk_stats_t = stats.chunk_stats_t;
//******************************************************************************

//******************************************************************************
// Extent data structures.
//******************************************************************************
pub struct extent_node {
    link: rb.rb_node(&extent_node),
    // Pointer to the extent that this tree node is responsible for
    addr: usize,
    // Total region size
    size: usize,
}
const extent_node_t = extent_node;
// /******************************************************************************/
// /*
//  * Arena data structures.
//  */
//typedef struct arena_s arena_t;
//typedef struct arena_bin_s arena_bin_t;

//* Each element of the chunk map corresponds to one page within the chunk. */
struct arena_chunk_map_t {
    // Linkage for run trees.  There are two disjoint uses:
    //
    // 1) arena_t's runs_avail tree.
    // 2) arena_run_t conceptually uses this linkage for in-use non-full
    //    runs, rather than directly embedding linkage.
    link: rb.rb_node(&arena_chunk_map_t),

    // Run address (or size) and various flags are stored together.  The bit
    // layout looks like (assuming 32-bit system):
    //
    //   ???????? ???????? ????---- ---kdzla
    //
    // ? : Unallocated: Run address for first/last pages, unset for internal
    //                  pages.
    //     Small: Run address.
    //     Large: Run size for first page, unset for trailing pages.
    // - : Unused.
    // k : key?
    // d : dirty?
    // z : zeroed?
    // l : large?
    // a : allocated?
    //
    // Following are example bit patterns for the three types of runs.
    //
    // r : run address
    // s : run size
    // x : don't care
    // - : 0
    // [dzla] : bit set
    //
    //   Unallocated:
    //     ssssssss ssssssss ssss---- --------
    //     xxxxxxxx xxxxxxxx xxxx---- ----d---
    //     ssssssss ssssssss ssss---- -----z--
    //
    //   Small:
    //     rrrrrrrr rrrrrrrr rrrr---- -------a
    //     rrrrrrrr rrrrrrrr rrrr---- -------a
    //     rrrrrrrr rrrrrrrr rrrr---- -------a
    //
    //   Large:
    //     ssssssss ssssssss ssss---- ------la
    //     -------- -------- -------- ------la
    //     -------- -------- -------- ------la
    bits: usize,
}
const CHUNK_MAP_KEY       = usize(0x10);
const CHUNK_MAP_DIRTY     = usize(0x08);
const CHUNK_MAP_ZEROED    = usize(0x04);
const CHUNK_MAP_LARGE     = usize(0x02);
const CHUNK_MAP_ALLOCATED = usize(0x01);

//typedef rb_tree(arena_chunk_map_t) arena_avail_tree_t;
//typedef rb_tree(arena_chunk_map_t) arena_run_tree_t;
const arena_avail_tree_t = rb.rb_tree(arena_chunk_map_t, arena_avail_comp);
const arena_run_tree_t = rb.rb_tree(arena_chunk_map_t, arena_run_comp);

//* Arena chunk header. */
//typedef struct arena_chunk_s arena_chunk_t;
struct arena_chunk_t {
        // Arena that owns the chunk.
        arena: &arena_t,

        // Linkage for the arena's chunks_dirty tree.
        link: rb.rb_node(&arena_chunk_t),

        // Number of dirty pages.
        ndirty: usize,

        //* Map of pages within chunk that keeps track of free/large/small. */
        // TODO[zig] map: [1]arena_chunk_map_t, //* Dynamically sized. */
        map: arena_chunk_map_t, //* Dynamically sized. */
}

//typedef rb_tree(arena_chunk_t) arena_chunk_tree_t;
const arena_chunk_tree_t = rb.rb_tree(arena_chunk_t, arena_chunk_comp);
//typedef struct arena_run_s arena_run_t;
const ARENA_RUN_MAGIC = u32(0x384adf93);

struct arena_run_t {
    magic: u32,

    // Bin this run is associated with.
    bin:    &arena_bin_t,

    // Index of first element that might have a free region.
    regs_minelm: usize,

    // Number of free regions in run.
    nfree: usize,

    // Bitmask of in-use regions (0: in use, 1: free).
    regs_mask: u32, // Dynamically sized.
}

struct arena_bin_t {
    // Current run being used to service allocations of this bin's size
    // class.
    runcur: &arena_run_t,

    // Tree of non-full runs.  This tree is used when looking for an
    // existing run when runcur is no longer usable.  We choose the
    // non-full run that is lowest in memory; this policy tends to keep
    // objects packed well, and it can also help reduce the number of
    // almost-empty chunks.
    runs: arena_run_tree_t,

    // Size of regions in a run for this bin's size class.
    reg_size: usize,

    //* Total size of a run for this bin's size class. */
    run_size: usize,

    //* Total number of regions in a run for this bin's size class. */
    nregs: u32,

    //* Number of elements in a run's regs_mask for this bin's size class. */
    regs_mask_nelms: u32,

    //* Offset of first region in a run for this bin's size class. */
    reg0_offset: u32,

    // #ifdef MALLOC_STATS
    //* Bin statistics. */
    stats: malloc_bin_stats_t,
    // #endif
}

const ARENA_MAGIC = u32(0x947d3d24);

struct arena_t {
    magic: u32,

    // All operations on this arena require that lock be locked.
    lock: pthread_mutex_t,

    // #ifdef MALLOC_STATS
    stats: arena_stats_t,
    // #endif

    // Tree of dirty-page-containing chunks this arena manages.
    chunks_dirty:    arena_chunk_tree_t,

    // In order to avoid rapid chunk allocation/deallocation when an arena
    // oscillates right on the cusp of needing a new chunk, cache the most
    // recently freed chunk.  The spare is left in the arena's chunk trees
    // until it is deleted.
    //
    // There is one spare chunk per arena, rather than one spare total, in
    // order to avoid interactions between multiple threads that could make
    // a single spare inadequate.
    spare: &arena_chunk_t,

    // Current count of pages within unused runs that are
    // potentially dirty, and for which madvise(... MADV_DONTNEED)
    // has not been called.  By tracking this, we can institute a
    // limit on how much dirty unused memory is mapped for each
    // arena.
    ndirty: usize,

    // Size/address-ordered tree of this arena's available runs.
    // This tree is used for first-best-fit run allocation.
    runs_avail:   arena_avail_tree_t,

    // #ifdef MALLOC_BALANCE
    // The arena load balancing machinery needs to keep track of
    // how much lock contention there is.  This value is
    // exponentially averaged.
    contention: u32,
    // #endif

    // bins is used to store rings of free regions of the following sizes,
    // assuming a 16-byte quantum, 4kB pagesize, and default MALLOC_OPTIONS.
    //
    //   bins[i] | size |
    //   --------+------+
    //        0  |    2 |
    //        1  |    4 |
    //        2  |    8 |
    //   --------+------+
    //        3  |   16 |
    //        4  |   32 |
    //        5  |   48 |
    //        6  |   64 |
    //           :      :
    //           :      :
    //       33  |  496 |
    //       34  |  512 |
    //   --------+------+
    //       35  | 1024 |
    //       36  | 2048 |
    //   --------+------+
    // TODO: Forced it to 37, should be dynamically sized, currently not in Zig
    // bins:    [37]arena_bin_t, // Dynamically sized
    bins:    arena_bin_t, // Dynamically sized
}

//******************************************************************************
// Magazine data structures.
//******************************************************************************

//******************************************************************************
// Data.
//******************************************************************************

//* Number of CPUs. */
var ncpus = usize(1);

pub const DEFAULT_PAGE_SIZE = usize(4096);
pub var pagesize: usize = usize(DEFAULT_PAGE_SIZE);
//* VM page size. */
// TODO: Why does gdb report sizeof(pagesize_mask/2pow) = 4, it surely is 8
pub var pagesize_2pow: usize = usize(12);
pub var pagesize_mask: usize = usize(DEFAULT_PAGE_SIZE) - 1;

//* Various bin-related settings. */
//* Number of (2^n)-spaced tiny bins. */
var ntbins = usize(0); // if (MALLOC_TINY) ((unsigned)(QUANTUM_2POW - TINY_MIN_2POW)) else 0;
var nqbins = usize(0); // Number of quantum-spaced bins.
var ncbins = usize(0); // Number of cacheline-spaced bins.
var nsbins = usize(0); // Number of subpage-spaced bins.
var nbins  = usize(0);
// #ifdef MALLOC_TINY
// #  define               tspace_max      ((size_t)(QUANTUM >> 1))
// #endif
var qspace_min = QUANTUM;
var qspace_max = usize(0);
var cspace_min = usize(0);
var cspace_max = usize(0);
var sspace_min = usize(0);
var sspace_max = DEFAULT_PAGE_SIZE - SUBPAGE;
var bin_maxclass = DEFAULT_PAGE_SIZE - SUBPAGE;

// static uint8_t const    *size2bin;
var size2bin: []u8 = undefined;
//  * const_size2bin is a static constant lookup table that in the common case can
//  * be used as-is for size2bin.  For dynamically linked programs, this avoids
//  * a page of memory overhead per process.
// #define S2B_1(i)        i,
// #define S2B_2(i)        S2B_1(i) S2B_1(i)
// #define S2B_4(i)        S2B_2(i) S2B_2(i)
// #define S2B_8(i)        S2B_4(i) S2B_4(i)
// #define S2B_16(i)       S2B_8(i) S2B_8(i)
// #define S2B_32(i)       S2B_16(i) S2B_16(i)
// #define S2B_64(i)       S2B_32(i) S2B_32(i)
// #define S2B_128(i)      S2B_64(i) S2B_64(i)
// #define S2B_256(i)      S2B_128(i) S2B_128(i)

fn S2B_1(i: u8) -> u8 { i }
fn S2B_2(i: u8) -> u8 { S2B_1(i) + S2B_1(i)}
fn S2B_4(i: u8) -> u8 { S2B_2(i) + S2B_2(i)}
fn S2B_8(i: u8) -> u8 { S2B_4(i) + S2B_4(i)}
fn S2B_16(i: u8) -> u8 { S2B_8(i) + S2B_8(i)}
fn S2B_32(i: u8) -> u8 { S2B_16(i) + S2B_16(i)}
fn S2B_64(i: u8) -> u8 { S2B_32(i) + S2B_32(i)}
fn S2B_128(i: u8) -> u8 { S2B_64(i) + S2B_64(i)}
fn S2B_256(i: u8) -> u8 { S2B_128(i) + S2B_128(i)}

const S2B_QMIN = u8(0);
const S2B_CMIN = (S2B_QMIN + 16);
const S2B_SMIN = (S2B_CMIN + 6);
var const_size2bin: [(1 << PAGESIZE_2POW) - 255]u8 = zeroes;

// We'd really like this to happen at compile time...
fn prep_size2bin() {
    // @setFnStaticEval(this, true);
    var ix = usize(0);
    const_size2bin[ix] = 0xff;
    ix += 1;
    // S2B_16(0),                  //   16
    {var i = usize(0);
        while(i < 16; {i += 1; ix += 1}) {
            const_size2bin[ix] = S2B_QMIN;
        }
    };
    // S2B_16(S2B_QMIN + 1),       //   32
    // S2B_16(S2B_QMIN + 2),       //   48
    // S2B_16(S2B_QMIN + 3),       //   64
    // S2B_16(S2B_QMIN + 4),       //   80
    // S2B_16(S2B_QMIN + 5),       //   96
    // S2B_16(S2B_QMIN + 6),       //  112
    // S2B_16(S2B_QMIN + 7),       //  128
    {var j = u8(1);
        while (j < 8; j += 1) {
            var i = usize(0); 
            while(i < 16; {i += 1; ix += 1}) {
                const_size2bin[ix] = S2B_QMIN + j;
            }
        }
    };
    // S2B_64(S2B_CMIN + 0),       //  192
    // S2B_64(S2B_CMIN + 1),       //  256
    // S2B_64(S2B_CMIN + 2),       //  320
    // S2B_64(S2B_CMIN + 3),       //  384
    // S2B_64(S2B_CMIN + 4),       //  448
    // S2B_64(S2B_CMIN + 5),       //  512
    {var j = u8(0);
        while (j < 6; j += 1) {
            var i = usize(0);
            while(i < 64; {i += 1; ix += 1}) {
                const_size2bin[ix] = S2B_CMIN + j;
            }
        }
    };
    // S2B_256(S2B_SMIN + 0),      //  768
    // S2B_256(S2B_SMIN + 1),      // 1024
    // S2B_256(S2B_SMIN + 2),      // 1280
    // S2B_256(S2B_SMIN + 3),      // 1536
    // S2B_256(S2B_SMIN + 4),      // 1792
    // S2B_256(S2B_SMIN + 5),      // 2048
    // S2B_256(S2B_SMIN + 6),      // 2304
    // S2B_256(S2B_SMIN + 7),      // 2560
    // S2B_256(S2B_SMIN + 8),      // 2816
    // S2B_256(S2B_SMIN + 9),      // 3072
    // S2B_256(S2B_SMIN + 10),     // 3328
    // S2B_256(S2B_SMIN + 11),     // 3584
    // S2B_256(S2B_SMIN + 12),     // 3840
    {var j = u8(0);
        while (j < 13; j += 1) {
            var i = usize(0); 
            while(i < 256; {i += 1; ix += 1}) {
                const_size2bin[ix] = S2B_SMIN + j;
            }
        }
    };
    if (@compileVar("is_test")){
        %%io.stdout.printInt(usize, ix);
        %%io.stdout.printf("\n");
        // for (const_size2bin) |x, i| {
        //     %%io.stdout.printInt(usize, i);
        //     %%io.stdout.write(":");
        //     %%io.stdout.printInt(u8, x);
        //     %%io.stdout.printf("\n");
        // }
    }
    assert(ix == const_size2bin.len);
}
// static const uint8_t    const_size2bin[(1 << PAGESIZE_2POW) - 255] = {
//         S2B_1(0xff)            /*    0 */
// #if (QUANTUM_2POW == 4)
// /* 64-bit system ************************/
// #  ifdef MALLOC_TINY
//         S2B_2(0)                /*    2 */
//         S2B_2(1)                /*    4 */
//         S2B_4(2)                /*    8 */
//         S2B_8(3)                /*   16 */
// #    define S2B_QMIN 3
// #  else
//         S2B_16(0)               /*   16 */
// #    define S2B_QMIN 0
// #  endif
//         S2B_16(S2B_QMIN + 1)    /*   32 */
//         S2B_16(S2B_QMIN + 2)    /*   48 */
//         S2B_16(S2B_QMIN + 3)    /*   64 */
//         S2B_16(S2B_QMIN + 4)    /*   80 */
//         S2B_16(S2B_QMIN + 5)    /*   96 */
//         S2B_16(S2B_QMIN + 6)    /*  112 */
//         S2B_16(S2B_QMIN + 7)    /*  128 */
// #  define S2B_CMIN (S2B_QMIN + 8)
// #else
// /* 32-bit system ************************/
// #  ifdef MALLOC_TINY
//         S2B_2(0)                /*    2 */
//         S2B_2(1)                /*    4 */
//         S2B_4(2)                /*    8 */
// #    define S2B_QMIN 2
// #  else
//         S2B_8(0)                /*    8 */
// #    define S2B_QMIN 0
// #  endif
//         S2B_8(S2B_QMIN + 1)     /*   16 */
//         S2B_8(S2B_QMIN + 2)     /*   24 */
//         S2B_8(S2B_QMIN + 3)     /*   32 */
//         S2B_8(S2B_QMIN + 4)     /*   40 */
//         S2B_8(S2B_QMIN + 5)     /*   48 */
//         S2B_8(S2B_QMIN + 6)     /*   56 */
//         S2B_8(S2B_QMIN + 7)     /*   64 */
//         S2B_8(S2B_QMIN + 8)     /*   72 */
//         S2B_8(S2B_QMIN + 9)     /*   80 */
//         S2B_8(S2B_QMIN + 10)    /*   88 */
//         S2B_8(S2B_QMIN + 11)    /*   96 */
//         S2B_8(S2B_QMIN + 12)    /*  104 */
//         S2B_8(S2B_QMIN + 13)    /*  112 */
//         S2B_8(S2B_QMIN + 14)    /*  120 */
//         S2B_8(S2B_QMIN + 15)    /*  128 */
// #  define S2B_CMIN (S2B_QMIN + 16)
// #endif
// /****************************************/
//         S2B_64(S2B_CMIN + 0)    /*  192 */
//         S2B_64(S2B_CMIN + 1)    /*  256 */
//         S2B_64(S2B_CMIN + 2)    /*  320 */
//         S2B_64(S2B_CMIN + 3)    /*  384 */
//         S2B_64(S2B_CMIN + 4)    /*  448 */
//         S2B_64(S2B_CMIN + 5)    /*  512 */
// #  define S2B_SMIN (S2B_CMIN + 6)
//         S2B_256(S2B_SMIN + 0)   /*  768 */
//         S2B_256(S2B_SMIN + 1)   /* 1024 */
//         S2B_256(S2B_SMIN + 2)   /* 1280 */
//         S2B_256(S2B_SMIN + 3)   /* 1536 */
//         S2B_256(S2B_SMIN + 4)   /* 1792 */
//         S2B_256(S2B_SMIN + 5)   /* 2048 */
//         S2B_256(S2B_SMIN + 6)   /* 2304 */
//         S2B_256(S2B_SMIN + 7)   /* 2560 */
//         S2B_256(S2B_SMIN + 8)   /* 2816 */
//         S2B_256(S2B_SMIN + 9)   /* 3072 */
//         S2B_256(S2B_SMIN + 10)  /* 3328 */
//         S2B_256(S2B_SMIN + 11)  /* 3584 */
//         S2B_256(S2B_SMIN + 12)  /* 3840 */
// #if (PAGESIZE_2POW == 13)
//         S2B_256(S2B_SMIN + 13)  /* 4096 */
//         S2B_256(S2B_SMIN + 14)  /* 4352 */
//         S2B_256(S2B_SMIN + 15)  /* 4608 */
//         S2B_256(S2B_SMIN + 16)  /* 4864 */
//         S2B_256(S2B_SMIN + 17)  /* 5120 */
//         S2B_256(S2B_SMIN + 18)  /* 5376 */
//         S2B_256(S2B_SMIN + 19)  /* 5632 */
//         S2B_256(S2B_SMIN + 20)  /* 5888 */
//         S2B_256(S2B_SMIN + 21)  /* 6144 */
//         S2B_256(S2B_SMIN + 22)  /* 6400 */
//         S2B_256(S2B_SMIN + 23)  /* 6656 */
//         S2B_256(S2B_SMIN + 24)  /* 6912 */
//         S2B_256(S2B_SMIN + 25)  /* 7168 */
//         S2B_256(S2B_SMIN + 26)  /* 7424 */
//         S2B_256(S2B_SMIN + 27)  /* 7680 */
//         S2B_256(S2B_SMIN + 28)  /* 7936 */
// #endif
// };

// Various chunk-related settings.
var chunksize = usize(0);
var chunksize_mask = usize(0); // (chunksize - 1).
var chunk_npages = usize(0);
var arena_chunk_header_npages = usize(0);
var arena_maxclass = usize(0); // Max size class for arenas.

//********/
// * Chunks.

//* Protects chunk-related data structures. */
var huge_mtx = malloc_mutex_t(0);

//* Tree of chunks that are stand-alone huge allocations. */
var huge: rb.rb_tree(extent_node_t, extent_ad_comp) = zeroes;

//#ifdef MALLOC_STATS
// Huge allocation statistics.
var huge_nmalloc = u64(0);
var huge_ndalloc = u64(0);
var huge_allocated = usize(0);
//#endif

//****************************
// base (internal allocation).
//****************************

// Current pages that are being used for internal memory allocations.
// These pages are carved up in cacheline-size quanta, so that there
// is no chance of false cache line sharing.
var base_pages: ?&u8 = null;
var base_next_addr: ?&u8 = null;
var base_past_addr: ?&u8 = null; // Addr immediately past base_pages.
var base_nodes: ?&extent_node_t = null;
var base_mtx: malloc_mutex_t = undefined;

//#ifdef MALLOC_STATS
var base_mapped = usize(0);
//#endif

//********
// Arenas.
//********

// Arenas that are used to service external requests.  Not all elements of the
// arenas array are necessarily used; arenas are created lazily as needed.
//static arena_t          **arenas;
var arenas: &&arena_t = undefined;
var narenas = usize(0);
//#ifndef NO_TLS
//#  ifdef MALLOC_BALANCE
var narenas_2pow = usize(0);
//#  else
var next_arena = usize(0);
//#  endif
//#endif
//static pthread_mutex_t  arenas_lock; //* Protects arenas initialization. */
var arenas_lock = pthread_mutex_t(0); // = undefined;

//#ifndef NO_TLS
//  * Map of pthread_self() --> arenas[???], used for selecting an arena to use
//  * for allocations.
//static __thread arena_t *arenas_map;
//#endif
var arenas_map: &arena_t = undefined;

inline fn pthread_self() -> usize { usize(0) }

// #ifdef MALLOC_STATS
//* Chunk statistics. */
var stats_chunks: chunk_stats_t = zeroes;
// #endif

//*******************************
// Runtime configuration options.
//*******************************
//const char      *_malloc_options;

//#ifndef MALLOC_PRODUCTION
var opt_abort = true;
var opt_junk = true;
//#else
//static bool     opt_abort = false;
//static bool     opt_junk = false;
//#endif
var opt_dirty_max = usize(DIRTY_MAX_DEFAULT);
//#ifdef MALLOC_BALANCE
var opt_balance_threshold = u64(BALANCE_THRESHOLD_DEFAULT);
//#endif
var opt_print_stats = false;
var opt_qspace_max_2pow = QSPACE_MAX_2POW_DEFAULT;
var opt_cspace_max_2pow = CSPACE_MAX_2POW_DEFAULT;
var opt_chunk_2pow = CHUNK_2POW_DEFAULT;
var opt_utrace = false;
var opt_sysv = false;
var opt_xmalloc = false;
var opt_zero = false;
var opt_narenas_lshift = usize(0);
var opt_mmap = true;

// typedef struct {
//         void    *p;
//         size_t  s;
//         void    *r;
// } malloc_utrace_t;

// #ifdef MALLOC_STATS
// #define UTRACE(a, b, c)                                                 \
//         if (opt_utrace) {                                               \
//                 malloc_utrace_t ut;                                     \
//                 ut.p = (a);                                             \
//                 ut.s = (b);                                             \
//                 ut.r = (c);                                             \
//                 utrace(&ut, sizeof(ut));                                \
//         }
// #else
// #define UTRACE(a, b, c)
// #endif

// /******************************************************************************/
// /*
//  * Begin function prototypes for non-inline static functions.
//  */

// static bool     malloc_mutex_init(malloc_mutex_t *mutex);
// static bool     malloc_spin_init(pthread_mutex_t *lock);
// static void     wrtmessage(const char *p1, const char *p2, const char *p3,
//                 const char *p4);
// #ifdef MALLOC_STATS
// static void     malloc_printf(const char *format, ...);
// #endif
// static char     *umax2s(uintmax_t x, char *s);
// static bool     base_pages_alloc_mmap(size_t minsize);
// static bool     base_pages_alloc(size_t minsize);
// static void     *base_alloc(size_t size);
// static extent_node_t *base_node_alloc(void);
// static void     base_node_dealloc(extent_node_t *node);
// #ifdef MALLOC_STATS
// static void     stats_print(arena_t *arena);
// #endif
// static void     *pages_map(void *addr, size_t size);
// static void     pages_unmap(void *addr, size_t size);
// static void     *chunk_alloc_mmap(size_t size);
// static void     *chunk_alloc(size_t size, bool zero);
// static void     chunk_dealloc_mmap(void *chunk, size_t size);
// static void     chunk_dealloc(void *chunk, size_t size);
// #ifndef NO_TLS
// static arena_t  *choose_arena_hard(void);
// #endif
// static void     arena_run_split(arena_t *arena, arena_run_t *run, size_t size,
//     bool large, bool zero);
// static arena_chunk_t *arena_chunk_alloc(arena_t *arena);
// static void     arena_chunk_dealloc(arena_t *arena, arena_chunk_t *chunk);
// static arena_run_t *arena_run_alloc(arena_t *arena, size_t size, bool large,
//     bool zero);
// static void     arena_purge(arena_t *arena);
// static void     arena_run_dalloc(arena_t *arena, arena_run_t *run, bool dirty);
// static void     arena_run_trim_head(arena_t *arena, arena_chunk_t *chunk,
//     arena_run_t *run, size_t oldsize, size_t newsize);
// static void     arena_run_trim_tail(arena_t *arena, arena_chunk_t *chunk,
//     arena_run_t *run, size_t oldsize, size_t newsize, bool dirty);
// static arena_run_t *arena_bin_nonfull_run_get(arena_t *arena, arena_bin_t *bin);
// static void     *arena_bin_malloc_hard(arena_t *arena, arena_bin_t *bin);
// static size_t   arena_bin_run_size_calc(arena_bin_t *bin, size_t min_run_size);
// #ifdef MALLOC_BALANCE
// static void     arena_lock_balance_hard(arena_t *arena);
// #endif
// static void     *arena_malloc_large(arena_t *arena, size_t size, bool zero);
// static void     *arena_palloc(arena_t *arena, size_t alignment, size_t size,
//     size_t alloc_size);
// static size_t   arena_salloc(const void *ptr);
// static void     arena_dalloc_large(arena_t *arena, arena_chunk_t *chunk,
//     void *ptr);
// static void     arena_ralloc_large_shrink(arena_t *arena, arena_chunk_t *chunk,
//     void *ptr, size_t size, size_t oldsize);
// static bool     arena_ralloc_large_grow(arena_t *arena, arena_chunk_t *chunk,
//     void *ptr, size_t size, size_t oldsize);
// static bool     arena_ralloc_large(void *ptr, size_t size, size_t oldsize);
// static void     *arena_ralloc(void *ptr, size_t size, size_t oldsize);
// static bool     arena_new(arena_t *arena);
// static arena_t  *arenas_extend(unsigned ind);
// static void     *huge_malloc(size_t size, bool zero);
// static void     *huge_palloc(size_t alignment, size_t size);
// static void     *huge_ralloc(void *ptr, size_t size, size_t oldsize);
// static void     huge_dalloc(void *ptr);
// static void     malloc_print_stats(void);
// #ifdef MALLOC_DEBUG
// static void     size2bin_validate(void);
// #endif
// static bool     size2bin_init(void);
// static bool     size2bin_init_hard(void);
// static unsigned malloc_ncpus(void);
// static bool     malloc_init_hard(void);
// void            _malloc_prefork(void);
// void            _malloc_postfork(void);

// End function prototypes.
//******************************************************************************
// We don't want to depend on vsnprintf() for production builds, since that can
// cause unnecessary bloat for static binaries.  umax2s() provides minimal
// integer printing functionality, so that malloc_printf() use can be limited to
// MALLOC_STATS code.
const UMAX2S_BUFSIZE = 21;
fn umax2s(v: var, s: []u8) -> []u8{
    var i = s.len - 1;
    var x = v;
    s[i] = 0;
    while (true) {
        i -= 1;
        s[i] = "0123456789"[x % 10];
        x /= 10;
        if (x == 0) break;
    }
    return s[i...];
}

/// Define a custom assert() in order to reduce the chances of deadlock during
/// assertion failure.
// #ifdef MALLOC_DEBUG
// #  define assert(e) do {                                                \
//         if (!(e)) {                                                     \
//                 char line_buf[UMAX2S_BUFSIZE];                          \
//                 _malloc_message(__FILE__, ":", umax2s(__LINE__,         \
//                     line_buf), ": Failed assertion: ");                 \
//                 _malloc_message("\"", #e, "\"\n", "");                  \
//                 abort();                                                \
//         }                                                               \
// } while (0)
// #else
// #define assert(e)
// #endif

// #ifdef MALLOC_STATS
// static int
// utrace(const void *addr, size_t len)
// {
//         malloc_utrace_t *ut = (malloc_utrace_t *)addr;
//         assert(len == sizeof(malloc_utrace_t));
//         if (ut->p == null && ut->s == 0 && ut->r == null)
//                 malloc_printf("%d x USER malloc_init()\n", getpid());
//         else if (ut->p == null && ut->r != null) {
//                 malloc_printf("%d x USER %p = malloc(%zu)\n", getpid(), ut->r,
//                     ut->s);
//         } else if (ut->p != null && ut->r != null) {
//                 malloc_printf("%d x USER %p = realloc(%p, %zu)\n", getpid(),
//                     ut->r, ut->p, ut->s);
//         } else
//                 malloc_printf("%d x USER free(%p)\n", getpid(), ut->p);
//         return (0);
// }
// #endif

inline fn _getprogname() -> []u8 {
    return "<jemalloc>";
}

//******************************************************************************
// Begin mutex.
//******************************************************************************
const pthread_mutexattr_t = usize;

fn pthread_mutexattr_init(attr: &pthread_mutexattr_t) -> isize {
    if (usize(attr) != usize(0)) {
        return 0;
    } else {
        return -1;
    }
}

fn pthread_mutexattr_destroy(attr: &pthread_mutexattr_t) -> isize {
    if (usize(attr) != usize(0)) {
        return 0;
    }
    return -1;
}

inline fn pthread_mutex_init(mtx: &pthread_mutex_t, attr: ?&pthread_mutexattr_t) -> isize {
    if (usize(mtx) != usize(0)) {
        *mtx = pthread_mutex_t(0);
        return 0;
    }
    return -1;
}

inline fn pthread_mutex_unlock(mtx: &pthread_mutex_t) -> isize {
    if (usize(mtx) != usize(0)) {
        *mtx -= 1;
        return 0;
    }
    return -1;
}

inline fn pthread_mutex_lock(mtx: &pthread_mutex_t) -> isize {
    if (usize(mtx) != usize(0)) {
        *mtx += 1;
        return 0;
    }
    return -1;
}

inline fn pthread_mutex_trylock(mtx: &pthread_mutex_t) -> isize {
    if (usize(mtx) != usize(0)) {
        if (*mtx == 0) {
            return 0;
        }
    }
    return -1;
}


fn malloc_mutex_init(mutex: &malloc_mutex_t) -> bool {
    if (HAVE_THREADS) {
        var attr: pthread_mutexattr_t = undefined;
        if (pthread_mutexattr_init(&attr) != 0) {
            return true;
        }
        if (pthread_mutex_init(mutex, &attr) != 0) {
            pthread_mutexattr_destroy(&attr);
            return true;
        }
        pthread_mutexattr_destroy(&attr);
    }
    return false;
}

inline fn malloc_mutex_lock(mutex: &malloc_mutex_t) {
    if (HAVE_THREADS) {
        if (__isthreaded) {
            pthread_mutex_lock(mutex);
        }
    }
}

inline fn malloc_mutex_unlock(mutex: &malloc_mutex_t) {
    if (HAVE_THREADS) {
        if (__isthreaded) {
            pthread_mutex_unlock(mutex);
        }
    }
}

//******************************************************************************
// End mutex.
//******************************************************************************
// Begin spin lock.  Spin locks here are actually adaptive mutexes that block
// after a period of spinning, because unbounded spinning would allow for
// priority inversion.
//******************************************************************************
inline fn malloc_spin_init(lock: &pthread_mutex_t) -> bool {
    if (HAVE_THREADS) {
        if (pthread_mutex_init(lock, null) != 0) {
            return true;
        }
    }

    return false;
}

inline fn malloc_spin_lock(lock: &pthread_mutex_t) -> usize {
    var ret = usize(0);

    if (HAVE_THREADS) {
        if (__isthreaded) {
            if (pthread_mutex_trylock(lock) != 0) {
                var i = usize(0);
                // Exponentially back off.
                while (i <= SPIN_LIMIT_2POW; i += 1) {
                    {var j = usize(0); // volatile?
                        while (j < (1 << i); j += 1) {
                            ret += 1;
                            cpuSpinWait();
                        }
                    }
                    if (pthread_mutex_trylock(lock) == 0) {
                        return ret;
                    }
                }
                // Spinning failed.  Block until the lock becomes
                // available, in order to avoid indefinite priority
                // inversion.
                pthread_mutex_lock(lock);
                assert((ret << BLOCK_COST_2POW) != 0);
                return (ret << BLOCK_COST_2POW);
            }
        }
    }

    return ret;
}

inline fn malloc_spin_unlock(lock: &pthread_mutex_t) {
    if (HAVE_THREADS) {
        if (__isthreaded) {
            pthread_mutex_unlock(lock);
        }
    }
}

//******************************************************************************
// End spin lock.
//******************************************************************************
// Begin Utility functions/macros.
//******************************************************************************
const zeutils = @import("zemalloc_utils.zig");
const CHUNK_ADDR2BASE = zeutils.CHUNK_ADDR2BASE;
const CHUNK_ADDR2OFFSET = zeutils.CHUNK_ADDR2OFFSET;
const CHUNK_CEILING = zeutils.CHUNK_CEILING;
const QUANTUM_CEILING = zeutils.QUANTUM_CEILING;
const CACHELINE_CEILING = zeutils.CACHELINE_CEILING;
const SUBPAGE_CEILING = zeutils.SUBPAGE_CEILING;
const PAGE_CEILING = zeutils.PAGE_CEILING;
const getPageSize = zeutils.getPageSize;
const getNumCpus = zeutils.getNumCpus;
const next_power_of_two = zeutils.next_power_of_two;

// #ifdef MALLOC_BALANCE
// Use a simple linear congruential pseudo-random number generator:
//
//   prn(y) = (a*x + c) % m
//
// where the following constants ensure maximal period:
//
//   a == Odd number (relatively prime to 2^n), and (a-1) is a multiple of 4.
//   c == Odd number (relatively prime to 2^n).
//   m == 2^32
//
// See Knuth's TAOCP 3rd Ed., Vol. 2, pg. 17 for details on these constraints.
//
// This choice of m has the disadvantage that the quality of the bits is
// proportional to bit position.  For example. the lowest bit has a cycle of 2,
// the next has a cycle of 4, etc.  For this reason, we prefer to use the upper
// bits.
// #  define PRN_DEFINE(suffix, var, a, c)                                 \
// static inline void                                                      \
// sprn_##suffix(uint32_t seed)                                            \
// {                                                                       \
//         var = seed;                                                     \
// }                                                                       \
//                                                                         \
// static inline uint32_t                                                  \
// prn_##suffix(uint32_t lg_range)                                         \
// {                                                                       \
//         uint32_t ret, x;                                                \
//                                                                         \
//         assert(lg_range > 0);                                           \
//         assert(lg_range <= 32);                                         \
//                                                                         \
//         x = (var * (a)) + (c);                                          \
//         var = x;                                                        \
//         ret = x >> (32 - lg_range);                                     \
//                                                                         \
//         return (ret);                                                   \
// }
// #  define SPRN(suffix, seed)    sprn_##suffix(seed)
// #  define PRN(suffix, lg_range) prn_##suffix(lg_range)
// #endif

// #ifdef MALLOC_BALANCE
// /* Define the PRNG used for arena assignment. */
// static __thread uint32_t balance_x;
// PRN_DEFINE(balance, balance_x, 1297, 1301)
// #endif

//******************************************************************************
fn base_pages_alloc_mmap(minsize: usize) -> bool {
    assert(minsize != 0);
    var csize = PAGE_CEILING(minsize);
    base_pages = pages_map((&u8)(usize(0)), csize);
    if (usize(base_pages) == usize(0)) {
        return true;
    }
    base_next_addr = base_pages;
    base_past_addr = (&u8)(usize(base_pages) + csize);
    // #ifdef MALLOC_STATS
    if (MALLOC_STATS) {
        base_mapped += csize;
    }
    // #endif

    return false;
}

fn base_pages_alloc(minsize: usize) -> bool {
    if (base_pages_alloc_mmap(minsize) == false) {
        return false;
    }

    return true;
}

fn base_alloc(size: usize) -> ?&u8 {
    // Round size up to nearest multiple of the cacheline size.
    var csize = CACHELINE_CEILING(size);

    malloc_mutex_lock(&base_mtx);
    // Make sure there's enough space for the allocation.
    if (usize(base_next_addr) + csize > usize(base_past_addr)) {
        if (base_pages_alloc(csize)) {
            malloc_mutex_unlock(&base_mtx);
            return null;
        }
    }
    // Allocate.
    var ret = base_next_addr;
    base_next_addr = (&u8)(usize(base_next_addr) + csize);
    malloc_mutex_unlock(&base_mtx);

    return ret;
}

fn base_node_alloc() -> ?&extent_node_t {
    var ret = (&extent_node_t)(usize(0));

    malloc_mutex_lock(&base_mtx);
    if (var bn ?= base_nodes) {
        %%io.stdout.printf("have base_nodes\n");
    }
    if (usize(base_nodes) != usize(0)) {
        if (@compileVar("is_test")) {
            %%io.stdout.printf("have base_nodes\n");
        }
        ret = base_nodes ?? {
            malloc_mutex_unlock(&base_mtx);
            return null;
        };
        // *(extent_note_t*)ret
        if (@compileVar("is_test")) {
            %%io.stdout.printf("setting base_nodes\n");
        }
        base_nodes = (&extent_node_t)(ret);
        malloc_mutex_unlock(&base_mtx);
    } else {
        if (@compileVar("is_test")) {
            %%io.stdout.printf("no base_nodes\n");
        }
        malloc_mutex_unlock(&base_mtx);
        if (var rr ?= base_alloc(@sizeOf(extent_node_t))) {
                ret = (&extent_node_t)(rr);
        }
        // TODO forced
        // base_nodes = (&extent_node_t)(ret);
    }

    if (@compileVar("is_test")) {
        %%io.stdout.write("ret=");
        %%io.stdout.printInt(usize, usize(ret));
        %%io.stdout.printf("\n");
    }
    return (ret);
}

fn base_node_dealloc(node: &extent_node_t) {
    var lnode = node;
    malloc_mutex_lock(&base_mtx);
    //*(extent_node_t **)node = base_nodes;
    if (@compileVar("is_test")) {
        %%io.stdout.printInt(usize, usize(base_nodes));
        %%io.stdout.printf("\n");
    }
    if (var bn ?= base_nodes) {
        lnode = bn; // TODO
        if (@compileVar("is_test")) {
            %%io.stdout.printInt(usize, usize(base_nodes));
            %%io.stdout.printf("setting base_nodes\n");
        }
        base_nodes = lnode;
    } else {
        // %%abort();
        base_nodes = node;
    }
    malloc_mutex_unlock(&base_mtx);
}

//******************************************************************************
// #ifdef MALLOC_STATS
fn stats_print(arena: &arena_t) -> %void {
    if (MALLOC_STATS) {
        var s: [UMAX2S_BUFSIZE]u8 = zeroes;
        var ss: [UMAX2S_BUFSIZE]u8 = zeroes;
        %%_malloc_message("dirty:", umax2s(arena.ndirty, s), "", "");
        %%_malloc_message(", sweeps:", umax2s(arena.stats.npurge, s),
                          ", madvise:", umax2s(arena.stats.nmadvise, ss));
        %%_malloc_message(", purged:", umax2s(arena.stats.purged, s), "\n", "");
        %%_malloc_message("small:", umax2s(arena.stats.allocated_small, s),
                          ", nmalloc:", umax2s(arena.stats.nmalloc_small, ss));
        %%_malloc_message(", ndalloc:", umax2s(arena.stats.ndalloc_small, s),
                          "\n", "");
        %%_malloc_message("large:", umax2s(arena.stats.allocated_large, s),
                          ", nmalloc:", umax2s(arena.stats.nmalloc_large, ss));
        %%_malloc_message(", ndalloc:", umax2s(arena.stats.ndalloc_large, s),
                          "\n", "");
        // totals
        %%_malloc_message("mapped:", umax2s(arena.stats.mapped, s),
                          "\n", "");
    }
}
//     unsigned i, gap_start;
//     malloc_printf("total:   %12zu %12llu %12llu\n",
//         arena->stats.allocated_small + arena->stats.allocated_large,
//         arena->stats.nmalloc_small + arena->stats.nmalloc_large,
//         arena->stats.ndalloc_small + arena->stats.ndalloc_large);
//     malloc_printf("bins:     bin   size regs pgs  requests   "
//                   "newruns    reruns maxruns curruns\n");
//     for (i = 0, gap_start = UINT_MAX; i < nbins; i++) {
//             if (arena->bins[i].stats.nruns == 0) {
//                     if (gap_start == UINT_MAX)
//                             gap_start = i;
//             } else {
//                     if (gap_start != UINT_MAX) {
//                             if (i > gap_start + 1) {
//                                     /* Gap of more than one size class. */
//                                     malloc_printf("[%u..%u]\n",
//                                         gap_start, i - 1);
//                             } else {
//                                     /* Gap of one size class. */
//                                     malloc_printf("[%u]\n", gap_start);
//                             }
//                             gap_start = UINT_MAX;
//                     }
//                     malloc_printf(
//                         "%13u %1s %4u %4u %3u %9llu %9llu"
//                         " %9llu %7lu %7lu\n",
//                         i,
//                         i < ntbins ? "T" : i < ntbins + nqbins ? "Q" :
//                         i < ntbins + nqbins + ncbins ? "C" : "S",
//                         arena->bins[i].reg_size,
//                         arena->bins[i].nregs,
//                         arena->bins[i].run_size >> pagesize_2pow,
//                         arena->bins[i].stats.nrequests,
//                         arena->bins[i].stats.nruns,
//                         arena->bins[i].stats.reruns,
//                         arena->bins[i].stats.highruns,
//                         arena->bins[i].stats.curruns);
//             }
//     }
//     if (gap_start != UINT_MAX) {
//             if (i > gap_start + 1) {
//                     /* Gap of more than one size class. */
//                     malloc_printf("[%u..%u]\n", gap_start, i - 1);
//             } else {
//                     /* Gap of one size class. */
//                     malloc_printf("[%u]\n", gap_start);
//             }
//     }
// }
// #endif

//******************************************************************************
// End Utility functions/macros.
//******************************************************************************
// Begin extent tree code.
//******************************************************************************
fn extent_ad_comp(a: &extent_node_t, b: &extent_node_t) -> isize {
    const a_addr = usize(a.addr);
    const b_addr = usize(b.addr);

    return (isize(a_addr > b_addr) - isize(a_addr < b_addr));
}

//* Wrap red-black tree macros in functions. */
// TODO
//rb_wrap(static, extent_tree_ad_, extent_tree_t, extent_node_t, link_ad,
//    extent_ad_comp)

//******************************************************************************
// End extent tree code.
//******************************************************************************
// Begin chunk management functions.
//******************************************************************************
const MAP_FAILED = usize(@maxValue(usize));
fn pages_map(addr: &u8, size: usize) -> ?&u8 {
    // We don't use MAP_FIXED here, because it can cause the *replacement*
    // of existing mappings, and we only want to create new mappings.
    const m = system.mmap((&u8)(usize(0)), size,
                          system.MMAP_PROT_READ | system.MMAP_PROT_WRITE,
                          system.MMAP_MAP_PRIVATE | system.MMAP_MAP_ANON,
                          -1, 0);
    //var ret = (&u8)(mmap(addr, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0));
    var ret = (&u8)(m);

    if (m == MAP_FAILED) {
        ret = (&u8)(usize(0));
    } else if (usize(addr) != usize(0) && usize(ret) != usize(addr)) {
        // We succeeded in mapping memory, but not in the right place.
        if (system.munmap(ret, size) == MAP_FAILED) {
            var buf: []u8 = "error";
            // #if HAVE_THREADS != 0
            //             strerror_r(errno, buf, sizeof(buf));
            // #endif
            %%_malloc_message(_getprogname(), ": (malloc) Error in munmap(): ", buf, "\n");
            if (opt_abort) {
                %%abort();
            }
        }
        ret = (&u8)(usize(0));
    }

    assert((ret == (&u8)(usize(0))) || (addr == (&u8)(usize(0)) && ret != addr)
           || (addr != (&u8)(usize(0)) && ret == addr));
    return ret;
}

inline fn pages_unmap(addr: &u8, size: usize) {
    const r = system.munmap(addr, size);
    if (r == MAP_FAILED) {
        // var buf: [STRERROR_BUF]u8 = "error";
        // #if HAVE_THREADS != 0
        //         strerror_r(errno, buf, sizeof(buf));
        // #endif
        %%_malloc_message(_getprogname(), ": (malloc) Error in munmap(): ", "error", "\n");
        if (opt_abort) {
            %%abort();
        }
    }
}

fn chunk_alloc_mmap(size: usize) -> ?&u8 {
    // Ideally, there would be a way to specify alignment to mmap() (like
    // NetBSD has), but in the absence of such a feature, we have to work
    // hard to efficiently create aligned mappings.  The reliable, but
    // expensive method is to create a mapping that is over-sized, then
    // trim the excess.  However, that always results in at least one call
    // to pages_unmap().
    //
    // A more optimistic approach is to try mapping precisely the right
    // amount, then try to append another mapping if alignment is off.  In
    // practice, this works out well as long as the application is not
    // interleaving mappings via direct mmap() calls.  If we do run into a
    // situation where there is an interleaved mapping and we are unable to
    // extend an unaligned mapping, our best option is to momentarily
    // revert to the reliable-but-expensive method.  This will tend to
    // leave a gap in the memory map that is too small to cause later
    // problems for the optimistic method.

    var ret = pages_map((&u8)(usize(0)), size) ?? return null;
    // if (ret == null) return (null);

    var offset = CHUNK_ADDR2OFFSET(ret);
    if (offset != 0) {
        // Try to extend chunk boundary.
        if (var r ?= pages_map((&u8)(usize(ret) + size), chunksize - offset)) {
            pages_unmap(r, chunksize - offset);
            ret = (&u8)(usize(ret) + (chunksize - offset));
        } else {
            //if (pages_map((&u8)(usize(ret) + size), chunksize - offset) == (&u8)(usize(0))) {
            // Extension failed.  Clean up, then revert to the
            // reliable-but-expensive method.
            pages_unmap(ret, size);

            // Beware size_t wrap-around.
            if (size + chunksize <= size) {
                return null;
            }

            ret = pages_map((&u8)(usize(0)), size + chunksize) ?? return null;
            // if (ret == null) {
            //     return (null);
            // }

            // Clean up unneeded leading/trailing space.
            offset = CHUNK_ADDR2OFFSET(ret);
            if (offset != 0) {
                // Leading space.
                pages_unmap(ret, chunksize - offset);

                ret = (&u8)(usize(ret) + (chunksize - offset));

                // Trailing space.
                pages_unmap((&u8)(usize(ret) + size), offset);
            } else {
                // Trailing space only.
                pages_unmap((&u8)(usize(ret) + size), chunksize);
            }
        // } else {
        //     // Clean up unneeded leading space.
        //     pages_unmap(ret, chunksize - offset);
        //     ret = (&u8)(usize(ret) + (chunksize - offset));
        }
    }

    return ret;
}

fn chunk_alloc(size: usize, zero: bool) -> ?&u8 {
    var ret: ?&u8 = null;

    assert(size != 0);
    assert((size & chunksize_mask) == 0);

    {
        ret = chunk_alloc_mmap(size) ?? goto RETURN;
        if (usize(ret) != usize(0)) {
             goto RETURN;
        }
    }

    // All strategies for allocation failed.
    ret = null;
 RETURN:
    // #ifdef MALLOC_STATS
    if (MALLOC_STATS) {
        if (usize(ret) != 0) {
            stats_chunks.nchunks += (size / chunksize);
            stats_chunks.curchunks += (size / chunksize);
        }
        if (stats_chunks.curchunks > stats_chunks.highchunks) {
            stats_chunks.highchunks = stats_chunks.curchunks;
        }
    }
    //#endif

    if (var rret ?= ret) {
        assert(CHUNK_ADDR2BASE(rret) == rret);
    }
    return ret;
}

fn chunk_dealloc_mmap(chunk: &u8, size: usize) {
    pages_unmap(chunk, size);
}

fn chunk_dealloc(chunk: &u8, size: usize) {
    assert(usize(chunk) != usize(0));
    assert(size != 0);
    assert(CHUNK_ADDR2BASE(chunk) == chunk);
    assert((size & chunksize_mask) == 0);

    //#ifdef MALLOC_STATS
    if (MALLOC_STATS) {
        stats_chunks.curchunks -= (size / chunksize);
    }
    //#endif

    chunk_dealloc_mmap(chunk, size);
}

//******************************************************************************
// End chunk management functions.
//******************************************************************************
// Begin arena.
//******************************************************************************
// Choose an arena based on a per-thread value (fast-path code, calls
// slow-path code if necessary).
inline fn choose_arena() -> ?&arena_t {
    var ret: ?&arena_t = null;

    // We can only use TLS if this is a PIC library, since for the static
    // library version, libc's malloc is used by TLS allocation, which
    // introduces a bootstrapping issue.
    //#ifndef NO_TLS
    if (! NO_TLS) {
        if (__isthreaded == false) {
            // Avoid the overhead of TLS for single-threaded operation.
            return (arenas[0]);
        }

        if (usize(arenas_map) != usize(0)) {
            ret = arenas_map;
        } else {
            if (var rret ?= choose_arena_hard()) {
                ret = rret;
            } else {
                //
            }
            assert(usize(ret) != usize(0));
        }
        //#else
    } else {
        //#if HAVE_THREADS != 0
        if (HAVE_THREADS) {
            if (__isthreaded && narenas > 1) {
                //unsigned long ind;

                // Hash pthread_self() to one of the arenas.  There is a prime
                // number of arenas, so this has a reasonable chance of
                // working.  Even so, the hashing can be easily thwarted by
                // inconvenient pthread_self() values.  Without specific
                // knowledge of how pthread_self() calculates values, we can't
                // easily do much better than this.
                var ind = usize(pthread_self()) % narenas;

                // Optimistially assume that arenas[ind] has been initialized.
                // At worst, we find out that some other thread has already
                // done so, after acquiring the lock in preparation.  Note that
                // this lazy locking also has the effect of lazily forcing
                // cache coherency; without the lock acquisition, there's no
                // guarantee that modification of arenas[ind] by another thread
                // would be seen on this CPU for an arbitrary amount of time.
                //
                // In general, this approach to modifying a synchronized value
                // isn't a good idea, but in this case we only ever modify the
                // value once, so things work out well.
                var rret = arenas[ind];
                if (usize(rret) != usize(0)) {
                    ret = rret;
                } else {
                    // Avoid races with another thread that may have already
                    // initialized arenas[ind].
                    malloc_spin_lock(&arenas_lock);
                    rret = arenas[ind];
                    if (usize(rret) != usize(0)) {
                        ret = rret;
                    } else {
                        ret = arenas_extend(ind);
                    }
                    malloc_spin_unlock(&arenas_lock);
                }
            } else {
                //#endif
                ret = arenas[0];
            }
            //#endif
        } else {
            ret = arenas[0];
        }
    }
    //assert(ret != null);
    assert(usize(ret) != usize(0));
    return ret;
}

// #ifndef NO_TLS
// Choose an arena based on a per-thread value (slow-path code only, called
// only by choose_arena()).
fn choose_arena_hard() -> ?&arena_t {
    var ret: &arena_t = undefined;

    assert(__isthreaded);

    // #ifdef MALLOC_BALANCE
    //* Seed the PRNG used for arena load balancing. */
    // SPRN(balance, (uint32_t)(uintptr_t)(pthread_self()));
    // #endif

    if (narenas > 1) {
        // #ifdef MALLOC_BALANCE
        if (MALLOC_BALANCE) {
            //unsigned ind;

            var ind = usize(0); // PRN(balance, narenas_2pow);
            ret = arenas[ind];
            if (usize(ret) == usize(0)) {
                malloc_spin_lock(&arenas_lock);
                ret = arenas[ind];
                if (usize(ret) == usize(0)) {
                    ret = arenas_extend(ind);
                }
                malloc_spin_unlock(&arenas_lock);
            }
            // #else
        } else {
            malloc_spin_lock(&arenas_lock);
            ret = arenas[next_arena];
            if (usize(ret) == usize(0)) {
                ret = arenas_extend(next_arena);
            }
            next_arena = (next_arena + 1) % narenas;
            malloc_spin_unlock(&arenas_lock);
            // #endif
        }
    } else {
        ret = arenas[0];
    }

    arenas_map = ret;

    return ret;
}
// #endif

//static inline int
fn arena_chunk_comp(a: &arena_chunk_t, b: &arena_chunk_t) -> isize {
    const a_chunk = usize(a);
    const b_chunk = usize(b);

    assert(usize(a) != 0);
    assert(usize(b) != 0);

    return (isize(a_chunk > b_chunk) - isize(a_chunk < b_chunk));
}

// Wrap red-black tree macros in functions.
// rb_wrap(static, arena_chunk_tree_dirty_, arena_chunk_tree_t, arena_chunk_t, link_dirty, arena_chunk_comp)

//static inline int
fn arena_run_comp(a: &arena_chunk_map_t, b: &arena_chunk_map_t) -> isize {
    const a_mapelm = usize(a);
    const b_mapelm = usize(b);

    assert(usize(a) != 0);
    assert(usize(b) != 0);

    return (isize(a_mapelm > b_mapelm) - isize(a_mapelm < b_mapelm));
}

//* Wrap red-black tree macros in functions. */
// rb_wrap(static, arena_run_tree_, arena_run_tree_t, arena_chunk_map_t, link, arena_run_comp)

fn arena_avail_comp(a: &arena_chunk_map_t, b: &arena_chunk_map_t) -> isize {
    const a_size = a.bits & ~pagesize_mask;
    const b_size = b.bits & ~pagesize_mask;

    var ret = isize(a_size > b_size) - isize(a_size < b_size);
    if (ret == 0) {
        var a_mapelm = usize(0);
        if ((a.bits & CHUNK_MAP_KEY) == 0) {
            a_mapelm = usize(a);
        } else {
            // Treat keys as though they are lower than anything else.
            a_mapelm = 0;
        }
        const b_mapelm = usize(b);

        ret = isize(a_mapelm > b_mapelm) - isize(a_mapelm < b_mapelm);
    }

    return ret;
}

//* Wrap red-black tree macros in functions. */
// rb_wrap(static, arena_avail_tree_, arena_avail_tree_t, arena_chunk_map_t, link, arena_avail_comp)

var arent_avail_tree: arena_avail_tree_t = zeroes;

inline fn arena_run_reg_alloc(run: &arena_run_t, bin: &arena_bin_t) -> ?&u8 {
    var ret: ?&u8 = null;
    var regind = usize(0);

    if (MALLOC_DEBUG) {
        assert(run.magic == ARENA_RUN_MAGIC);
    }
    assert(run.regs_minelm < bin.regs_mask_nelms);

    // Move the first check outside the loop, so that run->regs_minelm
    // can be updated unconditionally, without the possibility of
    // updating it multiple times.
    var i = run.regs_minelm;
    // TODO[#173]
    var mask = *(&(&run.regs_mask)[i]);
    if (mask != 0) {
        // Usable allocation found.
        const bit = ffs(mask) - 1;

        regind = ((i << (SIZEOF_INT_2POW + 3)) + bit);
        assert(regind < bin.nregs);
        ret = (&u8)(usize(run) + bin.reg0_offset + (bin.reg_size * regind));

        // Clear bit.
        mask ^= (1 << bit);
        // TODO[#173] run.regs_mask[i] = mask;
        *(&(&run.regs_mask)[i]) = mask;

        return ret;
    }

    i += 1;
    while (i < bin.regs_mask_nelms; i += 1) {
        // TODO[#173] mask = run.regs_mask[i];
        mask = *(&(&run.regs_mask)[i]);
        if (mask != 0) {
            // Usable allocation found.
            const bit = ffs(mask) - 1;

            regind = ((i << (SIZEOF_INT_2POW + 3)) + bit);
            assert(regind < bin.nregs);
            ret = (&u8)(usize(run) + bin.reg0_offset + (bin.reg_size * regind));

            // Clear bit.
            mask ^= (1 << bit);
            // TODO[#173] run.regs_mask[i] = mask;
            *(&(&run.regs_mask)[i]) = mask;

            // Make a note that nothing before this element
            // contains a free region.
            run.regs_minelm = i; // Low payoff: + (mask == 0);

            return (ret);
        }
    }
    // Not reached.
    assert(true);
    return null;
}

const log2_table = []u8 {
    0, 1, 0, 2, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 4,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7
};

inline fn arena_run_reg_dalloc(run: &arena_run_t, bin: &arena_bin_t, ptr: &u8, size: usize) {
    var regind = usize(0);
    var elm = usize(0);
    var bit = u32(0);

    if (MALLOC_DEBUG) {
        assert(run.magic == ARENA_RUN_MAGIC);
    }

    // Avoid doing division with a variable divisor if possible.
    // Using actual division here can reduce allocator throughput by
    // over 20%!
    var diff = usize(usize(ptr) - usize(run) - bin.reg0_offset);
    if ((size & (size - 1)) == 0) {
        // log2_table allows fast division of a power of two in the
        // [1..128] range.
        //
        // (x / divisor) becomes (x >> log2_table[divisor - 1]).

        if (size <= 128) {
            regind = (diff >> log2_table[size - 1]);
        } else if (size <= 32768) {
            regind = diff >> (8 + log2_table[(size >> 8) - 1]);
        } else {
            regind = diff / size;
        }
    } else if (size < qspace_max) {
        // To divide by a number D that is not a power of two we
        // multiply by (2^21 / D) and then right shift by 21 positions.
        //
        //   X / D
        //
        // becomes
        //
        //   (X * qsize_invs[(D >> QUANTUM_2POW) - 3])
        //       >> SIZE_INV_SHIFT
        //
        // We can omit the first three elements, because we never
        // divide by 0, and QUANTUM and 2*QUANTUM are both powers of
        // two, which are handled above.
// #define SIZE_INV_SHIFT 21
// #define QSIZE_INV(s) (((1 << SIZE_INV_SHIFT) / (s << QUANTUM_2POW)) + 1)
//         static const unsigned qsize_invs[] = {
//             QSIZE_INV(3),
//             QSIZE_INV(4), QSIZE_INV(5), QSIZE_INV(6), QSIZE_INV(7)
// #if (QUANTUM_2POW < 4)
//             ,
//             QSIZE_INV(8), QSIZE_INV(9), QSIZE_INV(10), QSIZE_INV(11),
//             QSIZE_INV(12),QSIZE_INV(13), QSIZE_INV(14), QSIZE_INV(15)
// #endif
//         };
//         assert(QUANTUM * (((sizeof(qsize_invs)) / sizeof(unsigned)) + 3)
//                >= (1 << QSPACE_MAX_2POW_DEFAULT));

//         if (size <= (((sizeof(qsize_invs) / sizeof(unsigned)) + 2) <<
//                      QUANTUM_2POW)) {
//             regind = qsize_invs[(size >> QUANTUM_2POW) - 3] * diff;
//             regind >>= SIZE_INV_SHIFT;
//         } else
//             regind = diff / size;
// #undef QSIZE_INV
//     } else if (size < cspace_max) {
// #define CSIZE_INV(s) (((1 << SIZE_INV_SHIFT) / (s << CACHELINE_2POW)) + 1)
//         static const unsigned csize_invs[] = {
//             CSIZE_INV(3),
//             CSIZE_INV(4), CSIZE_INV(5), CSIZE_INV(6), CSIZE_INV(7)
//         };
//         assert(CACHELINE * (((sizeof(csize_invs)) / sizeof(unsigned)) +
//                             3) >= (1 << CSPACE_MAX_2POW_DEFAULT));

//         if (size <= (((sizeof(csize_invs) / sizeof(unsigned)) + 2) <<
//                      CACHELINE_2POW)) {
//             regind = csize_invs[(size >> CACHELINE_2POW) - 3] *
//                 diff;
//             regind >>= SIZE_INV_SHIFT;
//         } else
//             regind = diff / size;
// #undef CSIZE_INV
//     } else {
// #define SSIZE_INV(s) (((1 << SIZE_INV_SHIFT) / (s << SUBPAGE_2POW)) + 1)
//         static const unsigned ssize_invs[] = {
//             SSIZE_INV(3),
//             SSIZE_INV(4), SSIZE_INV(5), SSIZE_INV(6), SSIZE_INV(7),
//             SSIZE_INV(8), SSIZE_INV(9), SSIZE_INV(10), SSIZE_INV(11),
//             SSIZE_INV(12), SSIZE_INV(13), SSIZE_INV(14), SSIZE_INV(15)
// #if (PAGESIZE_2POW == 13)
//             ,
//             SSIZE_INV(16), SSIZE_INV(17), SSIZE_INV(18), SSIZE_INV(19),
//             SSIZE_INV(20), SSIZE_INV(21), SSIZE_INV(22), SSIZE_INV(23),
//             SSIZE_INV(24), SSIZE_INV(25), SSIZE_INV(26), SSIZE_INV(27),
//             SSIZE_INV(28), SSIZE_INV(29), SSIZE_INV(29), SSIZE_INV(30)
// #endif
//         };
//         assert(SUBPAGE * (((sizeof(ssize_invs)) / sizeof(unsigned)) + 3)
//                >= (1 << PAGESIZE_2POW));

//         if (size < (((sizeof(ssize_invs) / sizeof(unsigned)) + 2) <<
//                     SUBPAGE_2POW)) {
//             regind = ssize_invs[(size >> SUBPAGE_2POW) - 3] * diff;
//             regind >>= SIZE_INV_SHIFT;
//         } else
//             regind = diff / size;
// #undef SSIZE_INV
//     }
// #undef SIZE_INV_SHIFT
    }
    assert(diff == regind * size);
    assert(regind < bin.nregs);

    elm = regind >> (SIZEOF_INT_2POW + 3);
    if (elm < run.regs_minelm) {
        run.regs_minelm = elm;
    }
    bit = u32(regind - (elm << (SIZEOF_INT_2POW + 3)));
    // TODO[#173]
    assert((*(&(&run.regs_mask)[elm]) & (1 << bit)) == 0);
    *(&(&run.regs_mask)[elm]) |= (1 << bit);
}

fn arena_run_split(arena: &arena_t, run: &arena_run_t, size: usize, large: bool, zero: bool) {
    // arena_chunk_t *chunk;
    // size_t old_ndirty, run_ind, total_pages, need_pages, rem_pages, i;

    var chunk = (&arena_chunk_t)(CHUNK_ADDR2BASE((&u8)(run)));
    var old_ndirty = chunk.ndirty;
    const run_ind = ((usize(run) - usize(chunk)) >> pagesize_2pow);
    // TODO[#173] the .map is dynamically sized
    var bits = (&(&chunk.map)[run_ind]).bits;
    // total_pages is zero, it may not have been initialized properly
    var total_pages = ((*(&(&chunk.map)[run_ind].bits) & ~(usize)(pagesize_mask)) >> pagesize_2pow);
    var need_pages = (size >> pagesize_2pow);
    assert(need_pages > 0);
    assert(need_pages <= total_pages);
    var rem_pages = total_pages - need_pages;

    arena.runs_avail.remove(&(&chunk.map)[run_ind]);
    // Keep track of trailing unused pages for later use.
    if (rem_pages > 0) {
        %%io.stdout.printf("rem_pages > 0\n");
        // TODO[#173]
        *(&(&chunk.map)[run_ind+need_pages].bits) = (rem_pages << pagesize_2pow)
            | (*(&(&chunk.map)[run_ind + need_pages].bits) & pagesize_mask);
        *(&(&chunk.map)[run_ind+total_pages-1].bits) = (rem_pages << pagesize_2pow)
            | (*(&(&chunk.map)[run_ind+total_pages-1].bits) & pagesize_mask);
        arena.runs_avail.insert((&(&chunk.map)[run_ind+need_pages]));
    }
    // for (i = 0; i < need_pages; i++) {
    {var i = usize(0);
        while (i < need_pages; i += 1) {
            // Zero if necessary.
            //     if (zero) {
            //         if ((chunk->map[run_ind + i].bits & CHUNK_MAP_ZEROED)
            //             == 0) {
            //             memset((void *)((uintptr_t)chunk + ((run_ind
            //                                                  + i) << pagesize_2pow)), 0, pagesize);
            //             // CHUNK_MAP_ZEROED is cleared below.
            //         }
            //     }
            // Update dirty page accounting.
            if ((*(&(&chunk.map)[run_ind + i].bits) & CHUNK_MAP_DIRTY) != 0) {
                chunk.ndirty -= 1;
                arena.ndirty -= 1;
                // CHUNK_MAP_DIRTY is cleared below.
            }
            // Initialize the chunk map.
            if (large) {
                *(&(&chunk.map)[run_ind + i].bits) = CHUNK_MAP_LARGE | CHUNK_MAP_ALLOCATED;
            } else {
                *(&(&chunk.map)[run_ind + i].bits) = (usize(run)) | CHUNK_MAP_ALLOCATED;
            }
        }
    }

    // Set the run size only in the first element for large runs.  This is
    // primarily a debugging aid, since the lack of size info for trailing
    // pages only matters if the application tries to operate on an
    // interior pointer.
    if (large) {
        *(&(&chunk.map)[run_ind].bits) |= size;
    }
    // if (chunk->ndirty == 0 && old_ndirty > 0) {
    //     arena_chunk_tree_dirty_remove(&arena.chunks_dirty, chunk);
    // }
}

fn arena_chunk_alloc(arena: &arena_t) -> &arena_chunk_t {
    var chunk: &arena_chunk_t = zeroes;

    if (usize(arena.spare) != usize(0)) {
        chunk = arena.spare;
        arena.spare = (&arena_chunk_t)(usize(0));
    } else {
        //chunk = (&arena_chunk_t)(chunk_alloc(chunksize, true));
        //if (usize(chunk) == usize(0)) {
        //    return (&arena_chunk_t)(usize(0));
        //}
        var cc = chunk_alloc(chunksize, true) ?? return (&arena_chunk_t)(usize(0));
        chunk = (&arena_chunk_t)(cc);
        // #ifdef MALLOC_STATS
        if (MALLOC_STATS) {
            arena.stats.mapped += chunksize;
        }
        // #endif

        chunk.arena = arena;

        // Claim that no pages are in use, since the header is merely
        // overhead.
        chunk.ndirty = 0;

        // Initialize the map to contain one maximal free untouched run.
        var i = usize(0);
        while (i < arena_chunk_header_npages; i += 1) {
            // TODO[#173]: chunk.map[i].bits = 0;
            *(&(&chunk.map)[i].bits) = 0;
            // *m = 0;
        }
        // TODO: chunk.map[i].bits = u32(arena_maxclass) | CHUNK_MAP_ZEROED;
        *(&(&chunk.map)[i].bits) = arena_maxclass | CHUNK_MAP_ZEROED;
        //*m = u32(arena_maxclass) | CHUNK_MAP_ZEROED;
        // BUG fixed: missing i += 1;
        i += 1;
        while (i < chunk_npages - 1; i += 1) {
            // chunk.map[i].bits = CHUNK_MAP_ZEROED;
            *(&(&chunk.map)[i].bits) = CHUNK_MAP_ZEROED;
        }
        // chunk.map[chunk_npages-1].bits = u32(arena_maxclass) | CHUNK_MAP_ZEROED;
        *(&(&chunk.map)[chunk_npages - 1].bits) = arena_maxclass | CHUNK_MAP_ZEROED;
    }

    // Insert the run into the runs_avail tree.
    // arena_avail_tree_insert(&arena.runs_avail, &chunk.map[arena_chunk_header_npages]);
    // TODO: arena.runs_avail.insert(&chunk.map[arena_chunk_header_npages]);
    arena.runs_avail.insert(&(&chunk.map)[arena_chunk_header_npages]);
    return chunk;
}

fn arena_chunk_dealloc(arena: &arena_t, chunk: &arena_chunk_t) {
    if (usize(arena.spare) != usize(0)) {
        if (arena.spare.ndirty > 0) {
            //arena_chunk_tree_dirty_remove(&chunk.arena.chunks_dirty, arena.spare);
            chunk.arena.chunks_dirty.remove(arena.spare);
            arena.ndirty -= arena.spare.ndirty;
        }
        chunk_dealloc((&u8)(arena.spare), chunksize);
        // #ifdef MALLOC_STATS
        if (MALLOC_STATS) {
            arena.stats.mapped -= chunksize;
        }
        //#endif
    }

    // Remove run from runs_avail, regardless of whether this
    // chunk will be cached, so that the arena does not use it.
    // Dirty page flushing only uses the chunks_dirty tree, so
    // leaving this chunk in the chunks_* trees is sufficient for
    // that purpose.
    // arena_avail_tree_remove(&arena.runs_avail, &chunk.map[arena_chunk_header_npages]);
    // TODO: arena.runs_avail.remove(&chunk.map[arena_chunk_header_npages]);
    arena.runs_avail.remove(&(&chunk.map)[arena_chunk_header_npages]);
    arena.spare = chunk;
}

fn arena_run_alloc(arena: &arena_t, size: usize, large: bool, zero: bool) -> ?&arena_run_t {
    //arena_chunk_t *chunk;
    //arena_run_t *run;
    //arena_chunk_map_t *mapelm, key;
    var run: &arena_run_t = undefined;
    var key: arena_chunk_map_t = undefined;

    assert(size <= arena_maxclass);
    assert((size & pagesize_mask) == 0);

    // Search the arena's chunks for the lowest best fit.
    key.bits = size | CHUNK_MAP_KEY;
    //var mapelm = arena_avail_tree_nsearch(&arena.runs_avail, &key);
    if (var mapelm ?= arena.runs_avail.nsearch(&key)) {
        var run_chunk = (&arena_chunk_t)(CHUNK_ADDR2BASE((&u8)(mapelm)));
        var pageind = (usize(mapelm) - usize(&run_chunk.map)) / @sizeOf(arena_chunk_map_t);

        run = (&arena_run_t)(usize(run_chunk) + (pageind << pagesize_2pow));
        arena_run_split(arena, run, size, large, zero);
        return run;
    }

    // No usable runs.  Create a new chunk from which to allocate the
    // run.
    var chunk = arena_chunk_alloc(arena);
    if (usize(chunk) == usize(0)) {
        return null;
    }
    run = (&arena_run_t)(usize(chunk) + (arena_chunk_header_npages << pagesize_2pow));
    // Update page map.
    arena_run_split(arena, run, size, large, zero);
    return run;
}

fn arena_purge(arena: &arena_t) {
    //#ifdef MALLOC_DEBUG
    // if (MALLOC_DEBUG) {
    //     var ndirty = usize(0);

    //     rb_foreach_begin(arena_chunk_t, link_dirty, &arena.chunks_dirty, chunk) {
    //         ndirty += chunk.ndirty;
    //     } rb_foreach_end(arena_chunk_t, link_dirty, &arena.chunks_dirty, chunk)
    //           assert(ndirty == arena.ndirty);
    //     //#endif
    // }
    assert(arena.ndirty > opt_dirty_max);

    //#ifdef MALLOC_STATS
    if (MALLOC_STATS) {
        arena.stats.npurge += 1;
    }
    //#endif

    // Iterate downward through chunks until enough dirty memory
    // has been purged.  Terminate as soon as possible in order to
    // minimize the number of system calls, even if a chunk has
    // only been partially purged.
    while (arena.ndirty > (opt_dirty_max >> 1)) {
        //var chunk = arena_chunk_tree_dirty_last(&arena.chunks_dirty);
        var cchunk = arena.chunks_dirty.last();
        assert(usize(cchunk) != usize(0));
        var i = chunk_npages - 1;
        if (var chunk ?= cchunk) {
            while (chunk.ndirty > 0; i -= 1) {
                assert(i >= arena_chunk_header_npages);
                // TODO[#173]
                if ((*(&(&chunk.map)[i].bits) & CHUNK_MAP_DIRTY) != 0) {
                    *(&(&chunk.map)[i].bits) ^= CHUNK_MAP_DIRTY;
                    //* Find adjacent dirty run(s). */
                    var npages = usize(1);
                    while ((i > arena_chunk_header_npages) && ((*(&(&chunk.map)[i - 1].bits) & CHUNK_MAP_DIRTY) != 0); npages += 1) {
                        i -= 1;
                        *(&(&chunk.map)[i].bits) ^= CHUNK_MAP_DIRTY;
                    }
                    chunk.ndirty -= npages;
                    arena.ndirty -= npages;

                    // madvise((void *)((uintptr_t)chunk + (i << pagesize_2pow)), (npages << pagesize_2pow),
                    //         MADV_DONTNEED);
                    //#ifdef MALLOC_STATS
                    if (MALLOC_STATS) {
                        arena.stats.nmadvise += 1;
                        arena.stats.purged += npages;
                    }
                    //#endif
                    if (arena.ndirty <= (opt_dirty_max >> 1)) {
                        break;
                    }
                }
            }

            if (chunk.ndirty == 0) {
                //arena_chunk_tree_dirty_remove(&arena.chunks_dirty, chunk);
                arena.chunks_dirty.remove(chunk);
            }
        } else {
            %%abort();
        }
    }
}

// static void
// arena_run_dalloc(arena_t *arena, arena_run_t *run, bool dirty) {
fn arena_run_dalloc(arena: &arena_t, run: &arena_run_t, dirty: bool) {
    //     arena_chunk_t *chunk;
    //     size_t size, run_ind, run_pages;
    //     chunk = (arena_chunk_t *)CHUNK_ADDR2BASE(run);
    //     run_ind = (size_t)(((uintptr_t)run - (uintptr_t)chunk)
    //                        >> pagesize_2pow);
    //     assert(run_ind >= arena_chunk_header_npages);
    //     assert(run_ind < chunk_npages);
    //     if ((chunk->map[run_ind].bits & CHUNK_MAP_LARGE) != 0) {
    //         size = chunk->map[run_ind].bits & ~pagesize_mask;
    //     } else {
    //         size = run->bin->run_size;
    //     }
    //     run_pages = (size >> pagesize_2pow);
    //     // Mark pages as unallocated in the chunk map.
    //     if (dirty) {
    //         size_t i;
    //         for (i = 0; i < run_pages; i++) {
    //             assert((chunk->map[run_ind + i].bits & CHUNK_MAP_DIRTY)
    //                    == 0);
    //             chunk->map[run_ind + i].bits = CHUNK_MAP_DIRTY;
    //         }
    //         if (chunk->ndirty == 0) {
    //             arena_chunk_tree_dirty_insert(&arena->chunks_dirty,
    //                                           chunk);
    //         }
    //         chunk->ndirty += run_pages;
    //         arena->ndirty += run_pages;
    //     } else {
    //         size_t i;
    //         for (i = 0; i < run_pages; i++) {
    //             chunk->map[run_ind + i].bits &= ~(CHUNK_MAP_LARGE |
    //                                               CHUNK_MAP_ALLOCATED);
    //         }
    //     }
    //     chunk->map[run_ind].bits = size | (chunk->map[run_ind].bits &
    //                                        pagesize_mask);
    //     chunk->map[run_ind+run_pages-1].bits = size |
    //         (chunk->map[run_ind+run_pages-1].bits & pagesize_mask);
    //     //* Try to coalesce forward. */
    //     if (run_ind + run_pages < chunk_npages &&
    //         (chunk->map[run_ind+run_pages].bits & CHUNK_MAP_ALLOCATED) == 0) {
    //         size_t nrun_size = chunk->map[run_ind+run_pages].bits &
    //             ~pagesize_mask;
    //         // Remove successor from runs_avail; the coalesced run
    //         // is inserted later.
    //         arena_avail_tree_remove(&arena->runs_avail,
    //                                 &chunk->map[run_ind+run_pages]);
    //         size += nrun_size;
    //         run_pages = size >> pagesize_2pow;
    //         assert((chunk->map[run_ind+run_pages-1].bits & ~pagesize_mask)
    //                == nrun_size);
    //         chunk->map[run_ind].bits = size | (chunk->map[run_ind].bits &
    //                                            pagesize_mask);
    //         chunk->map[run_ind+run_pages-1].bits = size |
    //             (chunk->map[run_ind+run_pages-1].bits & pagesize_mask);
    //     }
    //     // Try to coalesce backward.
    //     if (run_ind > arena_chunk_header_npages && (chunk->map[run_ind-1].bits &
    //                                                 CHUNK_MAP_ALLOCATED) == 0) {
    //         size_t prun_size = chunk->map[run_ind-1].bits & ~pagesize_mask;
    //         run_ind -= prun_size >> pagesize_2pow;
    //         // Remove predecessor from runs_avail; the coalesced run is
    //         // inserted later.
    //         arena_avail_tree_remove(&arena->runs_avail,
    //                                 &chunk->map[run_ind]);
    //         size += prun_size;
    //         run_pages = size >> pagesize_2pow;
    //         assert((chunk->map[run_ind].bits & ~pagesize_mask) ==
    //                prun_size);
    //         chunk->map[run_ind].bits = size | (chunk->map[run_ind].bits &
    //                                            pagesize_mask);
    //         chunk->map[run_ind+run_pages-1].bits = size |
    //             (chunk->map[run_ind+run_pages-1].bits & pagesize_mask);
    //     }
    //     // Insert into runs_avail, now that coalescing is complete.
    //     arena_avail_tree_insert(&arena->runs_avail, &chunk->map[run_ind]);
    //     // Deallocate chunk if it is now completely unused.
    //     if ((chunk->map[arena_chunk_header_npages].bits & (~pagesize_mask |
    //                                                        CHUNK_MAP_ALLOCATED)) == arena_maxclass)
    //         arena_chunk_dealloc(arena, chunk);
    //     // Enforce opt_dirty_max.
    //     if (arena->ndirty > opt_dirty_max)
    //         arena_purge(arena);
}

fn arena_run_trim_head(arena: &arena_t, chunk: &arena_chunk_t, run: &arena_run_t, oldsize: usize, newsize: usize) {
    const pageind = (usize(run) - usize(chunk)) >> pagesize_2pow;
    const head_npages = (oldsize - newsize) >> pagesize_2pow;
    assert(oldsize > newsize);
    // Update the chunk map so that arena_run_dalloc() can treat
    // the leading run as separately allocated.
    // TODO[#173] chunk.map[pageind].bits = u32(oldsize - newsize) | CHUNK_MAP_LARGE | CHUNK_MAP_ALLOCATED;
    // TODO[#173] chunk.map[pageind + head_npages].bits = u32(newsize) | CHUNK_MAP_LARGE | CHUNK_MAP_ALLOCATED;
    *(&(&chunk.map)[pageind].bits) = (oldsize - newsize) | CHUNK_MAP_LARGE | CHUNK_MAP_ALLOCATED;
    *(&(&chunk.map)[pageind + head_npages].bits) = (newsize) | CHUNK_MAP_LARGE | CHUNK_MAP_ALLOCATED;
    arena_run_dalloc(arena, run, false);
}

fn arena_run_trim_tail(arena: &arena_t, chunk: &arena_chunk_t, run: &arena_run_t, oldsize: usize, newsize: usize, dirty: bool) {
    const pageind = (usize(run) - usize(chunk)) >> pagesize_2pow;
    const npages = newsize >> pagesize_2pow;
    assert(oldsize > newsize);
    // Update the chunk map so that arena_run_dalloc() can treat the
    // trailing run as separately allocated.
    // TODO[#173] chunk.map[pageind].bits = u32(newsize) | CHUNK_MAP_LARGE | CHUNK_MAP_ALLOCATED;
    // TODO[#173] chunk.map[pageind+npages].bits = u32(oldsize - newsize) | CHUNK_MAP_LARGE | CHUNK_MAP_ALLOCATED;
    *(&(&chunk.map)[pageind].bits) = (newsize) | CHUNK_MAP_LARGE | CHUNK_MAP_ALLOCATED;
    *(&(&chunk.map)[pageind+npages].bits) = (oldsize - newsize) | CHUNK_MAP_LARGE | CHUNK_MAP_ALLOCATED;
    arena_run_dalloc(arena, (&arena_run_t)(usize(run) + newsize), dirty);
}

fn arena_bin_nonfull_run_get(arena: &arena_t, bin: &arena_bin_t) -> ?&arena_run_t {
    //     arena_chunk_map_t *mapelm;
    // var run: ?&arena_run_t = null;
    //     unsigned i, remainder;
    // Look for a usable run.
    var mapelm = bin.runs.first();
    if (usize(mapelm) != usize(0)) {
        // run is guaranteed to have available space.
        //         arena_run_tree_remove(&bin->runs, mapelm);
        if (var mlm ?= mapelm) {
            var run = (&arena_run_t)(mlm.bits & ~pagesize_mask);
            // #ifdef MALLOC_STATS
            if (MALLOC_STATS) {
                bin.stats.reruns += 1;
            }
            // #endif
            return run;
        }
    }
    // No existing runs have any space available.
    // Allocate a new run.
    var run = arena_run_alloc(arena, bin.run_size, false, false) ?? return null;
    //     if (run == null)
    //         return (null);
    // Initialize run internals.
    run.bin = bin;
    { var i = usize(0);
        while (i < bin.regs_mask_nelms - 1; i += 1) {
            // TODO[#173] run.regs_mask[i] = @maxValue(u32);
            *(&(&run.regs_mask)[i]) = @maxValue(u32);
        }
        const remainder = bin.nregs & ((1 << (SIZEOF_INT_2POW + 3)) - 1);
        if (remainder == 0) {
            *(&(&run.regs_mask)[i]) = @maxValue(u32);
        } else {
            *(&(&run.regs_mask)[i]) = u32((@maxValue(u32)) >> ((1 << (SIZEOF_INT_2POW + 3)) - remainder));
        }
    }
    //     for (i = 0; i < bin->regs_mask_nelms - 1; i++)
    //         run->regs_mask[i] = UINT_MAX;
    //     if (remainder == 0)
    //         run->regs_mask[i] = UINT_MAX;
    //     else {
    //         // The last element has spare bits that need to be unset.
    //         run->regs_mask[i] = (UINT_MAX >> ((1 << (SIZEOF_INT_2POW + 3))
    //                                           - remainder));
    //     }
    run.regs_minelm = 0;
    run.nfree = bin.nregs;
    // #ifdef MALLOC_DEBUG
    if (MALLOC_DEBUG) {
        run.magic = ARENA_RUN_MAGIC;
    }
    // #endif
    // #ifdef MALLOC_STATS
    if (MALLOC_STATS) {
        bin.stats.nruns += 1;
        bin.stats.curruns += 1;
        if (bin.stats.curruns > bin.stats.highruns) {
            bin.stats.highruns = bin.stats.curruns;
        }
    }
    // #endif
    return (run);
}

/// bin->runcur must have space available before this function is called.
// static inline void *
// arena_bin_malloc_easy(arena_t *arena, arena_bin_t *bin, arena_run_t *run) {
inline fn arena_bin_malloc_easy(arena: &arena_t, bin: &arena_bin_t, run: &arena_run_t) -> ?&u8 {
    assert(run.magic == ARENA_RUN_MAGIC);
    assert(run.nfree > 0);
    var ret = arena_run_reg_alloc(run, bin);
    assert(usize(ret) != usize(0));
    run.nfree -= 1;
    return ret;
}

/// Re-fill bin->runcur, then call arena_bin_malloc_easy().
// static void *
fn arena_bin_malloc_hard(arena: &arena_t, bin: &arena_bin_t) -> ?&u8 {
    bin.runcur = arena_bin_nonfull_run_get(arena, bin) ?? return null;
    // if (usize(bin.runcur) == usize(0)) {
    //     return null;
    // }
    assert(bin.runcur.magic == ARENA_RUN_MAGIC);
    assert(bin.runcur.nfree > 0);

    return arena_bin_malloc_easy(arena, bin, bin.runcur);
}

// Calculate bin->run_size such that it meets the following constraints:
//
//   *) bin->run_size >= min_run_size
//   *) bin->run_size <= arena_maxclass
//   *) bin->run_size <= RUN_MAX_SMALL
//   *) run header overhead <= RUN_MAX_OVRHD (or header overhead relaxed).
//
// bin->nregs, bin->regs_mask_nelms, and bin->reg0_offset are
// also calculated here, since these settings are all interdependent.
// static size_t
// arena_bin_run_size_calc(arena_bin_t *bin, size_t min_run_size) {
fn arena_bin_run_size_calc(bin: &arena_bin_t, min_run_size: usize) -> usize {
    //     size_t try_run_size, good_run_size;
    //     unsigned good_nregs, good_mask_nelms, good_reg0_offset;
    //     unsigned try_nregs, try_mask_nelms, try_reg0_offset;
    var good_run_size = usize(0);
    var good_nregs = usize(0);
    var good_mask_nelms = usize(0);
    var good_reg0_offset = usize(0);
    var try_run_size = usize(0);
    var try_nregs = usize(0);
    var try_mask_nelms = usize(0);
    var try_reg0_offset = usize(0);
    assert(min_run_size >= pagesize);
    assert(min_run_size <= arena_maxclass);
    assert(min_run_size <= RUN_MAX_SMALL);
    // Calculate known-valid settings before entering the run_size
    // expansion loop, so that the first part of the loop always copies
    // valid settings.
    //
    // The do..while loop iteratively reduces the number of regions until
    // the run header and the regions no longer overlap.  A closed formula
    // would be quite messy, since there is an interdependency between the
    // header's mask length and the number of regions.
    try_run_size = min_run_size;
    try_nregs = ((try_run_size - @sizeOf(arena_run_t)) / bin.reg_size) + 1; // Counter-act try_nregs-- in loop.
    // do {
    //     try_nregs--;
    //     try_mask_nelms = (try_nregs >> (SIZEOF_INT_2POW + 3)) +
    //         ((try_nregs & ((1 << (SIZEOF_INT_2POW + 3)) - 1)) ? 1 : 0);
    //     try_reg0_offset = try_run_size - (try_nregs * bin->reg_size);
    // } while (sizeof(arena_run_t) + (sizeof(unsigned) * (try_mask_nelms - 1))
    //          > try_reg0_offset);
    while (true) {
        try_nregs -= 1;
        try_mask_nelms = (try_nregs >> (SIZEOF_INT_2POW + 3)) +
            (if ((try_nregs & ((1 << (SIZEOF_INT_2POW + 3)) - 1)) != 0)  usize(1) else usize(0));
        try_reg0_offset = try_run_size - (try_nregs * bin.reg_size);
        if (@sizeOf(arena_run_t) + (@sizeOf(usize) * (try_mask_nelms - 1)) <= try_reg0_offset) break;
    }
    // run_size expansion loop.
    //         do {
    //             // Copy valid settings before trying more aggressive settings.
    //             good_run_size = try_run_size;
    //             good_nregs = try_nregs;
    //             good_mask_nelms = try_mask_nelms;
    //             good_reg0_offset = try_reg0_offset;
    //             // Try more aggressive settings.
    //             try_run_size += pagesize;
    //             try_nregs = ((try_run_size - sizeof(arena_run_t)) /
    //                          bin->reg_size) + 1; // Counter-act try_nregs-- in loop.
    //                 do {
    //                     try_nregs--;
    //                     try_mask_nelms = (try_nregs >> (SIZEOF_INT_2POW + 3)) +
    //                         ((try_nregs & ((1 << (SIZEOF_INT_2POW + 3)) - 1)) ?
    //                          1 : 0);
    //                     try_reg0_offset = try_run_size - (try_nregs *
    //                                                       bin->reg_size);
    //                 } while (sizeof(arena_run_t) + (sizeof(unsigned) *
    //                                                 (try_mask_nelms - 1)) > try_reg0_offset);
    //         } while (try_run_size <= arena_maxclass && try_run_size <= RUN_MAX_SMALL
    //                  && RUN_MAX_OVRHD * (bin->reg_size << 3) > RUN_MAX_OVRHD_RELAX
    //                  && (try_reg0_offset << RUN_BFP) > RUN_MAX_OVRHD * try_run_size);
    while (true) {
        // Copy valid settings before trying more aggressive settings.
        good_run_size = try_run_size;
        good_nregs = try_nregs;
        good_mask_nelms = try_mask_nelms;
        good_reg0_offset = try_reg0_offset;

        // Try more aggressive settings.
        try_run_size += pagesize;
        try_nregs = ((try_run_size - @sizeOf(arena_run_t)) / bin.reg_size) + 1; // Counter-act try_nregs-- in loop.
        //                 do {
        //                     try_nregs--;
        //                     try_mask_nelms = (try_nregs >> (SIZEOF_INT_2POW + 3)) +
        //                         ((try_nregs & ((1 << (SIZEOF_INT_2POW + 3)) - 1)) ?
        //                          1 : 0);
        //                     try_reg0_offset = try_run_size - (try_nregs *
        //                                                       bin->reg_size);
        //                 } while (sizeof(arena_run_t) + (sizeof(unsigned) *
        //                                                 (try_mask_nelms - 1)) > try_reg0_offset);
        while (true) {
            try_nregs -= 1;
            try_mask_nelms = (try_nregs >> (SIZEOF_INT_2POW + 3)) +
                if ((try_nregs & ((1 << (SIZEOF_INT_2POW + 3)) - 1)) != 0) usize(1) else usize(0);
            if (@sizeOf(arena_run_t) + (@sizeOf(usize) * (try_mask_nelms - 1)) <= try_reg0_offset) break;
        }
        if (try_run_size > arena_maxclass || try_run_size > RUN_MAX_SMALL
            || RUN_MAX_OVRHD * (bin.reg_size << 3) <= RUN_MAX_OVRHD_RELAX
            || (try_reg0_offset << RUN_BFP) <= RUN_MAX_OVRHD * try_run_size) {
            break;
        }
    }
    // assert(sizeof(arena_run_t) + (sizeof(unsigned) * (good_mask_nelms - 1))
    //        <= good_reg0_offset);
    assert((good_mask_nelms << (SIZEOF_INT_2POW + 3)) >= good_nregs);
    // Copy final settings.
    bin.run_size = good_run_size;
    bin.nregs = u32(good_nregs);
    bin.regs_mask_nelms = u32(good_mask_nelms);
    bin.reg0_offset = u32(good_reg0_offset);

    return good_run_size;
}

// #ifdef MALLOC_BALANCE
inline fn arena_lock_balance(arena: &arena_t) {
    if (MALLOC_BALANCE) {
        //     unsigned contention;
        var contention = malloc_spin_lock(&arena.lock);
        if (narenas > 1) {
            // Calculate the exponentially averaged contention for this
            // arena.  Due to integer math always rounding down, this
            // value decays somewhat faster than normal.
            arena.contention = u32((u64(arena.contention) * u64((1 << BALANCE_ALPHA_INV_2POW)-1))
                                + (u64(contention) >> BALANCE_ALPHA_INV_2POW));
            if (arena.contention >= opt_balance_threshold) {
                arena_lock_balance_hard(arena);
            }
        }
    }
}
// #endif

// static void
// arena_lock_balance_hard(arena_t *arena) {
fn arena_lock_balance_hard(arena: &arena_t) {
    // uint32_t ind;
    arena.contention = 0;
    if (MALLOC_STATS) {
        arena.stats.nbalance += 1;
    }
    var ind = usize(0); // TODO: PRN(balance, narenas_2pow);
    if (usize(arenas[ind]) != usize(0)) {
        arenas_map = arenas[ind];
    } else {
        malloc_spin_lock(&arenas_lock);
        if (usize(arenas[ind]) != usize(0)) {
            arenas_map = arenas[ind];
        } else {
            arenas_map = arenas_extend(ind);
        }
        malloc_spin_unlock(&arenas_lock);
    }
}
// #endif


inline fn arena_malloc_small(arena: &arena_t, size: usize, zero: bool) -> ?&u8 {
    var ret: ?&u8 = null;
    const binind = size2bin[size];
    assert(binind < nbins);
    // TODOL var bin = &arena.bins[binind];
    var bin = &(&arena.bins)[binind];
    const lsize = bin.reg_size;
    if (MALLOC_BALANCE) {
        arena_lock_balance(arena);
    } else {
        malloc_spin_lock(&arena.lock);
    }
    var run = bin.runcur;
    //     if ((run = bin->runcur) != null && run->nfree > 0)
    //         ret = arena_bin_malloc_easy(arena, bin, run);
    //     else
    //         ret = arena_bin_malloc_hard(arena, bin);
    if (usize(run) != usize(0) && run.nfree > 0) {
        ret = arena_bin_malloc_easy(arena, bin, run);
    } else {
        ret = arena_bin_malloc_hard(arena, bin);
    }
    if (usize(ret) == usize(0)) {
        malloc_spin_unlock(&arena.lock);
        return (null);
    }
    if (var r ?= ret) {
        // #ifdef MALLOC_STATS
        if (MALLOC_STATS) {
            bin.stats.nrequests += 1;
            arena.stats.nmalloc_small += 1;
            arena.stats.allocated_small += size;
        }
        // #endif
        malloc_spin_unlock(&arena.lock);
        if (zero == false) {
            if (opt_junk) {
                @memset(r, 0xa5, size);
            } else if (opt_zero) {
                @memset(r, 0, size);
            }
        } else {
            @memset(r, 0, size);
        }
    }

    return ret;
}

fn arena_malloc_large(arena: &arena_t, size: usize, zero: bool) -> &u8 {
    var lsize = PAGE_CEILING(size);
    if (MALLOC_BALANCE) {
        arena_lock_balance(arena);
    } else {
        malloc_spin_lock(&arena.lock);
    }
    if (var r ?= arena_run_alloc(arena, size, true, zero)) {
        var ret = r;
        // #ifdef MALLOC_STATS
        if (MALLOC_STATS) {
            arena.stats.nmalloc_large += 1;
            arena.stats.allocated_large += size;
        }
        // #endif
        malloc_spin_unlock(&arena.lock);
        if (zero == false) {
            if (opt_junk) {
                @memset(ret, 0xa5, size);
            } else if (opt_zero) {
                @memset(ret, 0, size);
            }
        }
        return (&u8)(ret);
    } else {
        malloc_spin_unlock(&arena.lock);
        return (&u8)(usize(0)); // TODO use a maybe?
    }
    //@unreachable();
}

inline fn arena_malloc(arena: &arena_t, size: usize, zero: bool) -> ?&u8 {
    assert(usize(arena) != usize(0));
    if (MALLOC_DEBUG) {
        assert(arena.magic == ARENA_MAGIC);
    }
    assert(size != 0);
    assert(QUANTUM_CEILING(size) <= arena_maxclass);
    if (size <= bin_maxclass) {
        return arena_malloc_small(arena, size, zero);
    } else {
        return arena_malloc_large(arena, size, zero);
    }
}

inline fn imalloc(size: usize) -> ?&u8 {
    assert(size != 0);
    if (size <= arena_maxclass) {
        if (var a ?= choose_arena()) {
            return arena_malloc(a, size, false)
        } else {
            return (&u8)(usize(0));
        }
        //return arena_malloc(choose_arena(), size, false);
    } else {
        return huge_malloc(size, false);
    }
}

inline fn icalloc(size: usize) -> ?&u8 {
    assert(size != 0);
    if (size <= arena_maxclass) {
        if (var a ?= choose_arena()) {
            return arena_malloc(a, size, true)
        } else {
            return (&u8)(usize(0));
        }
        //return arena_malloc(choose_arena(), size, true);
    } else {
        return huge_malloc(size, true);
    }
}

/// Only handles large allocations that require more than page alignment.
// static void *
// arena_palloc(arena_t *arena, size_t alignment, size_t size, size_t alloc_size) {
fn arena_palloc(arena: &arena_t, alignment: usize, size: usize, alloc_size: usize) -> ?&u8 {
    var ret: ?&u8 = null;
    //     size_t offset;
    //     arena_chunk_t *chunk;
    //     assert((size & pagesize_mask) == 0);
    //     assert((alignment & pagesize_mask) == 0);
    // #ifdef MALLOC_BALANCE
    //     arena_lock_balance(arena);
    // #else
    //     malloc_spin_lock(&arena->lock);
    // #endif
    //     ret = (void *)arena_run_alloc(arena, alloc_size, true, false);
    //     if (ret == null) {
    //         malloc_spin_unlock(&arena->lock);
    //         return (null);
    //     }
    //     chunk = (arena_chunk_t *)CHUNK_ADDR2BASE(ret);
    //     offset = (uintptr_t)ret & (alignment - 1);
    //     assert((offset & pagesize_mask) == 0);
    //     assert(offset < alloc_size);
    //     if (offset == 0)
    //         arena_run_trim_tail(arena, chunk, ret, alloc_size, size, false);
    //     else {
    //         size_t leadsize, trailsize;
    //         leadsize = alignment - offset;
    //         if (leadsize > 0) {
    //             arena_run_trim_head(arena, chunk, ret, alloc_size,
    //                                 alloc_size - leadsize);
    //             ret = (void *)((uintptr_t)ret + leadsize);
    //         }
    //         trailsize = alloc_size - leadsize - size;
    //         if (trailsize != 0) {
    //             // Trim trailing space.
    //             assert(trailsize < alloc_size);
    //             arena_run_trim_tail(arena, chunk, ret, size + trailsize,
    //                                 size, false);
    //         }
    //     }
    // #ifdef MALLOC_STATS
    //     arena->stats.nmalloc_large++;
    //     arena->stats.allocated_large += size;
    // #endif
    //     malloc_spin_unlock(&arena->lock);
    //     if (opt_junk)
    //         memset(ret, 0xa5, size);
    //     else if (opt_zero)
    //         memset(ret, 0, size);
    return ret;
}

// static inline void *
// ipalloc(size_t alignment, size_t size) {
fn ipalloc(alignment: usize, size: usize) -> ?&u8 {
    var ret: ?&u8 = null;
    // Round size up to the nearest multiple of alignment.
    //
    // This done, we can take advantage of the fact that for each small
    // size class, every object is aligned at the smallest power of two
    // that is non-zero in the base two representation of the size.  For
    // example:
    //
    //   Size |   Base 2 | Minimum alignment
    //   -----+----------+------------------
    //     96 |  1100000 |  32
    //    144 | 10100000 |  32
    //    192 | 11000000 |  64
    //
    // Depending on runtime settings, it is possible that arena_malloc()
    // will further round up to a power of two, but that never causes
    // correctness issues.

    // TODO: Check this
    var ceil_size = (size + (alignment - 1)) & (usize(-isize(alignment)));
    // (ceil_size < size) protects against the combination of maximal
    // alignment and size greater than maximal alignment.
    if (ceil_size < size) {
        // size_t overflow.
        return null;
    }
    if (ceil_size <= pagesize || (alignment <= pagesize && ceil_size <= arena_maxclass)) {
        // ret = arena_malloc(choose_arena(), ceil_size, false);
    } else {
        // size_t run_size;
    // We can't achieve subpage alignment, so round up alignment
    // permanently; it makes later calculations simpler.
    // alignment = PAGE_CEILING(alignment);
    // ceil_size = PAGE_CEILING(size);
    // (ceil_size < size) protects against very large sizes within
    // pagesize of SIZE_T_MAX.
    //
    // (ceil_size + alignment < ceil_size) protects against the
    // combination of maximal alignment and ceil_size large enough
    // to cause overflow.  This is similar to the first overflow
    // check above, but it needs to be repeated due to the new
    // ceil_size value, which may now be *equal* to maximal
    // alignment, whereas before we only detected overflow if the
    // original size was *greater* than maximal alignment.
    // if (ceil_size < size || ceil_size + alignment < ceil_size) {
    //     //* size_t overflow. */
    //     return (null);
    // }
    // // Calculate the size of the over-size run that arena_palloc()
    // // would need to allocate in order to guarantee the alignment.
    // if (ceil_size >= alignment)
    //     run_size = ceil_size + alignment - pagesize;
    // else {
    //     // It is possible that (alignment << 1) will cause
    //     // overflow, but it doesn't matter because we also
    //     // subtract pagesize, which in the case of overflow
    //     // leaves us with a very large run_size.  That causes
    //     // the first conditional below to fail, which means
    //     // that the bogus run_size value never gets used for
    //     // anything important.
    //     run_size = (alignment << 1) - pagesize;
    // }
    // if (run_size <= arena_maxclass) {
    //     ret = arena_palloc(choose_arena(), alignment, ceil_size,
    //                        run_size);
    // } else if (alignment <= chunksize)
    //     ret = huge_malloc(ceil_size, false);
    // else
    //     ret = huge_palloc(alignment, ceil_size);
    }
    assert((usize(ret) & (alignment - 1)) == 0);
    return ret;
}

/// Return the size of the allocation pointed to by ptr.
fn arena_salloc(ptr: &u8) -> usize {
    var ret = usize(0);

    assert(usize(ptr) != usize(0));
    assert(CHUNK_ADDR2BASE(ptr) != ptr);
    const chunk = (&arena_chunk_t)(CHUNK_ADDR2BASE(ptr));
    const pageind = ((usize(ptr) - usize(chunk)) >> pagesize_2pow);
    // TODO[#173]
    const mapbits = *(&(&chunk.map)[pageind].bits);
    assert((mapbits & CHUNK_MAP_ALLOCATED) != 0);

    if ((mapbits & CHUNK_MAP_LARGE) == 0) {
        const run = (&arena_run_t)(mapbits & ~pagesize_mask);
        assert(run.magic == ARENA_RUN_MAGIC);
        ret = run.bin.reg_size;
    } else {
        ret = mapbits & ~pagesize_mask;
        assert(ret != 0);
    }

    return ret;
}

inline fn ptrsEqual(a: var, b: var) -> bool {
    return usize(a) == usize(b)
}

inline fn isalloc(ptr: &u8) -> usize {
    var ret = usize(0);

    assert(usize(ptr) != usize(0));
    const chunk = (&arena_chunk_t)(CHUNK_ADDR2BASE(ptr));
    if (! ptrsEqual(chunk, ptr)) {
        // Region.
        assert(chunk.arena.magic == ARENA_MAGIC);
        ret = arena_salloc(ptr);
    } else {
        // extent_node_t *node, key;
        // Chunk (huge allocation).
        malloc_mutex_lock(&huge_mtx);
        // Extract from tree of huge allocations.
        var key: extent_node_t = zeroes;
        key.addr = usize(ptr);
        if (var node ?= huge.search(&key)) {
            ret = node.size;
        } else {
            // assert(node != null);
            %%abort();
        }
        malloc_mutex_unlock(&huge_mtx);
    }

    return ret;
}

// static inline void
// arena_dalloc_small(arena_t *arena, arena_chunk_t *chunk, void *ptr, arena_chunk_map_t *mapelm) {
inline fn arena_dalloc_small(arena: &arena_t, chunk: &arena_chunk_t, ptr: &u8, mapelm: &arena_chunk_map_t) {
    // TODO: This is next for implrmrntation...
    //     arena_run_t *run;
    //     arena_bin_t *bin;
    //     size_t size;
    //     run = (arena_run_t *)(mapelm->bits & ~pagesize_mask);
    //     assert(run->magic == ARENA_RUN_MAGIC);
    //     bin = run->bin;
    //     size = bin->reg_size;
    //     if (opt_junk)
    //         memset(ptr, 0x5a, size);
    //     arena_run_reg_dalloc(run, bin, ptr, size);
    //     run->nfree++;
    //     if (run->nfree == bin->nregs) {
    //         // Deallocate run.
    //         if (run == bin->runcur)
    //             bin->runcur = null;
    //         else if (bin->nregs != 1) {
    //             size_t run_pageind = (((uintptr_t)run -
    //                                    (uintptr_t)chunk)) >> pagesize_2pow;
    //             arena_chunk_map_t *run_mapelm =
    //                 &chunk->map[run_pageind];
    //             // This block's conditional is necessary because if the
    //             // run only contains one region, then it never gets
    //             // inserted into the non-full runs tree.
    //             arena_run_tree_remove(&bin->runs, run_mapelm);
    //         }
    // #ifdef MALLOC_DEBUG
    //         run->magic = 0;
    // #endif
    //         arena_run_dalloc(arena, run, true);
    // #ifdef MALLOC_STATS
    //         bin->stats.curruns--;
    // #endif
    //     } else if (run->nfree == 1 && run != bin->runcur) {
    //         // Make sure that bin->runcur always refers to the lowest
    //         // non-full run, if one exists.
    //         if (bin->runcur == null)
    //             bin->runcur = run;
    //         else if ((uintptr_t)run < (uintptr_t)bin->runcur) {
    //             // Switch runcur.
    //             if (bin->runcur->nfree > 0) {
    //                 arena_chunk_t *runcur_chunk =
    //                     CHUNK_ADDR2BASE(bin->runcur);
    //                 size_t runcur_pageind =
    //                     (((uintptr_t)bin->runcur -
    //                       (uintptr_t)runcur_chunk)) >> pagesize_2pow;
    //                 arena_chunk_map_t *runcur_mapelm =
    //                     &runcur_chunk->map[runcur_pageind];
    //                 // Insert runcur.
    //                     arena_run_tree_insert(&bin->runs,
    //                                           runcur_mapelm);
    //             }
    //             bin->runcur = run;
    //         } else {
    //             size_t run_pageind = (((uintptr_t)run - (uintptr_t)chunk)) >> pagesize_2pow;
    //             arena_chunk_map_t *run_mapelm =
    //                 &chunk->map[run_pageind];
    //             assert(arena_run_tree_search(&bin->runs, run_mapelm) ==
    //                    null);
    //             arena_run_tree_insert(&bin->runs, run_mapelm);
    //         }
    //     }
    // #ifdef MALLOC_STATS
    //     arena->stats.allocated_small -= size;
    //     arena->stats.ndalloc_small++;
    // #endif
}


// static void
// arena_dalloc_large(arena_t *arena, arena_chunk_t *chunk, void *ptr) {
fn arena_dalloc_large(arena: &arena_t, chunk: &arena_chunk_t, ptr: &u8) {
    // Large allocation.
    malloc_spin_lock(&arena.lock);
    // TODO: Translate this to zig in some fashion
    // #ifndef MALLOC_STATS
    //     if (opt_junk)
    // #endif
    //     {
    //         size_t pageind = ((uintptr_t)ptr - (uintptr_t)chunk) >>
    //             pagesize_2pow;
    //         size_t size = chunk->map[pageind].bits & ~pagesize_mask;
    // #ifdef MALLOC_STATS
    //         if (opt_junk)
    // #endif
    //             memset(ptr, 0x5a, size);
    // #ifdef MALLOC_STATS
    //         arena->stats.allocated_large -= size;
    // #endif
    //     }
    // #ifdef MALLOC_STATS
    if (MALLOC_STATS) {
        arena.stats.ndalloc_large += 1;
    }
    // #endif
    arena_run_dalloc(arena, (&arena_run_t)(ptr), true);
    malloc_spin_unlock(&arena.lock);
}

// static inline void
// arena_dalloc(arena_t *arena, arena_chunk_t *chunk, void *ptr) {
inline fn arena_dalloc(arena: &arena_t, chunk: &arena_chunk_t, ptr: &u8) {
    assert(usize(arena) != usize(0));
    assert(arena.magic == ARENA_MAGIC);
    assert(chunk.arena == arena);
    assert(usize(ptr) != usize(0));
    assert(CHUNK_ADDR2BASE(ptr) != ptr);

    const pageind = ((usize(ptr) - usize(chunk)) >> pagesize_2pow);
    // TODO[#173]...
    var mapelm = &(&chunk.map)[pageind];
    // this fails... investigate...
    assert((mapelm.bits & CHUNK_MAP_ALLOCATED) != 0);
    if ((mapelm.bits & CHUNK_MAP_LARGE) == 0) {
        // Small allocation.
        malloc_spin_lock(&arena.lock);
        arena_dalloc_small(arena, chunk, ptr, mapelm);
        malloc_spin_unlock(&arena.lock);
    } else {
        arena_dalloc_large(arena, chunk, ptr);
    }
}

inline fn idalloc(ptr: &u8) {
    assert(usize(ptr) != usize(0));
    var chunk = CHUNK_ADDR2BASE(ptr);
    if (chunk != ptr) {
        var cp = (&arena_chunk_t)(chunk);
        arena_dalloc(cp.arena, cp, ptr);
    } else {
        huge_dalloc(ptr);
    }
}

// static void
fn arena_ralloc_large_shrink(arena: &arena_t, chunk: &arena_chunk_t, ptr: &u8, size: usize, oldsize: usize) {
    assert(size < oldsize);
    // Shrink the run, and make trailing pages available for other
    // allocations.
    if (MALLOC_BALANCE) {
        arena_lock_balance(arena);
    } else {
        malloc_spin_lock(&arena.lock);
    }
    arena_run_trim_tail(arena, chunk, (&arena_run_t)(ptr), oldsize, size, true);
    if (MALLOC_STATS) {
        arena.stats.allocated_large -= oldsize - size;
    }
    malloc_spin_unlock(&arena.lock);
 }

// //static bool
// fn arena_ralloc_large_grow(arena_t *arena, arena_chunk_t *chunk, void *ptr,
//     size_t size, size_t oldsize) -> bool {
//     size_t pageind = ((uintptr_t)ptr - (uintptr_t)chunk) >> pagesize_2pow;
//     size_t npages = oldsize >> pagesize_2pow;
//     assert(oldsize == (chunk->map[pageind].bits & ~pagesize_mask));
//     // Try to extend the run.
//     assert(size > oldsize);
// #ifdef MALLOC_BALANCE
//     arena_lock_balance(arena);
// #else
//     malloc_spin_lock(&arena->lock);
// #endif
//     if (pageind + npages < chunk_npages && (chunk->map[pageind+npages].bits
//                                             & CHUNK_MAP_ALLOCATED) == 0 && (chunk->map[pageind+npages].bits &
//                                                                             ~pagesize_mask) >= size - oldsize) {
//         // The next run is available and sufficiently large.  Split the
//         // following run, then merge the first part with the existing
//         // allocation.
//         arena_run_split(arena, (arena_run_t *)((uintptr_t)chunk +
//                                                ((pageind+npages) << pagesize_2pow)), size - oldsize, true,
//                         false);
//         chunk->map[pageind].bits = size | CHUNK_MAP_LARGE |
//             CHUNK_MAP_ALLOCATED;
//         chunk->map[pageind+npages].bits = CHUNK_MAP_LARGE |
//             CHUNK_MAP_ALLOCATED;
// #ifdef MALLOC_STATS
//         arena->stats.allocated_large += size - oldsize;
// #endif
//         malloc_spin_unlock(&arena->lock);
//         return (false);
//     }
//     malloc_spin_unlock(&arena->lock);
//     return (true);
// }

/// Try to resize a large allocation, in order to avoid copying.  This will
/// always fail if growing an object, and the following run is already in use.
// fn arena_ralloc_large(void *ptr, size_t size, size_t oldsize) -> bool {
//     size_t psize;
//     psize = PAGE_CEILING(size);
//     if (psize == oldsize) {
//         // Same size class.
//         if (opt_junk && size < oldsize) {
//             memset((void *)((uintptr_t)ptr + size), 0x5a, oldsize -
//                    size);
//         }
//         return (false);
//     } else {
//         arena_chunk_t *chunk;
//         arena_t *arena;
//         chunk = (arena_chunk_t *)CHUNK_ADDR2BASE(ptr);
//         arena = chunk->arena;
//         assert(arena->magic == ARENA_MAGIC);
//         if (psize < oldsize) {
//             // Fill before shrinking in order avoid a race.
//             if (opt_junk) {
//                 memset((void *)((uintptr_t)ptr + size), 0x5a,
//                        oldsize - size);
//             }
//             arena_ralloc_large_shrink(arena, chunk, ptr, psize,
//                                       oldsize);
//             return (false);
//         } else {
//             bool ret = arena_ralloc_large_grow(arena, chunk, ptr, psize, oldsize);
//             if (ret == false && opt_zero) {
//                 memset((void *)((uintptr_t)ptr + oldsize), 0, size - oldsize);
//             }
//             return (ret);
//         }
//     }
// }

// static void *
// arena_ralloc(void *ptr, size_t size, size_t oldsize) {
fn arena_ralloc(ptr: &u8, size: usize, oldsize: usize) -> ?&u8 {
    //     void *ret;
    //     size_t copysize;
    //     // Try to avoid moving the allocation.
    //     if (size <= bin_maxclass) {
    //         if (oldsize <= bin_maxclass && size2bin[size] ==
    //             size2bin[oldsize])
    //             goto IN_PLACE;
    //     } else {
    //         if (oldsize > bin_maxclass && oldsize <= arena_maxclass) {
    //             assert(size > bin_maxclass);
    //             if (arena_ralloc_large(ptr, size, oldsize) == false)
    //                 return (ptr);
    //         }
    //     }
    //     // If we get here, then size and oldsize are different enough that
    //     // we need to move the object.  In that case, fall back to
    //     // allocating new space and copying.
    //     ret = arena_malloc(choose_arena(), size, false);
    //     if (ret == null)
    //         return (null);
    //     // Junk/zero-filling were already done by arena_malloc().
    //     copysize = (size < oldsize) ? size : oldsize;
    //     memcpy(ret, ptr, copysize);
    //     idalloc(ptr);
    //     return (ret);
    //  IN_PLACE:
    //     if (opt_junk && size < oldsize)
    //         memset((void *)((uintptr_t)ptr + size), 0x5a, oldsize - size);
    //     else if (opt_zero && size > oldsize)
    //         memset((void *)((uintptr_t)ptr + oldsize), 0, size - oldsize);
    return (ptr);
}

// static inline void *
fn iralloc(ptr: &u8, size: usize) -> ?&u8 {
    // size_t oldsize;
    assert(usize(ptr) != usize(0));
    assert(size != 0);
    var oldsize = isalloc(ptr);
    if (size <= arena_maxclass) {
        return arena_ralloc(ptr, size, oldsize);
    } else {
        return huge_ralloc(ptr, size, oldsize);
    }
}

// // static bool
fn arena_new(arena: &arena_t) -> bool {
    //     unsigned i;
    //     arena_bin_t *bin;
    //     size_t prev_run_size;
    if (malloc_spin_init(&arena.lock)) {
        return true;
    }
    if (MALLOC_STATS) {
        @memset(&arena.stats, 0, @sizeOf(arena_stats_t));
    }
    // Initialize chunks.
    //     arena_chunk_tree_dirty_new(&arena->chunks_dirty);
    arena.chunks_dirty.init();
    arena.spare = (&arena_chunk_t)(usize(0));
    arena.ndirty = 0;
    arena.runs_avail.init();
    //#ifdef MALLOC_BALANCE
    if (MALLOC_BALANCE) {
        arena.contention = 0;
    }
    // #endif
    // Initialize bins.
    var prev_run_size = pagesize;
    var i = usize(0);
    // #ifdef MALLOC_TINY
    //     // (2^n)-spaced tiny bins.
    //     for (; i < ntbins; i++) {
    //         bin = &arena->bins[i];
    //         bin->runcur = null;
    //         arena_run_tree_new(&bin->runs);
    //         bin->reg_size = (1 << (TINY_MIN_2POW + i));
    //         prev_run_size = arena_bin_run_size_calc(bin, prev_run_size);
    // #ifdef MALLOC_STATS
    //         memset(&bin->stats, 0, sizeof(malloc_bin_stats_t));
    // #endif
    //     }
    // #endif
    // Quantum-spaced bins.
    while (i < ntbins + nqbins; i += 1) {
        // TODO: var bin = &arena.bins[i] same for all below
        var bin = &(&arena.bins)[i];
        bin.runcur = (&arena_run_t)(usize(0));
        bin.runs.init();
        bin.reg_size = (i - ntbins + 1) << QUANTUM_2POW;
        // TODO: prev_run_size = arena_bin_run_size_calc(bin, prev_run_size);
        prev_run_size = arena_bin_run_size_calc(bin, prev_run_size);
        if (MALLOC_STATS) {
            @memset(&bin.stats, 0, @sizeOf(malloc_bin_stats_t));
        }
    }
    //     for (; i < ntbins + nqbins; i++) {
    //         bin = &arena->bins[i];
    //         bin->runcur = null;
    //         arena_run_tree_new(&bin->runs);
    //         bin->reg_size = (i - ntbins + 1) << QUANTUM_2POW;
    //         prev_run_size = arena_bin_run_size_calc(bin, prev_run_size);
    // #ifdef MALLOC_STATS
    //         memset(&bin->stats, 0, sizeof(malloc_bin_stats_t));
    // #endif
    //     }

    // Cacheline-spaced bins.
    while (i < ntbins + nqbins + ncbins; i += 1) {
        var bin = &(&arena.bins)[i];
        bin.runcur = (&arena_run_t)(usize(0));
        bin.runs.init();
        bin.reg_size = cspace_min + ((i - (ntbins + nqbins)) << CACHELINE_2POW);
        prev_run_size = arena_bin_run_size_calc(bin, prev_run_size);
        if (MALLOC_STATS) {
            @memset(&bin.stats, 0, @sizeOf(malloc_bin_stats_t));
        }
    }
    //     for (; i < ntbins + nqbins + ncbins; i++) {
    //         bin = &arena->bins[i];
    //         bin->runcur = null;
    //         arena_run_tree_new(&bin->runs);
    //         bin->reg_size = cspace_min + ((i - (ntbins + nqbins)) <<
    //                                       CACHELINE_2POW);
    //         prev_run_size = arena_bin_run_size_calc(bin, prev_run_size);
    // #ifdef MALLOC_STATS
    //         memset(&bin->stats, 0, sizeof(malloc_bin_stats_t));
    // #endif
    //     }

    // Subpage-spaced bins.
    while (i < nbins; i += 1) {
        var bin = &(&arena.bins)[i];
        bin.runcur = (&arena_run_t)(usize(0));
        bin.runs.init();
        bin.reg_size = sspace_min + ((i - (ntbins + nqbins + ncbins)) << SUBPAGE_2POW);
        prev_run_size = arena_bin_run_size_calc(bin, prev_run_size);
        if (MALLOC_STATS) {
            @memset(&bin.stats, 0, @sizeOf(malloc_bin_stats_t));
        }
    }
    //     for (; i < nbins; i++) {
    //         bin = &arena->bins[i];
    //         bin->runcur = null;
    //         arena_run_tree_new(&bin->runs);
    //         bin->reg_size = sspace_min + ((i - (ntbins + nqbins + ncbins))
    //                                       << SUBPAGE_2POW);
    //         prev_run_size = arena_bin_run_size_calc(bin, prev_run_size);
    // #ifdef MALLOC_STATS
    //         memset(&bin->stats, 0, sizeof(malloc_bin_stats_t));
    // #endif
    //     }
    // #ifdef MALLOC_DEBUG
    if (MALLOC_DEBUG) {
        arena.magic = ARENA_MAGIC;
    }
    // #endif
    //     return (false);
    //
    return false;
}

/// Create a new arena and insert it into the arenas array at index ind.
fn arenas_extend(ind: usize) -> &arena_t {
    if (var ret ?= base_alloc(@sizeOf(arena_t) + (@sizeOf(arena_bin_t) * (nbins - 1)))) {
        if (arena_new((&arena_t)(ret)) == false) {
            arenas[ind] = (&arena_t)(ret);
            return (&arena_t)(ret);
        }
    }
    // Only reached if there is an OOM error.
    // OOM here is quite inconvenient to propagate, since dealing with it
    // would require a check for failure in the fast path.  Instead, punt
    // by using arenas[0].  In practice, this is an extremely unlikely
    // failure.
    %%_malloc_message(_getprogname(), ": (malloc) Error initializing arena\n", "", "");
    if (opt_abort) {
        %%abort();
    }
    return arenas[0];
}

// End arena.
//******************************************************************************
// Begin general internal functions.
// static void *
fn huge_malloc(size: usize, zero: bool) -> &u8 {
    // Allocate one or more contiguous chunks for this request.
    var csize = CHUNK_CEILING(size);
    if (csize == 0) {
        // size is large enough to cause size_t wrap-around.
        return (&u8)(usize(0));//null;
    }
    // Allocate an extent node with which to track the chunk.
    if (var node ?= base_node_alloc()) {
        var ret = (&u8)(usize(0));
        if (var r ?= chunk_alloc(csize, zero)) {
            ret = r;
        } else {
            base_node_dealloc(node);
            return (&u8)(usize(0));
        }
        // Insert node into huge.
        node.addr = usize(ret);
        node.size = csize;
        malloc_mutex_lock(&huge_mtx);
        huge.insert(node);
        // #ifdef MALLOC_STATS
        if (MALLOC_STATS) {
            huge_nmalloc += 1;
            huge_allocated += csize;
        }
        // #endif
        malloc_mutex_unlock(&huge_mtx);
        if (zero == false) {
            if (opt_junk) {
                @memset(ret, 0xa5, csize);
            } else if (opt_zero) {
                @memset(ret, 0, csize);
            }
        }
        return ret;
    } else {
        return (&u8)(usize(0));//null;
    }
}

// /// Only handles large allocations that require more than chunk alignment.
// static void *
// huge_palloc(size_t alignment, size_t size) {
//     void *ret;
//     size_t alloc_size, chunk_size, offset;
//     extent_node_t *node;
//     // This allocation requires alignment that is even larger than chunk
//     // alignment.  This means that huge_malloc() isn't good enough.
//     //
//     // Allocate almost twice as many chunks as are demanded by the size or
//     // alignment, in order to assure the alignment can be achieved, then
//     // unmap leading and trailing chunks.
//     assert(alignment >= chunksize);
//     chunk_size = CHUNK_CEILING(size);
//     if (size >= alignment)
//         alloc_size = chunk_size + alignment - chunksize;
//     else
//         alloc_size = (alignment << 1) - chunksize;
//     // Allocate an extent node with which to track the chunk.
//     node = base_node_alloc();
//     if (node == null)
//         return (null);
//     ret = chunk_alloc(alloc_size, false);
//     if (ret == null) {
//         base_node_dealloc(node);
//         return (null);
//     }
//     offset = (uintptr_t)ret & (alignment - 1);
//     assert((offset & chunksize_mask) == 0);
//     assert(offset < alloc_size);
//     if (offset == 0) {
//         // Trim trailing space.
//         chunk_dealloc((void *)((uintptr_t)ret + chunk_size), alloc_size
//                       - chunk_size);
//     } else {
//         size_t trailsize;
//         // Trim leading space.
//         chunk_dealloc(ret, alignment - offset);
//         ret = (void *)((uintptr_t)ret + (alignment - offset));
//         trailsize = alloc_size - (alignment - offset) - chunk_size;
//         if (trailsize != 0) {
//             //* Trim trailing space. */
//             assert(trailsize < alloc_size);
//             chunk_dealloc((void *)((uintptr_t)ret + chunk_size),
//                           trailsize);
//         }
//     }
//     // Insert node into huge.
//     node->addr = ret;
//     node->size = chunk_size;
//     malloc_mutex_lock(&huge_mtx);
//     extent_tree_ad_insert(&huge, node);
// #ifdef MALLOC_STATS
//     huge_nmalloc++;
//     huge_allocated += chunk_size;
// #endif
//     malloc_mutex_unlock(&huge_mtx);
//     if (opt_junk)
//         memset(ret, 0xa5, chunk_size);
//     else if (opt_zero)
//         memset(ret, 0, chunk_size);
//     return (ret);
// }

// static void *
// huge_ralloc(void *ptr, size_t size, size_t oldsize) {
fn huge_ralloc(ptr: &u8, size: usize, oldsize: usize) -> ?&u8 {
    var ret: ?&u8 = null;
    //     size_t copysize;
    //     // Avoid moving the allocation if the size class would not change.
    //     if (oldsize > arena_maxclass &&
    //         CHUNK_CEILING(size) == CHUNK_CEILING(oldsize)) {
    //         if (opt_junk && size < oldsize) {
    //             memset((void *)((uintptr_t)ptr + size), 0x5a, oldsize
    //                    - size);
    //         } else if (opt_zero && size > oldsize) {
    //             memset((void *)((uintptr_t)ptr + oldsize), 0, size
    //                    - oldsize);
    //         }
    //         return (ptr);
    //     }
    //     // If we get here, then size and oldsize are different enough that we
    //     // need to use a different size class.  In that case, fall back to
    //     // allocating new space and copying.
    //     ret = huge_malloc(size, false);
    //     if (ret == null) {
    //         return (null);
    //     }
    //     copysize = (size < oldsize) ? size : oldsize;
    //     memcpy(ret, ptr, copysize);
    //     idalloc(ptr);
    return ret;
}

// static void
// huge_dalloc(void *ptr) {
inline fn huge_dalloc(ptr: &u8) {
    //     extent_node_t *node, key;
    malloc_mutex_lock(&huge_mtx);
    // Extract from tree of huge allocations.
    var key: extent_node_t = zeroes;
    key.addr = usize(ptr);
    if (var node ?= huge.search(&key)) {
        assert(node.addr == usize(ptr));
        //     extent_tree_ad_remove(&huge, node);
        huge.remove(node);
        // #ifdef MALLOC_STATS
        if (MALLOC_STATS) {
            huge_ndalloc += 1;
            huge_allocated -= node.size;
        }
        // #endif
        malloc_mutex_unlock(&huge_mtx);
        // Unmap chunk.
        chunk_dealloc(ptr, node.size);
        // TODO
        base_node_dealloc(node);
    } else {
        // key not found
        %%abort();
    }
}

pub fn abort() -> %void {
    %%io.stderr.printf("An error occured");
}

pub fn _malloc_message(a: []u8, b: []u8, c: []u8, d: []u8) -> %void {
    %%io.stderr.write(a);
    %%io.stderr.write("");
    %%io.stderr.write(b);
    %%io.stderr.write("");
    %%io.stderr.write(c);
    %%io.stderr.write("");
    %%io.stderr.printf(d);
}

fn malloc_print_stats() -> %void {
    if (opt_print_stats) {
        var s: [UMAX2S_BUFSIZE]u8 = zeroes;
        var ss: [UMAX2S_BUFSIZE]u8 = zeroes;
        %%_malloc_message("___ Begin malloc statistics ___\n", "", "", "");
        %%_malloc_message("Assertions ", if (@compileVar("is_release")) "disabled" else "enabled", "\n", "");
        %%_malloc_message("Boolean MALLOC_OPTIONS: ",  if (opt_abort) "A" else "a", "", "");
        %%_malloc_message(if (opt_junk) "J" else "j", "", "", "");
        %%_malloc_message(if (opt_utrace)  "PU" else "Pu",
                          if (opt_sysv) "V" else "v",
                          if (opt_xmalloc) "X" else "x",
                          if (opt_zero) "Z\n" else "z\n");
        %%_malloc_message("CPUs: ", umax2s(ncpus, s), "\n", "");
        %%_malloc_message("Max arenas: ", umax2s(narenas, s), "\n", "");
        // #ifdef MALLOC_BALANCE
        if (MALLOC_BALANCE) {
            %%_malloc_message("Arena balance threshold: ", umax2s(opt_balance_threshold, s), "\n", "");
        } else {
            %%_malloc_message("MALLOC_BALANCE disabled\n", "", "", "");
        }
        // #endif
        %%_malloc_message("Pointer size: ", umax2s(usize(@sizeOf(usize)), s), "\n", "");
        %%_malloc_message("Quantum size: ", umax2s(QUANTUM, s), "\n", "");
        %%_malloc_message("Cacheline size (assumed): ", umax2s(CACHELINE, s), "\n", "");
        // #ifdef MALLOC_TINY
        if (MALLOC_TINY) {
            %%_malloc_message("Tiny 2^n-spaced sizes: [", umax2s((1 <<TINY_MIN_2POW), s), "..", "");
            %%_malloc_message(umax2s((qspace_min >> 1), s), "]\n", "", "");
        } else {
            %%_malloc_message("MALLOC_TINY disabled\n", "", "", "");
        }
        // #endif
        %%_malloc_message("Quantum-spaced sizes: [", umax2s(qspace_min, s), "..", "");
        %%_malloc_message(umax2s(qspace_max, s), "]\n", "", "");
        %%_malloc_message("Cacheline-spaced sizes: [", umax2s(cspace_min, s), "..", "");
        %%_malloc_message(umax2s(cspace_max, s), "]\n", "", "");
        %%_malloc_message("Subpage-spaced sizes: [", umax2s(sspace_min, s), "..", "");
        %%_malloc_message(umax2s(sspace_max, s), "]\n", "", "");
        %%_malloc_message("Max dirty pages per arena: ", umax2s(opt_dirty_max, s), "\n", "");
        %%_malloc_message("Chunk size: ", umax2s(chunksize, s), "", "");
        %%_malloc_message(" (2^", umax2s(opt_chunk_2pow, s), ")\n", "");
        // #ifdef MALLOC_STATS
        if (MALLOC_STATS) {
            var allocated = usize(0);
            var mapped = usize(0);
            var nbalance = usize(0);
            // Calculate and print allocated/mapped stats.
            // arenas.
            {var i = usize(0);
                while (i < narenas; i += 1) {
                    if (usize(arenas[i]) != usize(0)) {
                        malloc_spin_lock(&arenas[i].lock);
                        allocated += arenas[i].stats.allocated_small;
                        allocated += arenas[i].stats.allocated_large;
                        if (MALLOC_BALANCE) {
                            nbalance += arenas[i].stats.nbalance;
                        }
                        malloc_spin_unlock(&arenas[i].lock);
                    }
                }
            }
            // huge/base.
            malloc_mutex_lock(&huge_mtx);
            allocated += huge_allocated;
            mapped = stats_chunks.curchunks * chunksize;
            malloc_mutex_unlock(&huge_mtx);
            malloc_mutex_lock(&base_mtx);
            mapped += base_mapped;
            malloc_mutex_unlock(&base_mtx);
            %%_malloc_message("Allocated: ", umax2s(allocated, s), ", mapped: ", umax2s(mapped, ss));
            // #ifdef MALLOC_BALANCE
            if (MALLOC_BALANCE) {
                %%_malloc_message("\nArena balance reassignments: ", umax2s(nbalance, s), "\n", "");
            }
            // #endif
            // Print chunk stats.
            malloc_mutex_lock(&huge_mtx);
            var chunks_stats = stats_chunks;
            malloc_mutex_unlock(&huge_mtx);
            %%_malloc_message("\nChunks nchunks:", umax2s(chunks_stats.nchunks, s),
                              ", highchunks:", umax2s(chunks_stats.highchunks, ss));
            %%_malloc_message(", curchunks:", umax2s(chunks_stats.curchunks, s), "\n", "");
            // Print chunk stats.
            %%_malloc_message("huge nmalloc:", umax2s(huge_nmalloc, s), ", ndalloc:", umax2s(huge_ndalloc, ss));
            %%_malloc_message(", allocated:", umax2s(huge_allocated, s), "\n", "");
            // Print stats for each arena.
            {var i = usize(0);
                while (i < narenas; i += 1) {
                    var arena = arenas[i];
                    if (usize(arena) != usize(0)) {
                        %%_malloc_message("\narenas[", umax2s(i, s), "]\n", "");
                        malloc_spin_lock(&arena.lock);
                        %%stats_print(arena);
                        malloc_spin_unlock(&arena.lock);
                    }
                }
            }
        }
        %%_malloc_message("--- End malloc statistics ---\n", "", "", "");
    }
}

fn size2bin_validate() {
    if (MALLOC_DEBUG) {
        assert(size2bin[0] == u8(0xff));
        // #  ifdef MALLOC_TINY
        //     // Tiny.
        //     for (; i < (1 << TINY_MIN_2POW); i++) {
        //         size = pow2_ceil(1 << TINY_MIN_2POW);
        //         binind = ffs((int)(size >> (TINY_MIN_2POW + 1)));
        //         assert(size2bin[i] == binind);
        //     }
        //     for (; i < qspace_min; i++) {
        //         size = pow2_ceil(i);
        //         binind = ffs((int)(size >> (TINY_MIN_2POW + 1)));
        //         assert(size2bin[i] == binind);
        //     }
        // #  endif
        // Quantum-spaced.
        var i = usize(1);
        while (i <= qspace_max; i += 1) {
            const size = u8(QUANTUM_CEILING(i));
            const binind = ntbins + (size >> QUANTUM_2POW) - 1;
            assert(size2bin[i] == binind);
        }
        // Cacheline-spaced.
        while (i <= cspace_max; i += 1) {
            const size = CACHELINE_CEILING(i);
            const binind = ntbins + nqbins + ((size - cspace_min) >> CACHELINE_2POW);
            //assert(size2bin[i] == binind);
        }
        // Sub-page.
        while (i <= sspace_max; i += 1) {
            const size = SUBPAGE_CEILING(i);
            const binind = ntbins + nqbins + ncbins + ((size - sspace_min) >> SUBPAGE_2POW);
            //assert(size2bin[i] == binind);
        }
    }
}

// // static bool
fn size2bin_init() -> bool {
    prep_size2bin();
    if (opt_qspace_max_2pow != QSPACE_MAX_2POW_DEFAULT || opt_cspace_max_2pow != CSPACE_MAX_2POW_DEFAULT) {
        return size2bin_init_hard();
    }
    // TODO
    size2bin = const_size2bin;
    //#ifdef MALLOC_DEBUG
    if (MALLOC_DEBUG) {
        assert((size2bin.len * @sizeOf(u8)) == bin_maxclass + 1);
        size2bin_validate();
    }
    //#endif
    return false;
}

// // static bool
fn size2bin_init_hard() -> bool {
    return false;
}
//     size_t i, size, binind;
//     uint8_t *custom_size2bin;
//     assert(opt_qspace_max_2pow != QSPACE_MAX_2POW_DEFAULT
//            || opt_cspace_max_2pow != CSPACE_MAX_2POW_DEFAULT);
//     custom_size2bin = (uint8_t *)base_alloc(bin_maxclass + 1);
//     if (custom_size2bin == null)
//         return (true);
//     custom_size2bin[0] = 0xff;
//     i = 1;
// #ifdef MALLOC_TINY
//     //* Tiny. */
//     for (; i < (1 << TINY_MIN_2POW); i++) {
//         size = pow2_ceil(1 << TINY_MIN_2POW);
//         binind = ffs((int)(size >> (TINY_MIN_2POW + 1)));
//         custom_size2bin[i] = binind;
//     }
//     for (; i < qspace_min; i++) {
//         size = pow2_ceil(i);
//         binind = ffs((int)(size >> (TINY_MIN_2POW + 1)));
//         custom_size2bin[i] = binind;
//     }
// #endif
//     //* Quantum-spaced. */
//     for (; i <= qspace_max; i++) {
//         size = QUANTUM_CEILING(i);
//         binind = ntbins + (size >> QUANTUM_2POW) - 1;
//         custom_size2bin[i] = binind;
//     }
//     //* Cacheline-spaced. */
//     for (; i <= cspace_max; i++) {
//         size = CACHELINE_CEILING(i);
//         binind = ntbins + nqbins + ((size - cspace_min) >>
//                                     CACHELINE_2POW);
//         custom_size2bin[i] = binind;
//     }
//     //* Sub-page. */
//     for (; i <= sspace_max; i++) {
//         size = SUBPAGE_CEILING(i);
//         binind = ntbins + nqbins + ncbins + ((size - sspace_min) >>
//                                              SUBPAGE_2POW);
//         custom_size2bin[i] = binind;
//     }
//     size2bin = custom_size2bin;
// #ifdef MALLOC_DEBUG
//     size2bin_validate();
// #endif
//     return (false);
// }

// FreeBSD's pthreads implementation calls malloc(3), so the malloc
// implementation has to take pains to avoid infinite recursion during
// initialization.
inline fn malloc_init() -> bool {

    if (malloc_initialized == false)
        return malloc_init_hard();

    return false;
}

fn malloc_init_hard() -> bool {
    //unsigned i;
    //int linklen;
    //char buf[PATH_MAX + 1];
    //const char *opts;

    malloc_mutex_lock(&init_lock);
    if (malloc_initialized) {
        // Another thread initialized the allocator before this one
        // acquired init_lock.
        malloc_mutex_unlock(&init_lock);
        return false;
    }

    // Get number of CPUs.
    ncpus = getNumCpus(HAVE_THREADS);

    // Get page size.
    pagesize = getPageSize(HAVE_THREADS) %% return true;

    // We assume that pagesize is a power of 2 when calculating
    // pagesize_mask and pagesize_2pow.
    // Why doesn't this fail, in disageement with gdb 
    assert(@sizeOf(@typeOf(pagesize_mask)) == @sizeOf(@typeOf(pagesize)));
    assert(((pagesize - 1) & pagesize) == 0);
    pagesize_mask = usize(pagesize - 1);
    pagesize_2pow = ffs(pagesize) - 1;

    //     for (i = 1; i < 3; i++) {
    //         unsigned j;

    //         //* Get runtime configuration. */
    //         switch (i) {
    //         case 0:
    //             if ((linklen = readlink("/etc/malloc.conf", buf,
    //                                     sizeof(buf) - 1)) != -1) {
    //                 // Use the contents of the "/etc/malloc.conf" symbolic
    //                 // link's name.
    //                 buf[linklen] = '\x00';
    //                 opts = buf;
    //             } else {
    //                 //* No configuration specified. */
    //                 buf[0] = '\x00';
    //                 opts = buf;
    //             }
    //             break;
    //         case 1:
    //             if (issetugid() == 0 && (opts =
    //                                      getenv("MALLOC_OPTIONS")) != null) {
    //                 // Do nothing; opts is already initialized to
    //                 // the value of the MALLOC_OPTIONS environment
    //                 // variable.
    //             } else {
    //                 // No configuration specified.
    //                 buf[0] = '\x00';
    //                 opts = buf;
    //             }
    //             break;
    //         case 2:
    //             if (_malloc_options != null) {
    //                 // Use options that were compiled into the
    //                 // program.
    //                 opts = _malloc_options;
    //             } else {
    //                 // No configuration specified.
    //                 buf[0] = '\x00';
    //                 opts = buf;
    //             }
    //             break;
    //         default:
    //             // NOTREACHED
    //             assert(false);
    //         }
    //         for (j = 0; opts[j] != '\x00'; j++) {
    //             unsigned k, nreps;
    //             bool nseen;
    //             //* Parse repetition count, if any. */
    //             for (nreps = 0, nseen = false;; j++, nseen = true) {
    //                 switch (opts[j]) {
    //                 case '0': case '1': case '2': case '3':
    //                 case '4': case '5': case '6': case '7':
    //                 case '8': case '9':
    //                     nreps *= 10;
    //                     nreps += opts[j] - '0';
    //                     break;
    //                 default:
    //                     goto MALLOC_OUT;
    //                 }
    //             }
    //         MALLOC_OUT:
    //             if (nseen == false)
    //                 nreps = 1;
    //             for (k = 0; k < nreps; k++) {
    //                 switch (opts[j]) {
    //                 case 'a':
    //                     opt_abort = false;
    //                     break;
    //                 case 'A':
    //                     opt_abort = true;
    //                     break;
    //                 case 'b':
    // #ifdef MALLOC_BALANCE
    //                     opt_balance_threshold >>= 1;
    // #endif
    //                     break;
    //                 case 'B':
    // #ifdef MALLOC_BALANCE
    //                     if (opt_balance_threshold == 0)
    //                         opt_balance_threshold = 1;
    //                     else if ((opt_balance_threshold << 1)
    //                              > opt_balance_threshold)
    //                         opt_balance_threshold <<= 1;
    // #endif
    //                     break;
    //                 case 'c':
    //                     if (opt_cspace_max_2pow - 1 >
    //                         opt_qspace_max_2pow &&
    //                         opt_cspace_max_2pow >
    //                         CACHELINE_2POW)
    //                         opt_cspace_max_2pow--;
    //                     break;
    //                 case 'C':
    //                     if (opt_cspace_max_2pow < pagesize_2pow
    //                         - 1)
    //                         opt_cspace_max_2pow++;
    //                     break;
    //                 case 'd':
    //                     break;
    //                 case 'D':
    //                     break;
    //                 case 'f':
    //                     opt_dirty_max >>= 1;
    //                     break;
    //                 case 'F':
    //                     if (opt_dirty_max == 0)
    //                         opt_dirty_max = 1;
    //                     else if ((opt_dirty_max << 1) != 0)
    //                         opt_dirty_max <<= 1;
    //                     break;
    //                 case 'j':
    //                     opt_junk = false;
    //                     break;
    //                 case 'J':
    //                     opt_junk = true;
    //                     break;
    //                 case 'k':
    //                     // Chunks always require at least one header page,
    //                     // so chunks can never be smaller than two pages.
    //                     if (opt_chunk_2pow > pagesize_2pow + 1)
    //                         opt_chunk_2pow--;
    //                     break;
    //                 case 'K':
    //                     if (opt_chunk_2pow + 1 < (sizeof(size_t) << 3)) {
    //                         opt_chunk_2pow++;
    //                     }
    //                     break;
    //                 case 'm':
    //                     break;
    //                 case 'M':
    //                     opt_mmap = true;
    //                     break;
    //                 case 'n':
    //                     opt_narenas_lshift -= 1;
    //                     break;
    //                 case 'N':
    //                     opt_narenas_lshift += 1;
    //                     break;
    //                 case 'p':
    //                     opt_print_stats = false;
    //                     break;
    //                 case 'P':
    //                     opt_print_stats = true;
    //                     break;
    //                 case 'q':
    //                     if (opt_qspace_max_2pow > QUANTUM_2POW) {
    //                         opt_qspace_max_2pow--;
    //                     }
    //                     break;
    //                 case 'Q':
    //                     if (opt_qspace_max_2pow + 1 < opt_cspace_max_2pow) {
    //                         opt_qspace_max_2pow++;
    //                     }
    //                     break;
    //                 case 'u':
    //                     opt_utrace = false;
    //                     break;
    //                 case 'U':
    //                     opt_utrace = true;
    //                     break;
    //                 case 'v':
    //                     opt_sysv = false;
    //                     break;
    //                 case 'V':
    //                     opt_sysv = true;
    //                     break;
    //                 case 'x':
    //                     opt_xmalloc = false;
    //                     break;
    //                 case 'X':
    //                     opt_xmalloc = true;
    //                     break;
    //                 case 'z':
    //                     opt_zero = false;
    //                     break;
    //                 case 'Z':
    //                     opt_zero = true;
    //                     break;
    //                 default: {
    //                     char cbuf[2];
    //                     cbuf[0] = opts[j];
    //                     cbuf[1] = '\x00';
    //                     _malloc_message(_getprogname(),
    //                                     ": (malloc) Unsupported character "
    //                                     "in malloc options: '", cbuf,
    //                                     "'\n");
    //                 }
    //                 }
    //             }
    //         }
    //     }
    opt_mmap = true;

    // Take care to call atexit() only once.
    if (opt_print_stats) {
        // Print statistics at exit.
        // atexit(malloc_print_stats);
    }
    //#if HAVE_THREADS != 0
    //* Register fork handlers.
    if (HAVE_THREADS) {
        // pthread_atfork(_malloc_prefork, _malloc_postfork, _malloc_postfork);
    }
    //#endif

    // Set variables according to the value of opt_[qc]space_max_2pow.
    qspace_max = (1 << opt_qspace_max_2pow);
    cspace_min = CACHELINE_CEILING(qspace_max);
    if (cspace_min == qspace_max) {
        cspace_min += CACHELINE;
    }
    cspace_max = (1 << opt_cspace_max_2pow);
    sspace_min = SUBPAGE_CEILING(cspace_max);
    if (sspace_min == cspace_max) {
        sspace_min += SUBPAGE;
    }
    assert(sspace_min < pagesize);
    sspace_max = pagesize - SUBPAGE;

    //#ifdef MALLOC_TINY
    if (MALLOC_TINY) {
        assert(QUANTUM_2POW >= TINY_MIN_2POW);
    }
    //#endif
    assert(ntbins <= QUANTUM_2POW);
    nqbins = qspace_max >> QUANTUM_2POW;
    ncbins = ((cspace_max - cspace_min) >> CACHELINE_2POW) + 1;
    nsbins = ((sspace_max - sspace_min) >> SUBPAGE_2POW) + 1;
    nbins = ntbins + nqbins + ncbins + nsbins;

    if (size2bin_init()) {
        malloc_mutex_unlock(&init_lock);
        return (true);
    }

    // Set variables according to the value of opt_chunk_2pow.
    chunksize = (1 << opt_chunk_2pow);
    chunksize_mask = chunksize - 1;
    chunk_npages = (chunksize >> pagesize_2pow);
    {
        // Compute the header size such that it is large enough to
        // contain the page map.
        var header_size = @sizeOf(arena_chunk_t) + (@sizeOf(arena_chunk_map_t) * (chunk_npages - 1));
        arena_chunk_header_npages = (header_size >> pagesize_2pow) + usize((header_size & pagesize_mask) != 0);
    }
    arena_maxclass = chunksize - (arena_chunk_header_npages << pagesize_2pow);

    // UTRACE(0, 0, 0);

    //#ifdef MALLOC_STATS
    if (MALLOC_STATS) {
        @memset(&stats_chunks, 0, @sizeOf(chunk_stats_t));
    }
    //#endif

    // Various sanity checks that regard configuration.
    assert(chunksize >= pagesize);

    // Initialize chunks data.
    if (malloc_mutex_init(&huge_mtx)) {
        malloc_mutex_unlock(&init_lock);
        return (true);
    }
    //extent_tree_ad_new(&huge);
    huge.init();
    //#ifdef MALLOC_STATS
    if (MALLOC_STATS) {
        huge_nmalloc = 0;
        huge_ndalloc = 0;
        huge_allocated = 0;
    }
    //#endif

    // Initialize base allocation data structures.
    //#ifdef MALLOC_STATS
    if (MALLOC_STATS) {
        base_mapped = 0;
    }
    //#endif
    base_nodes = null;
    if (malloc_mutex_init(&base_mtx)) {
        malloc_mutex_unlock(&init_lock);
        return true;
    }

    if (ncpus > 1) {
        // For SMP systems, create twice as many arenas as there
        // are CPUs by default.
        opt_narenas_lshift += 1;
    }

    // Determine how many arenas to use.
    narenas = ncpus;
    if (opt_narenas_lshift > 0) {
        if ((narenas << opt_narenas_lshift) > narenas) {
            narenas <<= opt_narenas_lshift;
        }
        // Make sure not to exceed the limits of what base_alloc() can
        // handle.
        if (narenas * @sizeOf(&arena_t) > chunksize) {
            narenas = chunksize / @sizeOf(&arena_t);
        }
    }
    // else if (opt_narenas_lshift < 0) {
    //     if ((narenas >> -opt_narenas_lshift) < narenas) {
    //         narenas >>= -opt_narenas_lshift;
    //     }
    //     // Make sure there is at least one arena.
    //     if (narenas == 0) {
    //         narenas = 1;
    //     }
    // }
    // #ifdef MALLOC_BALANCE
    if (MALLOC_BALANCE) {
        assert(narenas != 0);
        // for (narenas_2pow = 0; (narenas >> (narenas_2pow + 1)) != 0; narenas_2pow++);
    }
    // #endif

    // #ifdef NO_TLS
    if (narenas > 1) {
        const primes = []usize {1, 3, 5, 7, 11, 13, 17, 19,
                                23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83,
                                89, 97, 101, 103, 107, 109, 113, 127, 131, 137, 139, 149,
                                151, 157, 163, 167, 173, 179, 181, 191, 193, 197, 199, 211,
                                223, 227, 229, 233, 239, 241, 251, 257, 263};
        // unsigned nprimes, parenas;

        // Pick a prime number of hash arenas that is more than narenas
        // so that direct hashing of pthread_self() pointers tends to
        // spread allocations evenly among the arenas.
        assert((narenas & 1) == 0); // narenas must be even.
        var nprimes = ((@sizeOf(usize) * primes.len) >> SIZEOF_INT_2POW);
        var parenas = primes[nprimes - 1]; // In case not enough primes.
        var i = usize(1);
        while (i < nprimes; i += 1) {
            if (primes[i] > narenas) {
                parenas = primes[i];
                break;
            }
        }
        narenas = parenas;
    }
    // #endif

    //#ifndef NO_TLS
    //#  ifndef MALLOC_BALANCE
    if (! NO_TLS && ! MALLOC_BALANCE) {
        next_arena = 0;
    }
    //#  endif
    //#endif

    // Allocate and initialize arenas.
    // @sizeOf(arena_t or &arena_t)
    if (var a ?= base_alloc(@sizeOf(arena_t) * narenas)) {
        arenas = (&&arena_t)(a);
    } else {
        malloc_mutex_unlock(&init_lock);
        if (@compileVar("is_test") == true) {
            %%io.stdout.printf("arena prob 2")
        }
        return true;
    }
    // Zero the array.  In practice, this should always be pre-zeroed,
    // since it was just mmap()ed, but let's be sure.
    @memset(arenas, 0, @sizeOf(&arena_t) * narenas);

    // Initialize one arena here.  The rest are lazily created
    // in choose_arena_hard().
    arenas_extend(0);
    if (usize(arenas[0]) == usize(0)) {
        malloc_mutex_unlock(&init_lock);
        if (@compileVar("is_test") == true) {
            %%io.stdout.printf("arena prob 2")
        }
        return true;
    }
    //#ifndef NO_TLS
    if (! NO_TLS) {
        // Assign the initial arena to the initial thread, in
        // order to avoid spurious creation of an extra arena if
        // the application switches to threaded mode.
        arenas_map = arenas[0];
        //#endif
    }
    // Seed here for the initial thread, since
    // choose_arena_hard() is only called for other threads.
    // The seed value doesn't really matter.
    // #ifdef MALLOC_BALANCE
    //             SPRN(balance, 42);
    // #endif
    malloc_spin_init(&arenas_lock);

    malloc_initialized = true;
    malloc_mutex_unlock(&init_lock);
    if (!@compileVar("is_release")) {
        %%io.stdout.printf("malloc initialized\n");
    }
    //#if HAVE_THREADS != 0
    if (! HAVE_THREADS) {
        return false;
    } else {
        return false;
    }
    //#endif
}

//***************************************
// End general internal functions.
//***************************************
// Begin malloc(3)-compatible functions.
//***************************************
pub fn je_malloc(size: usize) -> ?&u8 {
    var ret: ?&u8 = null;
    var lsize = size;

    if (malloc_init()) {
        goto RETURN;
    }

    if (lsize == 0) {
        if (opt_sysv == false) {
            lsize = 1;
        } else {
            goto RETURN;
        }
    }

    ret = imalloc(size);

 RETURN:
    if (var rr ?= ret) {
    } else {
        if (opt_xmalloc) {
            %%_malloc_message(_getprogname(), ": (malloc) Error in malloc(): out of memory\n", "", "");
            %%abort();
        }
        var err = error.ErrNoMem;
    }

    //UTRACE(0, size, ret);
    return ret;
}

/// NOTE: this function assumes that any checks on alignment have
/// already been done and that malloc_init() has been called
fn memalign_base(memptr: &&u8, alignment: usize, size: usize, caller: []u8) -> isize {
    var ret = isize(0);
    if (var result ?= ipalloc(alignment, size)) {
        *memptr = result;
    } else {
        if (opt_xmalloc) {
            %%_malloc_message(_getprogname(), ": (malloc) Error in ", caller, "(): out of memory\n");
            %%abort();
        }
        ret = -1;
    }

    // UTRACE(0, size, result);
    return ret;
}

pub fn je_posix_memalign(memptr: &&u8, alignment: usize , size: usize) -> isize {
    var ret = isize(0);
    if (malloc_init()) {
        ret = -1;
    } else {
        // Make sure that alignment is a large enough power of 2.
        if (((alignment - 1) & alignment) != 0
            || alignment < @sizeOf(usize)) {
            if (opt_xmalloc) {
                %%_malloc_message(_getprogname(), ": (malloc) Error in posix_memalign(): ",
                                  "invalid alignment\n", "");
                %%abort();
            }
            ret = -1;
            goto RETURN;
        }
        ret = memalign_base(memptr, alignment, size, "je_posix_memalign"); // __func__
    }
 RETURN:
    return (ret);
}

// void*
// FUNC_NAME(je_memalign)(size_t boundary, size_t size)
pub fn je_memalign(boundary: usize, size: usize) -> ?&u8 {
    if (malloc_init()) {
        return null;            // MISRA: single return, ;)
    }
    // Use normal malloc
    if (boundary <= QUANTUM) {
        return je_malloc(size);
    }
    // Round up to nearest power of 2 if not power of 2
    var alignment = boundary;
    if ((alignment & (alignment - 1)) != 0) {
        alignment = next_power_of_two(alignment);
    }
    var result: &u8 = undefined;
    memalign_base(&result, alignment, size, "je_memalign"); // __func__

    return result;
}

pub fn je_valloc(size: usize) -> ?&u8 {
    if (malloc_init()) {
        return null;
    } else {
        var result: &u8 = undefined;
        memalign_base(&result, pagesize, size, "je_valloc"); // __func__
        return result;
    }
}

// void *
// FUNC_NAME(je_calloc)(size_t num, size_t size)
pub fn je_calloc(num: usize, size: usize) -> ?&u8 {
    // void *ret;
    var ret: ?&u8 = null;
    var num_size = usize(0);
    if (malloc_init()) {
        num_size = 0;
        goto RETURN;
     }
    num_size = num * size;
    if (num_size == 0) {
        if ((opt_sysv == false) && ((num == 0) || (size == 0))) {
            num_size = 1;
        } else {
            goto RETURN;
        }
        // Try to avoid division here.  We know that it isn't possible to
        // overflow during multiplication if neither operand uses any of
        // the most significant half of the bits in a size_t.
    } else if (((num | size) & (SIZE_T_MAX << (@sizeOf(usize) << 2))) != 0
               && (num_size / size != num)) {
        // size_t overflow.
        goto RETURN;
    }
    ret = icalloc(num_size);
 RETURN:
    if (var r ?= ret) {
    } else {
        if (opt_xmalloc) {
            %%_malloc_message(_getprogname(), ": (malloc) Error in calloc(): out of memory\n",
                              "", "");
            %%abort();
        }
        // errno = ENOMEM;
    }
    // UTRACE(0, num_size, ret);
    return ret;
}

// void *
// FUNC_NAME(je_realloc)(void *ptr, size_t size)
pub fn je_realloc(ptr: &u8, size: usize) -> ?&u8 {
    var ret: ?&u8 = null;
    var lsize = size;
    if (size == 0) {
        if (opt_sysv == false) {
            lsize = 1;
        } else {
            if (usize(ptr) != usize(0)) {
                idalloc(ptr);
            }
            goto RETURN;
        }
    }
    if (usize(ptr) != usize(0)) {
        assert(malloc_initialized);
        ret = iralloc(ptr, lsize);
        //    if (ret == null) {
    //                 if (opt_xmalloc) {
    //                         _malloc_message(_getprogname(),
    //                             ": (malloc) Error in realloc(): out of "
    //                             "memory\n", "", "");
    //                         abort();
    //                 }
    //                 errno = ENOMEM;
    //         }
    } else {
    //         if (malloc_init())
    //                 ret = null;
    //         else
    //                 ret = imalloc(size);
    //         if (ret == null) {
    //                 if (opt_xmalloc) {
    //                         _malloc_message(_getprogname(),
    //                             ": (malloc) Error in realloc(): out of "
    //                             "memory\n", "", "");
    //                         abort();
    //                 }
    //                 errno = ENOMEM;
    //         }
    }
    RETURN:
    // UTRACE(ptr, lsize, ret);
    return ret;
}

pub fn je_free(ptr: &u8) {
    // UTRACE(ptr, 0, 0)
    if (usize(ptr) != usize(0)) {
        assert(malloc_initialized);
        idalloc(ptr);
    }
}

// TODO: Can we have weak linkage in zig?

// #if !defined(HEAP_TRACKING)
// void* malloc(size_t size) __attribute__ ((weak, alias ("je_malloc")));
// void  free(void* ptr) __attribute__ ((weak, alias ("je_free")));
// void* realloc(void* ptr, size_t size) __attribute__ ((weak, alias ("je_realloc")));
// void* memalign(size_t boundary, size_t size) __attribute__ ((weak, alias ("je_memalign")));
// void* valloc(size_t size) __attribute__ ((weak, alias ("je_valloc")));
// void* calloc(size_t num, size_t size) __attribute__ ((weak, alias("je_calloc")));
// int   posix_memalign(void **memptr, size_t alignment, size_t size) __attribute__ ((weak, alias("je_posix_memalign")));
// #endif

//******************************************************************************
// End malloc(3)-compatible functions.
//******************************************************************************
// Begin non-standard functions.
//******************************************************************************
fn malloc_usable_size(ptr: &u8) -> usize {
    assert(usize(ptr) != usize(0));
    return isalloc(ptr);
}

//******************************************************************************
// End non-standard functions.
//******************************************************************************
// Begin library-private functions.
//******************************************************************************
// Begin thread cache.
//******************************************************************************
// We provide an unpublished interface in order to receive notifications from
// the pthreads library whenever a thread exits.  This allows us to clean up
// thread caches.
// void
pub fn _malloc_thread_cleanup() {
    // nothing here...
}

// The following functions are used by threading libraries for protection of
// malloc during fork().  These functions are only called if the program is
// running in threaded mode, so there is no need to check whether the program
// is threaded here.

pub fn _malloc_prefork() {
    // Acquire all mutexes in a safe order.
    malloc_spin_lock(&arenas_lock);
    { var i = usize(0);
        while (i < narenas; i += 1) {
            if (usize(arenas[i]) != usize(0)) {
                malloc_spin_lock(&arenas[i].lock);
            }
        }
    }
    malloc_spin_unlock(&arenas_lock);
    malloc_mutex_lock(&base_mtx);
    malloc_mutex_lock(&huge_mtx);
}

pub fn _malloc_postfork() {
    // Release all mutexes, now that fork() has completed.
    malloc_mutex_unlock(&huge_mtx);
    malloc_mutex_unlock(&base_mtx);
    malloc_spin_lock(&arenas_lock);
    { var i = usize(0);
        while (i < narenas; i += 1) {
            if (usize(arenas[i]) != usize(0)) {
                malloc_spin_unlock(&arenas[i].lock);
            }
        }
    }
    malloc_spin_unlock(&arenas_lock);
}
//******************************************************************************
// End library-private functions.
//******************************************************************************

//******************************************************************************
// Some tests
//******************************************************************************
fn testMallocInit() {
    @setFnTest(this, true);
    opt_print_stats = true;
    malloc_init();
    assert(malloc_initialized == true);
    var malls: [8]?&u8 = zeroes;
    for (malls) |*m| {
        *m = je_malloc(345);
        if (var mm ?= *m) {
            %%io.stdout.printf("ok\n");
        } else {
            %%io.stdout.printf("oh no\n");
        }
    }
    %%malloc_print_stats();
    for (malls) |*m| {
        if (var mm ?= *m) {
            %%io.stdout.printf("ok\n");
            je_free(mm);
        }
    }
    %%malloc_print_stats();
    //@breakpoint();
}
