// -*- mode:zig; -*-
const system = switch(@compileVar("os")) {
    linux => @import("std").linux,
    darwin => @import("std").darmin,
    else => @compileError("Unsupported OS"),
};
const debug = @import("std").debug;
const io = @import("std").io;
const mem = @import("std").mem;

const assert = debug.assert;

const securehash = @import("securehash.zig");
const sha1 = securehash.sha1;

// 2 MiB -> ok, need to allocate this memory (crashes if in function and too large)
var databuf: [2 << 20]u8 = undefined; // zeroes?

fn contextTester(data: []u8, sz: usize) {
    var h: [securehash.Sha1DigestSize]securehash.Sha1Digest = zeroes;
    var d: [securehash.Sha1HexDigestSize]u8 = zeroes;
    var sha1ctx: securehash.Sha1Context = undefined;

    // %%io.stdout.printInt(usize, sz);
    // %%io.stdout.printf(" bytes\n");
    sha1ctx.init();
    // 1) feed it 1 byte at the time
    // for (data) |b, i| {if (i >= sz) break; sha1ctx.update(data[i...], 1);}
    // 2) feed it twice
    // sha1ctx.update(data, 10);
    // sha1ctx.update(data[10...], sz - 10);
    // 3) or all at once...which is the one working at the moment
    sha1ctx.update(data, sz);
    sha1ctx.final(h);
    for (h) |v| {
        %%io.stdout.printInt(@typeOf(v), v);
        %%io.stdout.write(".");
    }
    %%io.stdout.printf("\n");
    securehash.hexdigest(h, d);
    %%io.stdout.write(d);
    %%io.stdout.printf("\n");
}

fn sha1Tester(data: []u8, sz: usize) {
    var h: [securehash.Sha1DigestSize]securehash.Sha1Digest = undefined;
    var d: [securehash.Sha1HexDigestSize]u8 = zeroes;
    %%sha1(data, sz, h);
    for (h) |v| {
            %%io.stdout.printInt(@typeOf(v), v);
            %%io.stdout.write(".");
        }
    securehash.hexdigest(h, d);
    %%io.stdout.write(", hash len=");
    %%io.stdout.printInt(usize, h.len);
    %%io.stdout.printf("\n");
    %%io.stdout.write("digest len=");
    %%io.stdout.printInt(usize, d.len);
    %%io.stdout.write(", '");
    %%io.stdout.write(d);
    %%io.stdout.printf("'\n");
}

pub fn main(args: [][] u8) -> %void {
    var h: [securehash.Sha1DigestSize]securehash.Sha1Digest = undefined;
    var d: [securehash.Sha1HexDigestSize]u8 = zeroes;

    if (args.len < 2) {
        var s = "a93tgj0p34jagp9[agjp98ajrhp9aej]";
        var x = "Important message for all Zig programmers! Please visit: http://ziglang.org/";
        const sref = "b4c7a9a3941c596009a758a7b188ef568a52e506";
        const xref = "0e958e40f7724852664c358118a20a018b83b760";
        %%io.stdout.printf(sref ++ " <- reference s\n");
        %%io.stdout.write("testing sha1 on '");
        %%io.stdout.write(s);
        %%io.stdout.printf("'\n");
        contextTester(s, s.len);
        sha1Tester(s, s.len);
        %%io.stdout.printf(xref ++ " <- reference x\n");
        %%io.stdout.write("testing sha1 on '");
        %%io.stdout.write(x);
        %%io.stdout.printf("'\n");
        // crikes, this fails...
        contextTester(x, x.len);
        sha1Tester(x, x.len);
        %%io.stdout.printf("sha1 test done\n");
    } else {
        for (args[1...]) |arg, i| {
            var input: io.InStream = undefined;
            input.open(arg) %% |err| {
                %%io.stderr.printf("Unable to open file: ");
                %%io.stderr.printf(@errorName(err));
                %%io.stderr.printf("\n");
                return err;
            }; //else {
            //defer %%input.close();
            const fsz = %%input.getEndPos();
            var m = system.mmap(null, fsz, system.MMAP_PROT_READ|system.MMAP_PROT_WRITE,
                                system.MMAP_MAP_PRIVATE|system.MMAP_MAP_ANON, input.fd, 0);
            // %%io.stdout.write("m=");
            // %%io.stdout.printInt(@typeOf(m), m);
            // %%io.stdout.printf("\n");
            const sz = input.read(databuf) %% |err| {
                %%io.stderr.write("Unable to read file: ");
                %%io.stderr.write(@errorName(err));
                %%io.stderr.printf("\n");
                return err;
            };
            h = zeroes;
            d = zeroes;
            %%securehash.sha1(databuf, fsz, h);
            securehash.hexdigest(h, d);
            %%io.stdout.write(d);
            %%io.stdout.write("  ");
            %%io.stdout.write(arg);
            %%io.stdout.write("  # ");
            %%io.stdout.printInt(usize, fsz);
            %%io.stdout.write(" bytes");
            %%io.stdout.printf("\n");
            system.munmap((&u8)(&m), fsz);
            input.close() %% |err| {
                %%io.stderr.write("Unable to close file: ");
                %%io.stderr.write(@errorName(err));
                %%io.stderr.printf("\n");
                return err;
            };
        }
    }

}
