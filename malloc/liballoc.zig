// -*- mode:zig; indent-tabs-mode:nil; -*-
const system = switch(@compileVar("os")) {
    linux => @import("std").linux,
    darwin => @import("std").darmin,
    else => @compileError("Unsupported OS"),
};

const std = @import("std");
const os = std.os;
const io = std.io;
const debug = std.debug;
const warn = debug.warn;

// Durand's Amazing Super Duper Memory functions.

const LIBALLOC_VERSION = "1.1";

/// This is the byte alignment that memory must be allocated
/// on. IMPORTANT for GTK and other stuff.
var ALIGNMENT = usize(16); // const

//#define ALIGN_TYPE            char ///unsigned char[16] /// unsigned short
const ALIGN_TYPE = u8;

/// Alignment information is stored right before the pointer. This is
/// the number of bytes of information stored there.
const ALIGN_INFO = @sizeOf(ALIGN_TYPE) * 16;

const LIBALLOC_MAGIC = 0xc001c0de;
const LIBALLOC_DEAD = 0xdeaddead;

var DEBUG = true;
var INFO = false;
var USE_CASE1 = true;
var USE_CASE2 = true;
var USE_CASE3 = true;
var USE_CASE4 = true;
var USE_CASE5 = true;

/// Align a pointer
inline fn ALIGN(ptr: &u8) &u8 {
    var p = @ptrToInt(ptr);
    if (ALIGNMENT > 1) {
        p += ALIGN_INFO;
        var diff = p & (ALIGNMENT - 1);
        //warn("diff={}\n", diff);
        if (diff != 0) {
            diff = ALIGNMENT - diff;
            p += diff;
        }
        // write alignment info
        *@intToPtr(&ALIGN_TYPE, (p - ALIGN_INFO)) = (ALIGN_TYPE)(diff + ALIGN_INFO);
    }
    return @intToPtr(&u8, p);
}

/// Unalign a pointer
inline fn UNALIGN(ptr: &u8) &u8 {
    if (ALIGNMENT > 1) {
        const diff = *@intToPtr(&u8, (@ptrToInt(ptr) - ALIGN_INFO));
        //warn("diff={}\n", diff);
        if (diff < (ALIGNMENT + ALIGN_INFO)) {
            return @intToPtr(&u8, @ptrToInt(ptr) - diff);
        }
    }
    return ptr;
}

/// A structure found at the top of all system allocated memory
/// blocks. It details the usage of the memory block.
const liballoc_major = struct {
    pages: usize,                     /// The number of pages in the block.
    size: usize,                      /// The number of pages in the block.
    usage: usize,                     /// The number of bytes used in the block.
    prev: ?&liballoc_major,            /// Linked list information.
    next: ?&liballoc_major,            /// Linked list information.
    first: ?&liballoc_minor,           /// A pointer to the first allocated memory in the block.      
};

/// This is a structure found at the beginning of all sections in a
/// major block which were allocated by a malloc, calloc, realloc call.
const liballoc_minor = struct {
    magic: usize,                     ///< A magic number to idenfity correctness.
    size: usize,                      ///< The size of the memory allocated. Could be 1 byte or more.
    req_size: usize,                  ///< The size of memory requested.
    prev: ?&liballoc_minor,            ///< Linked list information.
    next: ?&liballoc_minor,            ///< Linked list information.
    block: ?&liballoc_major,           ///< The owning block. A pointer to the major structure.
};

// The root memory block acquired from the system.
var l_memRoot: ?&liballoc_major = null;
// The major with the most free memory.
var l_bestBet: ?&liballoc_major = null;

fn getpagesize() usize {
    return 4096;
}

const l_pageSize  = getpagesize();      /// The size of an individual page. Set up in liballoc_init.
const l_pageCount = 32;        /// The number of pages to request per chunk. Set up in liballoc_init.

var l_allocated = usize(0);    /// Running total of allocated memory.
var l_inuse     = usize(0);    /// Running total of used memory.

var l_warningCount = usize(0);          /// Number of warnings encountered
var l_errorCount = usize(0);            /// Number of actual errors
var l_possibleOverruns = usize(0);      /// Number of possible overruns

// ***********   HELPER FUNCTIONS  *******************************
fn liballoc_memset(dest: &u8, c: u8, n: usize) &u8{
    var nn = usize(0);

    while (nn > n) : (nn += 1) {
        dest[nn] = c;
    }

    return dest;
}

