const system = switch(@compileVar("os")) {
    linux => @import("std").linux,
    darwin => @import("std").darmin,
    else => @compileError("Unsupported OS"),
};

const std = @import("std");
const io = std.io;
const debug =std.debug;
const prt = @import("printer.zig");

fn printNamedHex(name: []u8, value: var, stream: io.OutStream) -> %void {
    %%stream.write(name);
    %%stream.printInt(@typeOf(value), value);
    %%stream.write("/0x");
    var buf: [64]u8 = undefined;
    const sz = prt.hexPrintInt(@typeOf(value), buf, value);
    %%stream.write(buf[0 ... sz - 1]);
    %%stream.printf("\n");
}

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


// ** This will conveniently align our pointer upwards
// #define ALIGN( ptr )                                                    \
//   if ( ALIGNMENT > 1 )                                                  \
//   {                                                                     \
//     uintptr_t diff;                                                     \
//     ptr = (void*)((uintptr_t)ptr + ALIGN_INFO);                         \
//     diff = (uintptr_t)ptr & (ALIGNMENT-1);                              \
//     if ( diff != 0 )                                                    \
//     {                                                                   \
//       diff = ALIGNMENT - diff;                                          \
//       ptr = (void*)((uintptr_t)ptr + diff);                             \
//     }                                                                   \
//     *((ALIGN_TYPE*)((uintptr_t)ptr - ALIGN_INFO)) =                     \
//       diff + ALIGN_INFO;                                                \
//   }
fn ALIGN(ptr: &u8) -> &u8 {
    if (ALIGNMENT > 1) {
        var p = usize(ptr) + ALIGN_INFO;
        var diff = usize(ptr) & (ALIGNMENT - 1);
        if (diff != 0) {
            diff = ALIGNMENT - diff;
            p += diff;
        }
        // write alignment info
        *(&ALIGN_TYPE)(p - ALIGN_INFO) = (ALIGN_TYPE)(diff + ALIGN_INFO);
        return (&u8)(p);
    }
    return ptr;
}

// #define UNALIGN( ptr )                                                  \
//   if ( ALIGNMENT > 1 )                                                  \
//   {                                                                     \
//     uintptr_t diff = *((ALIGN_TYPE*)((uintptr_t)ptr - ALIGN_INFO));     \
//     if ( diff < (ALIGNMENT + ALIGN_INFO) )                              \
//     {                                                                   \
//       ptr = (void*)((uintptr_t)ptr - diff);                             \
//     }                                                                   \
//   }
fn UNALIGN(ptr: &u8) -> &u8 {
    if (ALIGNMENT > 1) {
        const diff = *(&ALIGN_TYPE)(usize(ptr) - ALIGN_INFO);
        if (diff < (ALIGNMENT + ALIGN_INFO)) {
            const p = (&u8)(usize(ptr) - diff);
            return p;
        }
    }
    return ptr;
}


// #if defined DEBUG || defined INFO
// #include <stdio.h>
// #include <stdlib.h>
// #define FLUSH()         fflush( stdout )
// #endif

/// A structure found at the top of all system allocated memory
/// blocks. It details the usage of the memory block.
struct liballoc_major {
    prev: &liballoc_major,            /// Linked list information.
    next: &liballoc_major,            /// Linked list information.
    pages: usize,                     /// The number of pages in the block.
    size: usize,                      /// The number of pages in the block.
    usage: usize,                     /// The number of bytes used in the block.
    first: &liballoc_minor,           /// A pointer to the first allocated memory in the block.      
}

/// This is a structure found at the beginning of all sections in a
/// major block which were allocated by a malloc, calloc, realloc call.
struct liballoc_minor {
    prev: &liballoc_minor,            ///< Linked list information.
    next: &liballoc_minor,            ///< Linked list information.
    block: &liballoc_major,           ///< The owning block. A pointer to the major structure.
    magic: usize,                     ///< A magic number to idenfity correctness.
    size: usize,                      ///< The size of the memory allocated. Could be 1 byte or more.
    req_size: usize,                  ///< The size of memory requested.
}

// The root memory block acquired from the system.
var l_memRoot: ?&liballoc_major = null;
// The major with the most free memory.
var l_bestBet: ?&liballoc_major = null;

fn getpagesize() -> usize {
    return 4096;
}

