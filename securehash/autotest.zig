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

pub fn main(args: [][] u8) -> %void {
    var h: [securehash.Sha1DigestSize]securehash.Sha1Digest = undefined;
    var d: [securehash.Sha1DigestSize * 2]u8 = zeroes;

    if (args.len < 2) {
        var s = "a93tgj0p34jagp9[agjp98ajrhp9aej]";
        const ref = "b4c7a9a3941c596009a758a7b188ef568a52e506";
        %%io.stdout.write("testing sha1 on '");
        %%io.stdout.write(s);
        %%io.stdout.printf("'\n");
        %%sha1(s, s.len, h);
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
        %%io.stdout.printf("sha1 test done\n");
        %%io.stdout.printf(ref ++ "\n");
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
            //var m = system.mmap(null, fsz, system.MMAP_PROT_READ, system.MMAP_MAP_ANON, input.fd, 0);
            const sz = input.read(databuf) %% |err| {
                %%io.stderr.write("Unable to read file: ");
                %%io.stderr.write(@errorName(err));
                %%io.stderr.printf("\n");
                return err;
            };
            //system.munmap((&u8)(&m), fsz);
            input.close() %% |err| {
                %%io.stderr.write("Unable to close file: ");
                %%io.stderr.write(@errorName(err));
                %%io.stderr.printf("\n");
                return err;
            };
            h = zeroes;
            d = zeroes;
            %%securehash.sha1(databuf, sz, h);
            securehash.hexdigest(h, d);
            %%io.stdout.write(d);
            %%io.stdout.write("  ");
            %%io.stdout.write(arg);
            %%io.stdout.write("  # ");
            %%io.stdout.printInt(usize, fsz);
            %%io.stdout.write(" bytes");
            %%io.stdout.printf("\n");
        }
    }

}