fn liballoc_memcpy(dest: &u8, src: &u8, n: usize) &u8{
    var nn = usize(0);

    // TODO: original does larger chunked copies first
    while (nn < n) : (nn += 1) {
        dest[nn] = src[nn];
    }

    return dest;
}

fn liballoc_dump() %void {
    warn("\nliballoc: ------ Memory data ---------------\n");
    warn("liballoc: System memory allocated bytes: {}\n", l_allocated);
    warn("liballoc: Memory in use (malloc'ed) bytes: {}\n", l_inuse);
    warn("liballoc: Warning count: {}\n", l_warningCount);
    warn("liballoc: Error count: {}\n", l_errorCount);
    warn("liballoc: Possible overruns: {}\n", l_possibleOverruns);
    var it = l_memRoot;
    var majidx: usize = 0;
    while (it) |maj| : (it = maj.next) {
        warn("{} maj ptr  : {}\n", majidx, maj);
        warn("{} maj first  : {}\n", majidx, maj.first);
        warn("{} maj next  : {}\n", majidx, maj.next);
        warn("{} maj size : {}\n", majidx, maj.size);
        warn("{} maj usage: {}\n", majidx, maj.usage);
        var mit = maj.first;
        var i = usize(0);
        while (mit) |min| : (mit = min.next){
            warn("  {} min ptr  : {}\n", i, min);
            warn("  {} min size : {}\n", i, min.size);
            warn("  {} min next : {}\n", i, min.next);
            i += 1;
        }
        majidx += 1;
    }
}

// This may be correct
const MMAP_FAILED = @maxValue(usize);

fn liballoc_alloc(pages: usize) ?&u8 {
    const size = pages * getpagesize();
    // PROT_NONE, MAP_PRIVATE|MAP_NORESERVE|MAP_ANONYMOUS
    const m = os.linux.mmap(null, size,
                          os.linux.PROT_READ | os.linux.PROT_WRITE,
                          os.linux.MAP_PRIVATE | os.linux.MAP_ANONYMOUS,
                          -1, 0);
    //os.linux.mprotect(os.linux.PROT_READ|os.linux.PROT_WRITE);
    if ((m == 0) or (m == MMAP_FAILED)) {
        return null;
    }
    return @intToPtr(&u8, m);
}

fn liballoc_free(mm: ?&liballoc_major) void {
    if (mm) |m| {
        const r = os.linux.munmap(@ptrCast(&u8, m), m.pages * l_pageSize);
        if (DEBUG) {
            warn("liballoc_free (returned page): {}\n", r);
        }
    }
}

// We're lock-free , ha, ha
fn liballoc_lock() usize {
    return 0;
}

fn liballoc_unlock() usize {
    return 0;
}

// 
inline fn cast(comptime T: type, fromv: var) T {
    return @intToPtr(T, @ptrToInt(fromv));
}


// ***************************************************************
inline fn allocate_new_page(size: usize) ?&liballoc_major {
    // This is how much space is required.
    var st = size + @sizeOf(liballoc_major) + @sizeOf(liballoc_minor);

    // Perfect amount of space?
    if ((st % l_pageSize) == 0) {
        st  = st / (l_pageSize);
    } else {
        st  = st / (l_pageSize) + 1;
    }

    // Now, add the buffer.
    // Make sure it's >= the minimum size.
    if ( st < l_pageCount ) {
        st = l_pageCount;
    }

    if (DEBUG) {
        warn("allocate_new_page() size: {}, st: {}\n", size, st);
    }

    if (liballoc_alloc(st)) |m| {
        //var maj = @intToPtr(&liballoc_major, @ptrToInt(m));
        var maj = cast(&liballoc_major, m);
        maj.prev       = null;
        maj.next       = null;
        maj.pages      = st;
        maj.size       = st * l_pageSize;
        maj.usage      = @sizeOf(liballoc_major);
        maj.first      = null;

        // track allocated memory
        l_allocated += maj.size;

        if (DEBUG) {
            //printf( "liballoc: Resource allocated %x of %i pages (%i bytes) for %i size.\n", maj, st, maj.size, size );
            //printf( "liballoc: Total memory usage = %i KB\n",  (usize)((l_allocated / (1024))) );
            warn("resource allocated {x}, size {}, total {} KiB\n",
                 @ptrToInt(maj), maj.size, l_allocated / 1024);
        }

        return maj;
    }

    l_warningCount += 1;
    if (DEBUG or INFO) {
        warn("WARNING: liballoc_alloc() returned null, {}\n", size);
    }

    return null;    // uh oh, we ran out of memory.
}