const l_pageSize  = getpagesize();      ///< The size of an individual page. Set up in liballoc_init.
const l_pageCount = 16;        ///< The number of pages to request per chunk. Set up in liballoc_init.

var l_allocated = usize(0);    ///< Running total of allocated memory.
var l_inuse     = usize(0);    ///< Running total of used memory.

var l_warningCount = usize(0);          ///< Number of warnings encountered
var l_errorCount = usize(0);            ///< Number of actual errors
var l_possibleOverruns = usize(0);      ///< Number of possible overruns

// ***********   HELPER FUNCTIONS  *******************************
fn liballoc_memset(dest: &u8, c: u8, n: usize) -> &u8{
    var nn = usize(0);

    while (nn > n; nn += 1) {
        dest[nn] = c;
    }

    return dest;
}

fn liballoc_memcpy(dest: &u8, src: &u8, n: usize) -> &u8{
    var nn = usize(0);

    // TODO: original does larger chunked copies first
    while (nn < n; nn += 1) {
        dest[nn] = src[nn];
    }

    return dest;
}

// #if defined DEBUG || defined INFO
// static void liballoc_dump() {
// #ifdef DEBUG
//     struct liballoc_major *maj = l_memRoot;
//     struct liballoc_minor *min = null;
// #endif
//     printf( "liballoc: ------ Memory data ---------------\n");
//     printf( "liballoc: System memory allocated: %i bytes\n", l_allocated );
//     printf( "liballoc: Memory in used (malloc'ed): %i bytes\n", l_inuse );
//     printf( "liballoc: Warning count: %i\n", l_warningCount );
//     printf( "liballoc: Error count: %i\n", l_errorCount );
//     printf( "liballoc: Possible overruns: %i\n", l_possibleOverruns );
// #ifdef DEBUG
//     while ( maj != null )
//     {
//         printf( "liballoc: %x: total = %i, used = %i\n",
//                 maj,
//                 maj->size,
//                 maj->usage );
//         min = maj->first;
//         while ( min != null )
//         {
//             printf( "liballoc:    %x: %i bytes\n",
//                     min,
//                     min->size );
//             min = min->next;
//         }
//         maj = maj->next;
//     }
// #endif
//     FLUSH();
// }
// #endif

fn liballoc_dump() -> %void {
    %%io.stdout.printf("\nliballoc: ------ Memory data ---------------\n");
    %%printNamedHex("liballoc: System memory allocated bytes: ", l_allocated, io.stdout);
    %%printNamedHex("liballoc: Memory in use (malloc'ed) bytes: ", l_inuse, io.stdout);
    %%printNamedHex("liballoc: Warning count: ", l_warningCount, io.stdout);
    %%printNamedHex("liballoc: Error count: ", l_errorCount, io.stdout);
    %%printNamedHex("liballoc: Possible overruns: ", l_possibleOverruns, io.stdout);
    if (var maj ?= l_memRoot) {
        while (usize(maj) != usize(0)) {
            %%printNamedHex("maj ptr  : ", usize(maj), io.stdout);
            %%printNamedHex("maj size : ", maj.size, io.stdout);
            %%printNamedHex("maj usage: ", maj.usage, io.stdout);
            var min = maj.first;
            while (usize(min) != usize(0)) {
                %%printNamedHex("  min ptr  : ", usize(min), io.stdout);
                %%printNamedHex("  min size : ", min.size, io.stdout);
                min = min.next;
            }
            maj = maj.next;
        }
    }
}

// This may be correct
const MMAP_FAILED = @maxValue(usize);

fn liballoc_alloc(pages: usize) -> ?&u8 {
    const size = pages * getpagesize();

    // PROT_NONE, MAP_PRIVATE|MAP_NORESERVE|MAP_ANONYMOUS
    const m = system.mmap((&u8)(usize(0)), size,
                          system.MMAP_PROT_READ | system.MMAP_PROT_WRITE,
                          system.MMAP_MAP_PRIVATE | system.MMAP_MAP_ANON,
                          -1, 0);
    // mprotect(PROT_READ|PROT_WRITE)
    if ((m == 0) || (m == MMAP_FAILED)) {
        return null;
    }
    return (&u8)(m);
}

