// -*- indent-tabs-mode:nil; -*-
const system = switch(@compileVar("os")) {
    linux => @import("std").linux,
    darwin => @import("std").darmin,
    else => @compileError("Unsupported OS"),
};
const debug = @import("std").debug;
const io = @import("std").io;
const mem = @import("std").mem;
const Allocator = mem.Allocator;

const assert = debug.assert;

const securehash = @import("securehash.zig");
const sha1 = securehash.sha1;

// 16 MiB -> crash ok, need to allocate this memory
var buf: [16 * 1024 * 1024]u8 = zeroes; // undefined?


pub fn main(args: [][] u8) -> %void {
    //    var allocator: &Allocator;

    var s = "a93tgj0p34jagp9[agjp98ajrhp9aej]";
    //var s = "// 180.199.169.163.148.28.89.96.9.167.88.167.177.136.239.86.138.82.229.6.";
    const ref = "b4c7a9a3941c596009a758a7b188ef568a52e506";
    %%io.stdout.write("testing sha1 on '");
    %%io.stdout.write(s);
    %%io.stdout.printf("'\n");
    var h: securehash.Sha1Digest = undefined;
    %%sha1(s, s.len, h);
    for (h) |v| {
        %%io.stdout.printInt(@typeOf(v), v);
        %%io.stdout.write(".");
    }
    var d: [securehash.Sha1DigestSize * 2]u8 = zeroes;
    securehash.hexdigest(h, d);
    %%io.stdout.write(", hash len=");
    %%io.stdout.printInt(usize, h.len);
    %%io.stdout.printf("\n");
    %%io.stdout.write("digest len=");
    %%io.stdout.printInt(usize, d.len);
    %%io.stdout.write(", '");
    %%io.stdout.write(d);
    %%io.stdout.printf("'\n");
    %%io.stdout.printf("sha1 test done\n");
    %%io.stdout.printf(ref ++ "\n");
    %%io.stdout.printf("// 180.199.169.163.148.28.89.96.9.167.88.167.177.136.239.86.138.82.229.6.\n");
    //assert(d == ref);

    for (args[1...]) |arg, i| {
        var is: io.InStream = undefined;
        is.open(arg) %% |err| {
            %%io.stderr.printf("Unable to open file: ");
            %%io.stderr.printf(@errorName(err));
            %%io.stderr.printf("\n");
            return err;
        }; //else {
        //defer %%is.close();
        const fsz = %%is.getEndPos();
        // pub fn mmap(address: ?&u8, length: usize, prot: usize, flags: usize, fd: i32, offset: usize)
        var m = system.mmap(null, fsz, system.MMAP_PROT_READ, system.MMAP_MAP_ANON, is.fd, 0);
        const sz = is.read(buf) %% |err| {
            %%io.stderr.write("Unable to read file: ");
            %%io.stderr.write(@errorName(err));
            %%io.stderr.printf("\n");
            return err;
        };
        %%io.stdout.write("testing sha1 on file '");
        %%io.stdout.write(arg);
        %%io.stdout.write("', mmap=");
        %%io.stdout.printInt(usize, m);
        %%io.stdout.write(", ");
        %%io.stdout.printInt(usize, fsz);
        %%io.stdout.write(", ");
        %%io.stdout.printInt(usize, sz);
        %%io.stdout.printf(" bytes\n");
        //system.munmap((&u8)(&m), fsz);
        is.close() %% |err| {
            %%io.stderr.write("Unable to close file: ");
            %%io.stderr.write(@errorName(err));
            %%io.stderr.printf("\n");
            return err;
        };
        h = zeroes;
        // ((&const x)[0...1])
        %%securehash.sha1(buf, sz, h);
        d = zeroes;
        securehash.hexdigest(h, d);
        %%io.stdout.write(d);
        %%io.stdout.printf("\n");
    }

}

// 0x00000000004005c6 <+1238>:	vmovaps %ymm0,0x80(%rsp)
// echo -n "a93tgj0p34jagp9[agjp98ajrhp9aej]" | openssl sha1
// (stdin)= b4c7a9a3941c596009a758a7b188ef568a52e506
// Nim, Hash=B4C7A9A3941C596009A758A7B188EF568A52E506
// 180.199.169.163.148.28.89.96.9.167.88.167.177.136.239.86.138.82.229.6.
// 3032983971 B4C7A9A3
// 2484885856 941C5960
//  161962151 09A758A7
// 2978541398 B188EF56
// 2320688390 8A52E506
// 0.3387418777|1.2964496570|2.3717280049|3.427548097|4.1657473006
// finally zig: digest len=40, 'b4c7a9a3941c596009a758a7b188ef568a52e506'
//                              b4c7a9a3941c596009a758a7b188ef568a52e506