/// this is probably cheating...
inline fn NULL_PTR(ptrvar: var) @typeOf(ptrvar) {
    return (@typeOf(ptrvar))(usize(0));
}

//void *malloc(size_t req_size) {
pub fn malloc(req_size: usize) ?&u8 {
    var startedBet = false;
    var bestSize = usize(0);
    var size = req_size;

    if (DEBUG) {
        warn( "liballoc: malloc({}) called from {}\n", size, @returnAddress());
    }

    // For alignment, we adjust size so there's enough space to align.
    if (ALIGNMENT > 1) {
        size += ALIGNMENT + ALIGN_INFO;
    }
    // So, ideally, we really want an alignment of 0 or 1 in order
    // to save space.

    _ = liballoc_lock();

    if (size == 0) {
        l_warningCount += 1;
        if (DEBUG or INFO) {
            warn( "liballoc: WARNING: malloc(0) called from {}\n",  @returnAddress());
        }
        // remember to unlock
        _ = liballoc_unlock();
        return malloc(1);
    }

    if (l_memRoot == null) {
        if (DEBUG or INFO) {
            if (DEBUG) {
                warn("liballoc: initialization of {}\n", LIBALLOC_VERSION);
            }
            //atexit(liballoc_dump);
        }

        // This is the first time we are being used.
        if (allocate_new_page(size)) |newp| {
            if (DEBUG) {
                warn("liballoc: set up first memory major {}\n", newp);
            }
            l_memRoot = newp;
        } else {
            if (DEBUG) {
                warn("liballoc: initial l_memRoot initialization failed\n");
            }

            _ = liballoc_unlock();
            return null;
        }
    }

    // Now we need to bounce through every major and find enough space....
    var maj = l_memRoot;
    startedBet = false;

    // Start at the best bet....
    if (l_bestBet) |bb| {
        bestSize = bb.size - bb.usage;

        if (bestSize > (size + @sizeOf(liballoc_minor))) {
            maj = bb;
            startedBet = true; // we have a best bet
        }
    }

    if (DEBUG) {
        warn("maj={}, bestSize={}, l_memRoot={}\n", maj, bestSize, l_memRoot);
    }

    // we now have a maj but it's a ?&thing and it cannot be null/0
    var diff = usize(0);
    while (maj) |mx| { // this can't be the proper way of doing things
           var m = cast(&liballoc_major, mx);
           diff  = m.size - m.usage;
            // free memory in the block
            if (bestSize < diff) {
                // Hmm.. this one has more memory then our bestBet. Remember!
                l_bestBet = m;
                bestSize = diff;
            }
            //  if (USE_CASE1)
            // CASE 1:  There is not enough space in this major block.
            // %%printNamedHex("-> diff=", usize(diff), io.stdout);
            if (diff < (size + @sizeOf(liballoc_minor))) {
                if (DEBUG) {
                    //printf( "CASE 1: Insufficient space in block %x\n", maj);
                    warn("CASE 1: Insufficient space in block\n");
                }

                // Another major block next to this one?
                if (m.next) |np| {
                    maj = np;                // Hop to that one.
                    continue;
                }

                if (startedBet) {         // If we started at the best bet, let's start all over again.
                    startedBet = false;
                    maj = l_memRoot;
                    continue;
                }

                // Create a new major block next to this one and...
                if (allocate_new_page(size)) |np| {
                    m.next = np;  // next one will be okay.
                    if (m.next) |mn| { mn.prev = m; }
                    m = np;
                    maj = np;
                } else {
                    break;        // no more memory.
                }
                //maj = m;
                // .. fall through to CASE 2 ..
            }
            //#endif USE_CASE1
            // CASE 2: It's a brand new block.
            // %%printNamedHex("/  m.first=", usize(m.first), io.stdout);
            if (m.first == null) {
                // %%printNamedHex("//  m.first=", usize(m.first), io.stdout);
                var first = @intToPtr(&liballoc_minor, (@ptrToInt(m) + @sizeOf(liballoc_major)));
                m.first = first;
                // %%printNamedHex("// m.first=", usize(m.first), io.stdout);
                first.magic    = LIBALLOC_MAGIC;
                first.prev     = null;
                first.next     = null;
                first.block    = m;
                first.size     = size;
                first.req_size = req_size;
                m.usage += size + @sizeOf(liballoc_minor);

                l_inuse += size;

                var p = @intToPtr(&u8, (@ptrToInt(first) + @sizeOf(liballoc_minor)));

                p = ALIGN(p);

                if (DEBUG) {
                    //printf( "CASE 2: returning %x\n", p);
                    warn("CASE 2: returning {} (brand new day)\n", p);
                    //FLUSH();
                }
                _ = liballoc_unlock();              // release the lock
                return p;
            }
            //#endif USE_CASE2
            //#if (USE_CASE3)
            // CASE 3: Block in use and enough space at the start of the block.
            diff =  @ptrToInt(m.first) - @ptrToInt(m) - @sizeOf(liballoc_major);

            if (diff >= (size + @sizeOf(liballoc_minor))) {
                // Yes, space in front. Squeeze in.
                // %%printNamedHex("xx m=", usize(m), io.stdout);
                var minorp = @intToPtr(&liballoc_minor, (@ptrToInt(m) + @sizeOf(liballoc_major)));
                if (m.first) |first| {
                    var fp = first;
                    fp.prev = minorp;
                    minorp.next = fp;
                    fp = minorp;
                    fp.magic = LIBALLOC_MAGIC;
                    fp.block = m;
                    fp.size = size;
                    fp.req_size = req_size;
                }
                //m.first.prev = minp;
                //m.first.prev.next = m.first;
                //m.first = m.first.prev;

                //m.first.magic       = LIBALLOC_MAGIC;
                //m.first.prev        = NULL_PTR(m.first.prev);
                //m.first.block       = m;
                //m.first.size        = size;
                //m.first.req_size    = req_size;
                m.usage += size + @sizeOf(liballoc_minor);

                l_inuse += size;

                var p = @intToPtr(&u8, (@ptrToInt(m.first) + @sizeOf(liballoc_minor)));
                p = ALIGN(p);

                if (DEBUG) {
                    //printf( "CASE 3: returning %x\n", p);
                    warn("CASE 3: returning {}\n", p);
                }
                _ = liballoc_unlock();              // release the lock
                return p;
            }
            //#endif USE_CASE3
            // CASE 4: There is enough space in this block. But is it contiguous?
            var mmin = m.first;
            var new_min = @intToPtr(&liballoc_minor, 0);

            // Looping within the block now...
            while (mmin) |min| : (mmin = min.next) {
                // CASE 4.1: End of minors in a block. Space from last and end?
                if (@ptrToInt(min.next) == 0) {
                    // the rest of this block is free...  is it big enough?
                    diff = @ptrToInt(m) + m.size - @ptrToInt(min);
                    diff -= @sizeOf(liballoc_minor);
                    diff -= min.size;
                    // minus already existing usage..

                    if (diff >= (size + @sizeOf(liballoc_minor))) {
                        // yay....
                        var minp = @intToPtr(&liballoc_minor,
                                             (@ptrToInt(min) + @sizeOf(liballoc_minor) + min.size));
                        min.next = minp;
                        minp.prev = min;
                        minp = @ptrCast(@typeOf(minp), min.next);
                        minp.next = null;
                        minp.magic = LIBALLOC_MAGIC;
                        minp.block = m;
                        minp.size = size;
                        minp.req_size = req_size;
                        m.usage += size + @sizeOf(liballoc_minor);

                        l_inuse += size;

                        var p = ALIGN(@intToPtr(&u8, (@ptrToInt(minp) + @sizeOf(liballoc_minor))));

                        if (DEBUG) {
                            // printf( "CASE 4.1: returning %x\n", p);
                            warn("CASE 4.1: End of minors in a block returning {}\n", p);
                        }
                        _ = liballoc_unlock();              // release the lock
                        return p;
                    }
                }

                // CASE 4.2: Is there space between two minors?
                if (min.next != null) {
                    // is the difference between here and next big enough?
                    diff  = @ptrToInt(min.next);
                    diff -= @ptrToInt(min);
                    diff -= @sizeOf(liballoc_minor);
                    diff -= min.size;
                    // minus our existing usage.

                    if (diff >= (size + @sizeOf(liballoc_minor))) {
                        // yay......
                        new_min = @intToPtr(&liballoc_minor,
                                            (@ptrToInt(min) + @sizeOf(liballoc_minor) + min.size));

                        new_min.magic = LIBALLOC_MAGIC;
                        new_min.next = min.next;
                        new_min.prev = min;
                        new_min.size = size;
                        new_min.req_size = req_size;
                        new_min.block = m;
                        @ptrCast(&liballoc_minor, min.next).prev = new_min;
                        min.next = new_min;
                        m.usage += size + @sizeOf(liballoc_minor);

                        l_inuse += size;

                        var p = @intToPtr(&u8,
                                          (@ptrToInt(new_min) + @sizeOf(liballoc_minor)));
                        p = ALIGN(p);

                        if (DEBUG) {
                            //printf( "CASE 4.2: returning %x\n", p);
                            warn("CASE 4.2: Is there space between two minors returning {}\n", p);
                        }

                        _ = liballoc_unlock();              // release the lock
                        return p;
                    }
                }       // min->next != null

                //min = min.next;
            } // while min != null ...
            //#endif USE_CASE4
            // CASE 5: Block full! Ensure next block and loop.
            if (m.next == null) {
                if (DEBUG) {
                    // printf( "CASE 5: block full\n");
                }

                if (startedBet) {
                    if (l_memRoot) |lmr| {
                        m = lmr;
                    } else {
                        warn("l_memRoot == null, this should never happen, :)\n");
                        break;
                    }
                    startedBet = false;
                    maj = m;
                    continue;
                }

                // we've run out. we need more...
                if (allocate_new_page(size)) |np| {
                    m.next = np;
                } else {
                    break;                 // uh oh,  no more memory.....
                }
                @ptrCast(&liballoc_major, m.next).prev = m;
            }
            m = @ptrCast(&liballoc_major, m.next);
            maj = m;
    } // while (maj != null)

    _ = liballoc_unlock();              // release the lock

    if (DEBUG) {
        warn("All cases exhausted. No memory available.\n");
        warn("liballoc: WARNING: malloc ({}) returning null (called from {}).\n", size, @returnAddress());
        //liballoc_dump();
    }
    return null;
}