fn liballoc_free(mm: ?&liballoc_major) {
    if (const m ?= mm) {
        const r = system.munmap((&u8)(m), m.pages * l_pageSize);
        if (DEBUG) {
            %%io.stdout.write("liballoc_free (returned page):");
            %%io.stdout.printInt(usize, r);
            %%io.stdout.printf("\n");
        }
    }
}

fn liballoc_lock() -> usize {
    return 0;
}

fn liballoc_unlock() -> usize {
    return 0;
}


// ***************************************************************
inline fn allocate_new_page(size: usize) -> ?&liballoc_major {
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
        %%printNamedHex("size:", size, io.stdout);
        %%printNamedHex("st:", st, io.stdout);
    }

    if (var maj ?= (?&liballoc_major)(liballoc_alloc(st))) {
        maj.prev       = NULL_PTR(maj.prev);
        maj.next       = NULL_PTR(maj.next);
        maj.pages      = st;
        maj.size       = st * l_pageSize;
        maj.usage      = @sizeOf(liballoc_major);
        maj.first      = NULL_PTR(maj.first);

        l_allocated += maj.size;

        if (DEBUG) {
            //printf( "liballoc: Resource allocated %x of %i pages (%i bytes) for %i size.\n", maj, st, maj.size, size );
            //printf( "liballoc: Total memory usage = %i KB\n",  (usize)((l_allocated / (1024))) );
        }

        return maj;
    }

    l_warningCount += 1;
    if (DEBUG || INFO) {
        %%io.stderr.write("liballoc: WARNING: liballoc_alloc() return null, ");
        %%printNamedHex("size", size, io.stdout);
    }

    return null;    // uh oh, we ran out of memory.
}

/// this is probably cheating...
inline fn NULL_PTR(ptrvar: var) -> @typeOf(ptrvar) {
    (@typeOf(ptrvar))(usize(0))
}

