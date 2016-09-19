// -*- mode:zig; -*-
const io = @import("std").io;
const mem = @import("std").mem;
const math = @import("std").math;
const Cmp = math.Cmp;

// foreign functions
extern fn fpconv_dtoa(fp: f64, dest: ?&u8) -> c_int;
extern fn atof(p: ?&const u8) -> f64;

// the "fast" atof() function, actually it's atod...
const fast_atof = @import("zfast_atof.zig");
const zfp = @import("zfpconv.zig");
const zfpconv_dtoa = zfp.zfpconv_dtoa;

const buildstyle = if (@compileVar("is_release")) "Release" else "Debug";

pub fn printNamedInt(n: var, name: []u8) -> %void {
    // TODO determine if const exprs are equal
    //    switch (@typeOf(n)) {
    //        u8, u16, u32, u64, usize, i8, i16, i32, i64, isize => {
    %%io.stdout.write(name);
    %%io.stdout.writeByte('=');
    %%io.stdout.printInt(@typeOf(n), n);
    %%io.stdout.printf("\n");
    //        },
    //        f32, f64 => {},
    //        else => {
    //            %%io.stdout.printf("unsupported type\n");
    //        },
    //    }
}

pub fn printSizedString(buf: []u8, sz: usize, stream: io.OutStream) -> %void {
    for (buf) |c, i| {
        if (i == sz) break;
        %%stream.writeByte(c);
    }
    %%stream.write(" (");
    %%stream.printInt(usize, sz);
    %%stream.printf(" bytes)\n");
}

fn reverseConvert(buf: [24]u8, sz: usize, value: f64) -> %void {
    var v: f64 = undefined;
    var nbuf: [24]u8 = undefined;
    buf[sz] = 0;
    v = %%fast_atof.zatod(buf);
    %%io.stdout.write("Converting with zatod ");
    %%printSizedString(buf, sz, io.stdout);
    var nsz: usize = zfpconv_dtoa(v, nbuf);
    %%printSizedString(nbuf, nsz, io.stdout);
    var cmp = mem.cmp(u8, buf[0...sz], nbuf[0...nsz]);
    %%io.stdout.printf(if (cmp == Cmp.Equal) "" else "NOT ");
    %%io.stdout.printf("equal\n---\n");
}

fn testConversion(value: f64) -> %void {
    var buf: [24]u8 = undefined;
    var cbuf: [24]u8 = zeroes;
    var sz = zfpconv_dtoa(value, buf);
    var v: c_int = fpconv_dtoa(value, &cbuf[0]);
    %%io.stdout.write("using fpconv_dtoa -> ");
    %%printSizedString(cbuf, usize(v), io.stdout);
    %%reverseConvert(cbuf, usize(v), value);
    %%io.stdout.write("using zfpconv_dtoa -> ");
    %%printSizedString(buf, usize(sz), io.stdout);
    %%reverseConvert(buf, sz, value);
}

pub fn main(args: [][] u8) -> %void {
    var buf: [24]u8 = undefined;
    var sz: usize = 0;

    %%testConversion(123.456);
    %%testConversion(-123.456);
    %%testConversion(-0.456e-9);
    %%testConversion(-10.0);
    %%testConversion(10.0);
    %%testConversion(0.1);
    %%testConversion(10e10);
    %%testConversion(10e138);
    %%testConversion(1000e-3);

    const test_iterations: usize = 10000000;
    var iterations: usize = 0;

    if (args.len == 1) {
        %%io.stderr.printf("Using Zig implementation, " ++ buildstyle
                           ++ " build, please wait...\n");
        { var n: f64 = 0.33;
            while (iterations < test_iterations; iterations += 1) {
                sz +%= zfpconv_dtoa(n, buf);
                n += 1.33;
            };
            %%printNamedInt(iterations, "zfpconv_dtoa iterations executed");
            %%printNamedInt(sz, "zfpconv_dtoa bytes produced");
        }
    }
    else {
        %%io.stderr.printf("Using C implementation, " ++ buildstyle
                           ++ " build, please wait...\n");
        { var n: f64 = 0.33; iterations=0;
            while (iterations < test_iterations; iterations += 1) {
                sz +%= usize(fpconv_dtoa(n, &buf[0]));
                n += 0.33;
            };
            %%printNamedInt(iterations, "fpconv_dtoa iterations executed");
            %%printNamedInt(sz, "fpconv_dtoa bytes produced");
        }
    }
}