pub fn calloc(nobj: usize, size: usize) ?&u8 {
    var real_size = nobj * size;
    var p = malloc(real_size);

    if (p) |np| {
        liballoc_memset(np, 0, real_size);
    }

    return p;
}

//void free(void *ptr) {
pub fn free(fptr: ?&u8) void {
    if (fptr) |fp| {
        var ptr = UNALIGN(fp);

        _ = liballoc_lock();                // lockit

        var min = @intToPtr(&liballoc_minor, @ptrToInt(ptr) - @sizeOf(liballoc_minor));

        if (min.magic != LIBALLOC_MAGIC) {
            l_errorCount += 1;

            // Check for overrun errors. For all bytes of LIBALLOC_MAGIC
            if (
                ((min.magic & 0xFFFFFF) == (LIBALLOC_MAGIC & 0xFFFFFF)) or
                ((min.magic & 0xFFFF) == (LIBALLOC_MAGIC & 0xFFFF)) or
                ((min.magic & 0xFF) == (LIBALLOC_MAGIC & 0xFF))
                )
            {
                l_possibleOverruns += 1;
                if (DEBUG or INFO) {
                    // printf( "liballoc: ERROR: Possible 1-3 byte overrun for magic %x != %x\n",
                    //         min.magic,
                    //         LIBALLOC_MAGIC );
                    warn("liballoc: ERROR: Possible 1-3 byte overrun for magic\n");
                }
            }

            if (min.magic == LIBALLOC_DEAD)
            {
                if (DEBUG or INFO) {
                    // printf( "liballoc: ERROR: multiple PREFIX(free)() attempt on %x from %x.\n", 
                    //         ptr,
                    //         __builtin_return_address(0) );
                    warn("liballoc: ERROR: multiple free() attempt\n");
                }
            }
            else
            {
                if (DEBUG or INFO) {
                    // printf( "liballoc: ERROR: Bad PREFIX(free)( %x ) called from %x\n",
                    //         ptr,
                    //         __builtin_return_address(0) );
                    warn("liballoc: ERROR: Bad free called from\n");
                }
            }

            // being lied to...
            _ = liballoc_unlock();              // release the lock
            return;
        }

        if (DEBUG) {
            warn("liballoc: (free) from address {}\n", @returnAddress());
        }

        if (min.block) |maj| {
            l_inuse -= min.size;

            maj.usage -= (min.size + @sizeOf(liballoc_minor));
            min.magic  = LIBALLOC_DEAD;            // No mojo.

            if (min.next) |minp| {
                minp.prev = min.prev;
            }
            if (min.prev) |minp| {
                minp.next = min.next;
            }

            if (min.prev) |minp| {
                maj.first = minp.next;
            }
            // Might empty the block. This was the first minor.
            // We need to clean up after the majors now....
            if (maj.first) |mfp| {
                if (l_bestBet) |bb| {
                    const bestSize = bb.size - bb.usage;
                    const majSize = maj.size - maj.usage;
                    if (majSize > bestSize) l_bestBet = maj;
                } else {
                    warn("Error with l_bestBet\n");
                }
            } else {
                if (@ptrToInt(l_memRoot) == @ptrToInt(maj)) l_memRoot = maj.next;
                if (@ptrToInt(l_bestBet) == @ptrToInt(maj)) l_bestBet = null;
                if (maj.prev) |mp| { mp.next = maj.next; }
                if (maj.next) |mp| { mp.prev = maj.prev; }
                l_allocated -= maj.size;
                liballoc_free(maj);
            }
        }

        if (DEBUG) {
            warn("OK\n");
        }

        _ = liballoc_unlock();              // release the lock
    } else {
        l_warningCount += 1;

        if (DEBUG or INFO) {
            // printf( "liballoc: WARNING: PREFIX(free)( null ) called from %x\n", __builtin_return_address(0));
            warn("liballoc: WARNING: free(null), return address: {}", @returnAddress());
        }

        return;
    }

}