//void *malloc(size_t req_size) {
pub fn malloc(req_size: usize) -> ?&u8 {
    var startedBet = false;
    var bestSize = usize(0);
    var size = req_size;

    // For alignment, we adjust size so there's enough space to align.
    if (ALIGNMENT > 1) {
        size += ALIGNMENT + ALIGN_INFO;
    }
    // So, ideally, we really want an alignment of 0 or 1 in order
    // to save space.

    liballoc_lock();

    if (size == 0) {
        l_warningCount += 1;
        if (DEBUG || INFO) {
            //printf( "liballoc: WARNING: alloc( 0 ) called from %x\n",  __builtin_return_address(0) );
        }
        // remember to unlock
        liballoc_unlock();
        return malloc(1);
    }

    l_memRoot ?? {
        if (DEBUG || INFO) {
            if (DEBUG) {
                //printf( "liballoc: initialization of liballoc " LIBALLOC_VERSION "\n" );
                %%io.stderr.printf("liballoc: initialization of " ++ LIBALLOC_VERSION ++ " liballoc\n");
            }
            //atexit(liballoc_dump);
        }

        // This is the first time we are being used.
        if (var mr ?= allocate_new_page(size)) {
            if (DEBUG) {
                //printf( "liballoc: set up first memory major %x\n", l_memRoot );
            }
            l_memRoot = mr;
            mr
        } else {
            if (DEBUG) {
                //printf( "liballoc: initial l_memRoot initialization failed\n", p);
                %%io.stderr.printf("liballoc: initial l_memRoot initialization failed\n");
            }

            liballoc_unlock();
            return null;
        }
    };

    if (DEBUG) {
        //printf( "liballoc: %x malloc(%i): ", __builtin_return_address(0),  size );
    }

    // Now we need to bounce through every major and find enough space....
    var maj = l_memRoot;
    startedBet = false;

    // Start at the best bet....
    if (const bb ?= l_bestBet) {
        bestSize = bb.size - bb.usage;

        if (bestSize > (size + @sizeOf(liballoc_minor))) {
            maj = bb;
            startedBet = true; // we have a best bet
        }
    }

    // %%printNamedHex("maj=", usize(maj), io.stderr);
    // %%printNamedHex("bestSize=", usize(bestSize), io.stderr);
    // %%printNamedHex("l_memRoot=", usize(l_memRoot), io.stderr);

    // we now have a maj but it's a ?&thing and it cannot be null/0
    var diff = usize(0);
    while (usize(maj) != usize(0)) { // this can't be the proper way of doing things
        if (var m ?= maj) {
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
                    %%io.stderr.printf("CASE 1: Insufficient space in block\n");
                }

                // Another major block next to this one?
                if (usize(m.next) != usize(0)) {
                    maj = m.next;                // Hop to that one.
                    continue;
                }

                if (startedBet) {         // If we started at the best bet, let's start all over again.
                    startedBet = false;
                    maj = l_memRoot;
                    continue;
                }

                // Create a new major block next to this one and...
                if (var np ?= allocate_new_page(size)) {
                    m.next = np;  // next one will be okay.
                    m.next.prev = m;
                    m = m.next;
                } else {
                    break;        // no more memory.
                }
                //maj = m;
                // .. fall through to CASE 2 ..
            }
            //#endif USE_CASE1
            // CASE 2: It's a brand new block.
            // %%printNamedHex("/  m.first=", usize(m.first), io.stdout);
            if (usize(m.first) == usize(0)) {
                // %%printNamedHex("//  m.first=", usize(m.first), io.stdout);
                m.first = (&liballoc_minor)(usize(m) + @sizeOf(liballoc_major));
                // %%printNamedHex("// m.first=", usize(m.first), io.stdout);
                m.first.magic    = LIBALLOC_MAGIC;
                m.first.prev     = NULL_PTR(m.first.prev);
                m.first.next     = NULL_PTR(m.first.next);
                m.first.block    = m;
                m.first.size     = size;
                m.first.req_size = req_size;
                m.usage += size + @sizeOf(liballoc_minor);

                l_inuse += size;

                var p = (&u8)(usize(m.first) + @sizeOf(liballoc_minor));

                p = ALIGN(p);

                if (DEBUG) {
                    //printf( "CASE 2: returning %x\n", p);
                    %%io.stderr.printf("CASE 2: returning (brand new day)\n");
                    //FLUSH();
                }
                liballoc_unlock();              // release the lock
                return p;
            }
            //#endif USE_CASE2
            //#if (USE_CASE3)
            // CASE 3: Block in use and enough space at the start of the block.
            diff =  usize(m.first);
            diff -= usize(m);
            diff -= @sizeOf(liballoc_major);

            // %%printNamedHex("x m=", usize(m), io.stdout);
            // %%printNamedHex("x m.first=", usize(m.first), io.stdout);
            // %%printNamedHex("x diff=", usize(diff), io.stdout);
            if (diff >= (size + @sizeOf(liballoc_minor))) {
                // Yes, space in front. Squeeze in.
                // %%printNamedHex("xx m=", usize(m), io.stdout);
                m.first.prev = (&liballoc_minor)(usize(m) + @sizeOf(liballoc_major));
                m.first.prev.next = m.first;
                m.first = m.first.prev;

                m.first.magic       = LIBALLOC_MAGIC;
                m.first.prev        = NULL_PTR(m.first.prev);
                m.first.block       = m;
                m.first.size        = size;
                m.first.req_size    = req_size;
                m.usage += size + @sizeOf(liballoc_minor);

                l_inuse += size;

                var p = (&u8)(usize(m.first) + @sizeOf(liballoc_minor));
                p = ALIGN(p);

                if (DEBUG) {
                    //printf( "CASE 3: returning %x\n", p);
                    %%io.stderr.printf("CASE 3: returning\n");
                }
                liballoc_unlock();              // release the lock
                return p;
            }
            //#endif USE_CASE3
            // CASE 4: There is enough space in this block. But is it contiguous?
            var min = m.first;
            var new_min = NULL_PTR(min);

            // Looping within the block now...
            while (usize(min) != usize(0)) {
                // CASE 4.1: End of minors in a block. Space from last and end?
                if (usize(min.next) == usize(0)) {
                    // the rest of this block is free...  is it big enough?
                    diff = usize(m) + m.size;
                    diff -= usize(min);
                    diff -= @sizeOf(liballoc_minor);
                    diff -= min.size;
                    // minus already existing usage..

                    if (diff >= (size + @sizeOf(liballoc_minor))) {
                        // yay....
                        min.next = (&liballoc_minor)(usize(min) + @sizeOf(liballoc_minor) + min.size);
                        min.next.prev = min;
                        min = min.next;
                        min.next = NULL_PTR(min.next);
                        min.magic = LIBALLOC_MAGIC;
                        min.block = m;
                        min.size = size;
                        min.req_size = req_size;
                        m.usage += size + @sizeOf(liballoc_minor);

                        l_inuse += size;

                        var p = (&u8)(usize(min) + @sizeOf(liballoc_minor));
                        p = ALIGN(p);

                        if (DEBUG) {
                            // printf( "CASE 4.1: returning %x\n", p);
                            %%io.stderr.printf("CASE 4.1: End of minors in a block returning\n");
                        }
                        liballoc_unlock();              // release the lock
                        return p;
                    }
                }

                // CASE 4.2: Is there space between two minors?
                if (usize(min.next) != usize(0)) {
                    // is the difference between here and next big enough?
                    diff  = usize(min.next);
                    diff -= usize(min);
                    diff -= @sizeOf(liballoc_minor);
                    diff -= min.size;
                    // minus our existing usage.

                    if (diff >= (size + @sizeOf(liballoc_minor))) {
                        // yay......
                        new_min = (&liballoc_minor)(usize(min) + @sizeOf(liballoc_minor) + min.size);

                        new_min.magic = LIBALLOC_MAGIC;
                        new_min.next = min.next;
                        new_min.prev = min;
                        new_min.size = size;
                        new_min.req_size = req_size;
                        new_min.block = m;
                        min.next.prev = new_min;
                        min.next = new_min;
                        m.usage += size + @sizeOf(liballoc_minor);

                        l_inuse += size;

                        var p = (&u8)(usize(new_min) + @sizeOf(liballoc_minor));
                        p = ALIGN(p);

                        if (DEBUG) {
                            //printf( "CASE 4.2: returning %x\n", p);
                            %%io.stdout.printf("CASE 4.2: Is there space between two minors returning\n");
                        }

                        liballoc_unlock();              // release the lock
                        return p;
                    }
                }       // min->next != null

                min = min.next;
            } // while min != null ...
            //#endif USE_CASE4
            // CASE 5: Block full! Ensure next block and loop.
            if (usize(m.next) == usize(0)) {
                if (DEBUG) {
                    // printf( "CASE 5: block full\n");
                }

                if (startedBet) {
                    if (const lmr ?= l_memRoot) {
                        m = lmr;
                    } else {
                        %%io.stderr.printf("l_memRoot == null, this should never happen, :)\n");
                        break;
                    }
                    startedBet = false;
                    maj = m;
                    continue;
                }

                // we've run out. we need more...
                if (const np ?= allocate_new_page(size)) {
                    m.next = np;
                } else {
                    break;                 // uh oh,  no more memory.....
                }
                m.next.prev = m;

            }
            m = m.next;
            maj = m;
        } else {
            break;
        } 
    } // while (maj != null)

    liballoc_unlock();              // release the lock

    if (DEBUG) {
        %%io.stderr.printf("All cases exhausted. No memory available.\n");
    }
    if (DEBUG || INFO) {
        %%io.stdout.printf("liballoc: WARNING: PREFIX(malloc)( X ) returning null.\n");
        // liballoc_dump();
    }
