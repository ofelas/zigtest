const system = switch(@compileVar("os")) {
    linux => @import("std").linux,
    darwin => @import("std").darmin,
    else => @compileError("Unsupported OS"),
};
const std = @import("std");
const os = std.os;
const io = std.io;
const mem = std.mem;
const debug = std.debug;
const assert = debug.assert;
const str = std.str;
const list = std.list;
const printer = @import("printer.zig");
const liballoc = @import("liballoc.zig");

enum MallocKind {
    STD,
    JOKER,
    JEMALLOC,
    LIBALLOC,
}

var mallocator_kind = MallocKind.STD;

// using external jemalloc_linux.c
pub extern fn malloc(size: c_ulong) -> ?&c_void;
pub extern fn free(ptr: ?&c_void);
pub extern fn realloc(ptr: ?&c_void, size: c_ulong) -> ?&c_void;
//pub extern fn memalign(boundary: c_ulong, size: c_ulong) -> ?&c_void;
//pub extern fn valloc(size: c_ulong) -> ?&c_void;
//pub extern fn calloc(num: c_ulong, size: c_ulong) -> ?&c_void;
//pub extern fn posix_memalign(memptr: ?&?&c_void, alignment: c_ulong, size: c_ulong) -> c_int;

const hexPrintInt = printer.hexPrintInt;

pub var allocator = mem.Allocator {
    .allocFn = localAlloc,
    .reallocFn = localRealloc,
    .freeFn = localFree,
    .context = null,
};

// This may be correct
const MMAP_FAILED = @maxValue(usize);

pub error NoMem;

// then port jemalloc_linux to zig
// red-black tree and all? ha, ha, optmistic...
// ~5000 lines of magic

struct MmapAllocator {
    m: usize,
    total: usize,
    used: usize,
    initial_size: usize,

    fn init(mapper: &MmapAllocator) -> %void {
        var m = usize(0);
        var buf: [32]u8 = zeroes;
        mapper.m = 0;
        mapper.initial_size = 4 * (1 << 10); // 4 KiB (initially)
        mapper.used = 0;
        mapper.m = system.mmap((&u8)(mapper.m), mapper.initial_size,
                               system.MMAP_PROT_READ | system.MMAP_PROT_WRITE,
                               system.MMAP_MAP_PRIVATE | system.MMAP_MAP_ANON,
                               -1, 0);
        %%io.stdout.write("Mapped :");
        %%io.stdout.printInt(@typeOf(mapper.m), mapper.m);
        %%io.stdout.write("/");
        const sz = hexPrintInt(usize, buf, mapper.m);
        %%io.stdout.write(buf[0...sz-1]);
        %%io.stdout.printf("\n");
        if ((mapper.m == 0) || (mapper.m == MMAP_FAILED)) {
            return error.NoMem;
        } else {
            mapper.total = mapper.initial_size;
            mapper.used = 0;
        }
    }

    fn deinit(mapper: &MmapAllocator) -> %void {
        // we will bomb if anything is in use
        system.munmap((&u8)(&mapper.m), mapper.total);
    }

    fn print(mapper: &MmapAllocator, stream: io.OutStream) -> %void {
        %%stream.printf("Mapped Memory\nAddress: ");
        var buf: [32]u8 = zeroes;
        %%io.stdout.printInt(@typeOf(mapper.m), mapper.m);
        %%io.stdout.write("/");
        const sz = hexPrintInt(usize, buf, mapper.m);
        %%io.stdout.write(buf[0...sz-1]);
        %%io.stdout.printf("\nUsed: ");
        %%io.stdout.printInt(@typeOf(mapper.used), mapper.used);
        %%io.stdout.write(", Total: ");
        %%io.stdout.printInt(@typeOf(mapper.used), mapper.used);
        %%io.stdout.printf("\n");
    }

    fn alloc(mapper: &MmapAllocator, n: usize) -> %[]u8 {
        const used = mapper.used;
        // do we have space left?
        if (n > mapper.total) {
            var buf: [32]u8 = zeroes;
            //%%io.stdout.printf("must realloc\n");
            // We might get another address back...
            const m = system.mmap((&u8)(mapper.m), n,
                                  system.MMAP_PROT_READ | system.MMAP_PROT_WRITE,
                                  system.MMAP_MAP_PRIVATE | system.MMAP_MAP_ANON,
                                  -1, 0);
            // %%io.stdout.write("Re Mapped :");
            // %%io.stdout.printInt(@typeOf(m), m);
            // %%io.stdout.write("/");
            // const sz = hexPrintInt(usize, buf, m);
            // %%io.stdout.write(buf[0...sz-1]);
            // %%io.stdout.printf("\n");
            if ((m == 0) || (m == MMAP_FAILED)) {
                return error.NoMem;
            }
            if (m < mapper.m) {  // realloc type thing
                // Seems to work on Linux x86_64
                // we seem to get a lower address, we can copy even if a wee bit expensive?
                // return error.NoMem;
                @memcpy((&u8)(m), (&u8)(mapper.m), used);
            } else {
                return error.NoMem;
            }
            mapper.m = m;
            mapper.total = n;
        }
        if ((mapper.m == 0) || (mapper.m == MMAP_FAILED)) {
            return error.NoMem;
        }
        mapper.used = n;
        var result: []u8 = undefined;
        result.ptr = (&u8)(mapper.m);
        result.len = n;
        return result;
    }