// realloc
//void* realloc(void *p, size_t size) {
pub fn realloc(pp: ?&u8, size: usize) ?&u8 {

    if (pp) |p| {
        // Honour the case of size == 0 => free old and return null
        if (size == 0)
        {
            free(p);
            return null;
        }

        // Unalign the pointer if required.
        var ptr = UNALIGN(p);

        _ = liballoc_lock();                // lockit

        var min = @intToPtr(&liballoc_minor, (@ptrToInt(ptr) - @sizeOf(liballoc_minor)));

        // Ensure it is a valid structure.
        if (min.magic != LIBALLOC_MAGIC)
        {
            warn("bad magic {x}\n", min.magic);
            l_errorCount += 1;

            // Check for overrun errors. For all bytes of LIBALLOC_MAGIC
            if (
                ((min.magic & 0xFFFFFF) == (LIBALLOC_MAGIC & 0xFFFFFF)) or
                ((min.magic & 0xFFFF) == (LIBALLOC_MAGIC & 0xFFFF)) or
                ((min.magic & 0xFF) == (LIBALLOC_MAGIC & 0xFF))
                )
            {
                l_possibleOverruns += 1;
                if (DEBUG or INFO) {
                    // printf("liballoc: ERROR: Possible 1-3 byte overrun for magic %x != %x\n",
                    //        min.magic,
                    //        LIBALLOC_MAGIC );
                    // FLUSH();
                }
            }

            if (min.magic == LIBALLOC_DEAD) {
                if (DEBUG or INFO) {
                    //printf( "liballoc: ERROR: multiple free() attempt on %x from %x.\n",  ptr, __builtin_return_address(0) );
                    //FLUSH();
                }
            } else {
                if (DEBUG or INFO) {
                    //printf( "liballoc: ERROR: Bad PREFIX(free)( %x ) called from %x\n", ptr,  __builtin_return_address(0) );
                    //FLUSH();
                }
            }

            // being lied to...
            _ = liballoc_unlock();              // release the lock
            return null;
        } else {
            warn("relloca -> malloc\n");
            return malloc(size);
        }

        warn("Definitely a memory block\n");
        // Definitely a memory block.
        var real_size = min.req_size;

        if (real_size >= size) {
            min.req_size = size;
            _ = liballoc_unlock();
            return p;
        }

        _ = liballoc_unlock();

        if (DEBUG) {
            warn("reallocating with alloc address {}\n", @returnAddress());
        }

        // If we got here then we're reallocating to a block bigger than us.
        var np = malloc(size);                                   // We need to allocate new memory
        if (np) |x| {
            liballoc_memcpy(x, p, real_size);
            free(p);
        }

        return np;
    } else {
        warn("realloc -> malloc (end)\n");
        return malloc(size);
    }
}