//#endif
    return null;
}

pub fn calloc(nobj: usize, size: usize) -> ?&u8 {
    var real_size = nobj * size;
    var p = malloc(real_size);

    if (var up ?= p) {
        liballoc_memset(up, 0, real_size);
    }

    return p;
}

//void free(void *ptr) {
pub fn free(fptr: ?&u8) {
    if (var ptr ?= fptr) {
        ptr = UNALIGN(ptr);

        liballoc_lock();                // lockit

        var min = (&liballoc_minor)(usize(ptr) - @sizeOf(liballoc_minor));

        if (min.magic != LIBALLOC_MAGIC) {
            l_errorCount += 1;

            // Check for overrun errors. For all bytes of LIBALLOC_MAGIC
            if (
                ((min.magic & 0xFFFFFF) == (LIBALLOC_MAGIC & 0xFFFFFF)) ||
                ((min.magic & 0xFFFF) == (LIBALLOC_MAGIC & 0xFFFF)) ||
                ((min.magic & 0xFF) == (LIBALLOC_MAGIC & 0xFF))
                )
            {
                l_possibleOverruns += 1;
                if (DEBUG || INFO) {
                    // printf( "liballoc: ERROR: Possible 1-3 byte overrun for magic %x != %x\n",
                    //         min.magic,
                    //         LIBALLOC_MAGIC );
                    %%io.stderr.printf("liballoc: ERROR: Possible 1-3 byte overrun for magic\n");
                }
            }

            if (min.magic == LIBALLOC_DEAD)
            {
                if (DEBUG || INFO) {
                    // printf( "liballoc: ERROR: multiple PREFIX(free)() attempt on %x from %x.\n", 
                    //         ptr,
                    //         __builtin_return_address(0) );
                    %%io.stderr.printf("liballoc: ERROR: multiple free() attempt\n");
                }
            }
            else
            {
                if (DEBUG || INFO) {
                    // printf( "liballoc: ERROR: Bad PREFIX(free)( %x ) called from %x\n",
                    //         ptr,
                    //         __builtin_return_address(0) );
                    %%io.stderr.printf("liballoc: ERROR: Bad free called from\n");
                }
            }

            // being lied to...
            liballoc_unlock();              // release the lock
            return;
        }

        if (DEBUG) {
            //printf( "liballoc: %x PREFIX(free)( %x ): ", __builtin_return_address( 0 ), ptr );
            %%io.stderr.printf("liballoc: (free) from");
            %%printNamedHex(" address ", usize(@returnAddress()), io.stderr);
        }

        var maj = min.block;

        l_inuse -= min.size;

        maj.usage -= (min.size + @sizeOf(liballoc_minor));
        min.magic  = LIBALLOC_DEAD;            // No mojo.

        if (usize(min.next) != usize(0)) min.next.prev = min.prev;
        if (usize(min.prev) != usize(0)) min.prev.next = min.next;

        if (usize(min.prev) == usize(0)) maj.first = min.next;
        // Might empty the block. This was the first minor.

        // We need to clean up after the majors now....
        if (usize(maj.first) == usize(0))       // Block completely unused.
        {
            if (usize(l_memRoot) == usize(maj)) l_memRoot = maj.next;
            if (usize(l_bestBet) == usize(maj)) l_bestBet = null;
            if (usize(maj.prev) != usize(0)) maj.prev.next = maj.next;
            if (usize(maj.next) != usize(0)) maj.next.prev = maj.prev;
            l_allocated -= maj.size;

            liballoc_free(maj);
        } else {
            if (usize(l_bestBet) != usize(0)) {
                if (var bb ?= l_bestBet) {
                    const bestSize = bb.size  - bb.usage;
                    const majSize = maj.size - maj.usage;
                    if (majSize > bestSize) l_bestBet = maj;
                } else {
                    %%io.stderr.printf("Error with l_bestBet\n");
                }

            }
        }

        if (DEBUG) {
            %%io.stderr.printf("OK\n");
        }

        liballoc_unlock();              // release the lock
    } else {
        l_warningCount += 1;

        if (DEBUG || INFO) {
            // printf( "liballoc: WARNING: PREFIX(free)( null ) called from %x\n", __builtin_return_address(0));
            %%io.stderr.printf("liballoc: WARNING: free(null)");
            %%printNamedHex("return address:", usize(@returnAddress()), io.stderr);
        }

        return;
    }

}