    fn realloc(mapper: &MmapAllocator, old_mem: []u8, new_size: usize) -> %[]u8 {
        const result = %return mapper.alloc(new_size);
        return result;
    }

    fn free(mapper: &MmapAllocator, old_mem: []u8) {
        // we cannot free yet, :(
        %%io.stdout.printf("cannot free\n");
    }
}

var local_mem: [2 * 1024 * 1024]u8 = undefined;
var local_mem_index: usize = 0;
var joker: MmapAllocator = undefined;

fn localAlloc(self: &mem.Allocator, n: usize) -> %[]u8 {
    switch (mallocator_kind) {
        STD => {
            const result = local_mem[local_mem_index ... local_mem_index + n];
            local_mem_index += n;
            return result;
        },
        JOKER => return joker.alloc(n),     // crowbarring joker into mem.Allocator
        JEMALLOC => {
            if (var v ?= malloc(n)) {
                var rv: []u8 = undefined;
                rv.ptr = (&u8)(v);
                rv.len = n;
                return rv;
            }
            return error.NoMem;
        },
        LIBALLOC => {
            if (var v ?= liballoc.malloc(n)) {
                var rv: []u8 = undefined;
                rv.ptr = (&u8)(v);
                rv.len = n;
                return rv;
            }
            return error.NoMem;
        },
    }
}

fn localRealloc(self: &mem.Allocator, old_mem: []u8, new_size: usize) -> %[]u8 {
    switch (mallocator_kind) {
        STD   => {
            const result = %return localAlloc(self, new_size);
            @memcpy(result.ptr, old_mem.ptr, old_mem.len);
            return result;

        },
        JOKER => return joker.realloc(old_mem, new_size),
        JEMALLOC => {
            if (old_mem.ptr == (&u8)(usize(0))) {
                var rv = localAlloc(self, new_size);
                return rv;
            }
            if (const v ?= realloc((&c_void)(old_mem.ptr), new_size)) {
                var rv: []u8 = undefined;
                rv.ptr = (&u8)(v);
                rv.len = new_size;
                return rv;
            }
            return error.NoMem;
        },
        LIBALLOC => {
            const v = liballoc.realloc(old_mem.ptr, new_size);
            if (const vv ?= v) {
                var rv: []u8 = undefined;
                rv.ptr = (vv);
                rv.len = new_size;
                return rv;
            }
            return error.NoMem;
        },
    }
}

fn localFree(self: &mem.Allocator, old_mem: []u8) {
    switch (mallocator_kind) {
        STD   => {},
        JOKER => return joker.free(old_mem),
        JEMALLOC => free((&c_void)(old_mem.ptr)),
        LIBALLOC => liballoc.free((&u8)(old_mem.ptr)),
    }
}

const UsizeList = list.List(usize);

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

pub fn main(args: [][] u8) -> %void {
    %%io.stdout.printf(args[0]);
    if (args.len > 1) {
        if (str.eql("joker", args[1])) {
            mallocator_kind = MallocKind.JOKER;
            %%io.stdout.printf(args[1]);
            %%io.stdout.printf("\n");
        } else if (str.eql("jemalloc", args[1])) {
            mallocator_kind = MallocKind.JEMALLOC;
            %%io.stdout.printf(args[1]);
            %%io.stdout.printf("\n");
        } else if (str.eql("liballoc", args[1])) {
            mallocator_kind = MallocKind.LIBALLOC;
            %%io.stdout.printf(args[1]);
            %%io.stdout.printf("\n");
        } else {
            mallocator_kind = MallocKind.STD;
            %%io.stdout.printf("standard\n");
        }
    }
    %%io.stdout.printf(" a malloc test program\n");
    if (mallocator_kind == MallocKind.JOKER) {
        // intialize the joker used by allocator
        %%joker.init();
        %%joker.print(io.stdout);
    }
    var ulst = UsizeList.init(&allocator);
    var i = usize(0);
    while (i < (1 << if (mallocator_kind == MallocKind.STD) usize(10) else usize(20)); i += 1) {
        %%ulst.append(i);
    }
    %%io.stdout.printf("\n");
    i = 0;
    %%io.stdout.printf("We have ");
    %%io.stdout.printInt(usize, ulst.len);
    %%io.stdout.printf(" entries in the list\n");
    while (i < ulst.len; i += 1) {
        if ((i < 32) || ((i & 0x1fff) == 0)) {
            %%io.stdout.printInt(usize, i);
            %%io.stdout.write(" -> ");
            %%io.stdout.printInt(usize, ulst.items[i]);
            %%io.stdout.printf("\n");
        }
        debug.assert(i == ulst.items[i]);
    }
    %%dump_proc_maps();
    if (mallocator_kind == MallocKind.JOKER) {
        %%joker.print(io.stdout);
        %%joker.deinit();
    }

    %%io.stdout.printf("false:");
    %%io.stdout.printInt(usize, usize(false));
    %%io.stdout.printf(", true:");
    %%io.stdout.printInt(usize, usize(true));
    %%io.stdout.printf("\n");
}