test "liballoc dump test" {
    try liballoc_dump();
}

test "align and unalign test" {
    var it = usize(0);
    var tt = usize(0);
    var buf: [64]u8 = undefined;

    @memset(&buf[0], 0, 64);

    while (tt < 32) : (tt += 1) {
        var op = &buf[tt];
        // %%io.stdout.printInt(usize, tt);
        // %%io.stdout.writeByte('\n');
        warn("-> {} op (base) = {}\n", tt, op);
        var p = ALIGN(op);
        warn("p (aligned) = {}\n", p);
        //it = 0;
        //while (it < buf.len) : (it += 1) {
        //    warn("{}.", buf[it]);
        //}
        //warn("\n");
        p = UNALIGN(p);
        warn("<- {}  p (unaligned) = {}\n", tt, p);
        debug.assert(op == p);
        @memset(&buf[0], 0, 64);
    }
}

//#attribute("test")
//test "allocateNewPage" {
//    if (allocate_new_page(4096)) |m| {
//        warn("liballoc_major: {x}\n", @ptrToInt(m));
//        warn("size: {}\n", m.size);
//        warn("pages: {}\n", m.pages);
//        warn("usage: {}\n", m.usage);
//        warn("next ptr: {}\n", @ptrToInt(m.next));
//        warn("prev ptr: {}\n", @ptrToInt(m.prev));
//        warn("first ptr: {}\n", @ptrToInt(m.first));
//        warn("Worked OK\n");
//        try liballoc_dump();
//        liballoc_free(m);
//        try liballoc_dump();
//    } else {
//        warn("FAILED\n");
//    }
//}