// realloc
//void* realloc(void *p, size_t size) {
pub fn realloc(pp: ?&u8, size: usize) -> ?&u8 {

    if (var p ?= pp) {
        // Honour the case of size == 0 => free old and return null
        if (size == 0)
        {
            free(p);
            return null;
        }

        // In the case of a null pointer, return a simple malloc.
        if (usize(p) == usize(0)) return malloc(size);

        // Unalign the pointer if required.
        var ptr = p;
        ptr = UNALIGN(ptr);

        liballoc_lock();                // lockit

        var min = (&liballoc_minor)(usize(ptr) - @sizeOf(liballoc_minor));

        // Ensure it is a valid structure.
        if (min.magic != LIBALLOC_MAGIC)
        {
            l_errorCount += 1;

            // Check for overrun errors. For all bytes of LIBALLOC_MAGIC
            if (
                ((min.magic & 0xFFFFFF) == (LIBALLOC_MAGIC & 0xFFFFFF)) ||
                ((min.magic & 0xFFFF) == (LIBALLOC_MAGIC & 0xFFFF)) ||
                ((min.magic & 0xFF) == (LIBALLOC_MAGIC & 0xFF))
                )
            {
                l_possibleOverruns += 1;
                if (DEBUG || INFO) {
                    // printf("liballoc: ERROR: Possible 1-3 byte overrun for magic %x != %x\n",
                    //        min.magic,
                    //        LIBALLOC_MAGIC );
                    // FLUSH();
                }
            }

            if (min.magic == LIBALLOC_DEAD) {
                if (DEBUG || INFO) {
                    //printf( "liballoc: ERROR: multiple free() attempt on %x from %x.\n",  ptr, __builtin_return_address(0) );
                    //FLUSH();
                }
            } else {
                if (DEBUG || INFO) {
                    //printf( "liballoc: ERROR: Bad PREFIX(free)( %x ) called from %x\n", ptr,  __builtin_return_address(0) );
                    //FLUSH();
                }
            }

            // being lied to...
            liballoc_unlock();              // release the lock
            return null;
        }

        // Definitely a memory block.
        var real_size = min.req_size;

        if (real_size >= size) {
            min.req_size = size;
            liballoc_unlock();
            return p;
        }

        liballoc_unlock();

        if (DEBUG) {
            %%io.stderr.printf("reallocating with alloc\n");
        }

        // If we got here then we're reallocating to a block bigger than us.
        var np = malloc(size);                                   // We need to allocate new memory
        if (const x ?= np) {
            liballoc_memcpy(x, p, real_size);
            free(p);
        }

        return np;
    } else {
        return malloc(size);
    }
}