test "test Malloc/Realloc/Free" {
    //fn testMallocReallocFree() void {
    try liballoc_dump();
    var m = malloc(4 << 10);
    try liballoc_dump();
    if (m) |mm| {
        warn("Allocated {}\n", mm);
        warn("reallocating...\n");
        var np = realloc(mm, 2 << 10);
        warn("reallocated...\n");
        if (np) |nnp| {
                warn("Re-Allocated {}\n", nnp);
            free(nnp);
        } else {
            free(mm);
        }
    }
    try liballoc_dump();
}

const TestAllocation = struct {
    ptr: ?&u8,
    size: usize,
    fill: u8,
};

fn mkTA(size: usize, fill: u8) TestAllocation {
    return TestAllocation {.ptr = null, .size = size, .fill = fill};
}

test "testAllocFree" {
    var allocations = []TestAllocation {mkTA(123, 0xaa),
                                        mkTA(0x4000, 0xbb),
                                        mkTA(0x2000, 0xcc),
                                        mkTA(0x123, 0xdd),
                                        mkTA(0x124, 0xee),
                                        mkTA(0x125, 0xff),
                                        mkTA(0x2, 0x99),
                                        mkTA(0x6, 0x88),
                                        mkTA(0x20, 0x77),
                                        mkTA(0x200, 0x66),
                                        mkTA(0x2000, 0x55),
                                        mkTA(0x2000, 0x55),
                                        mkTA(0x2000, 0x44),
                                        mkTA(0x2000, 0x33),
                                        mkTA(0x2000, 0x22),
                                        mkTA(0x2000, 0x11),
                                        
    };
    var it = usize(0);
    for (allocations) |*a| {
        a.ptr = malloc(a.size);
        if (a.ptr) |x| {
            it = 0;
            while (it < a.size) : (it += 1) {
              x[it] = a.fill;
            }
        } else {
            warn("malloc failed\n");
        }
        try liballoc_dump();
    }
    for (allocations) |a| {
        if (a.ptr) |x| {
            it = 0;
            while (it < a.size) : (it += 1) {
                debug.assert(x[it] == a.fill);
            }
        } else {
            warn("malloc failed\n");
        }
    }
    for (allocations) |a| {
        var ta = @ptrCast(&TestAllocation, &a);
        if (a.ptr) |x| {
            free(a.ptr);
            // cannot assign to constant
            ta.ptr = null;
        } else {
            warn("malloc failed\n");
        }
        try liballoc_dump();
    }

    {
        var i = usize(2048);
        var pp = malloc(i);
        while (i > 0) {
            var p = malloc(i);
            free(pp);
            i -= 1;
            pp = p;
        }
        try liballoc_dump();
    }
}