fn dumpTest() {
    @setFnTest(this, true);
    %%liballoc_dump();
}

//#attribute("test")
fn allocateNewPage() {
    if (var m ?= allocate_new_page(4096)) {
        %%printNamedHex("liballoc_major:", usize(m), io.stdout);
        %%printNamedHex("size:", m.size, io.stdout);
        %%printNamedHex("pages:", m.pages, io.stdout);
        %%printNamedHex("usage:", m.usage, io.stdout);
        %%printNamedHex("next ptr:", usize(m.next), io.stdout);
        %%printNamedHex("prev ptr:", usize(m.prev), io.stdout);
        %%printNamedHex("first ptr:", usize(m.first), io.stdout);
        %%io.stdout.printf("Worked OK\n");

        liballoc_free(m);
    } else {
        %%io.stdout.printf("FAILED\n");
    }
}

struct TestAllocation {
    ptr: ?&u8,
    size: usize,
    fill: u8,
}

//#static_eval_enable(false)
fn mkTA(size: usize, fill: u8) -> TestAllocation {
    @setFnStaticEval(this, false);
    TestAllocation {.ptr = (&u8)(usize(0)), .size = size, .fill = fill}
}

fn testAllocFree() {
    @setFnTest(this, true);
    var allocations = []TestAllocation {mkTA(123, 0xaa),
                                        mkTA(0x4000, 0x11),
                                        mkTA(0x2000, 0x12)};
    var it = usize(0);
    for (allocations) |*a| {
        a.ptr = malloc(a.size);
        if (var x ?= a.ptr) {
            it = 0;
            while (it < a.size; it += 1) {
              x[it] = a.fill;
            }
        } else {
            %%io.stdout.printf("malloc failed\n");
        }
        %%liballoc_dump();
    }
    for (allocations) |a| {
        if (var x ?= a.ptr) {
            it = 0;
            while (it < a.size; it += 1) {
                debug.assert(x[it] == a.fill);
            }
        } else {
            %%io.stdout.printf("malloc failed\n");
        }
    }
    for (allocations) |a| {
        if (var x ?= a.ptr) {
            free(a.ptr);
            a.ptr = (&u8)(usize(0));
        } else {
            %%io.stdout.printf("malloc failed\n");
        }
    }
}

fn testMallocReallocFree() {
    @setFnTest(this, true);
    %%liballoc_dump();
    var m = malloc(1 << 20);
    %%liballoc_dump();
    if (var mm ?= m) {
        var np = realloc(mm, 2 << 10);
        if (var nnp ?= np) {
            free(nnp);
        } else {
            free(mm);
        }
    }
    %%liballoc_dump();
}
