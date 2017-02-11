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

pub fn printSizedString(buf: []u8, sz: usize, stream: io.OutStream) -> %void {
    // cannot printf to const OutStream
    var s = stream;
    for (buf) |c, i| {
        if (i == sz) break;
        %%s.writeByte(c);
    }
    %%s.printf(" ({} bytes)", sz);
}

fn reverseConvert(buf: zfp.BUFTYPE, sz: usize, value: f64) -> %void {
    var v: f64 = undefined;
    var nbuf: [24]u8 = undefined;
    buf[sz] = 0;
    v = %%fast_atof.zatod(buf);
    const nsz: usize = zfpconv_dtoa(v, nbuf);
    const cmp = mem.cmp(u8, buf[0...sz], nbuf[0...nsz]);
    %%io.stdout.printf("R Converting with zatod '{}' ({} bytes) => '{}' ({} bytes)\n",
                       buf, sz, nbuf, nsz);
    // Why must these arguments have the same size?
    // error: incompatible types: '[0]u8' and '[4]u8'
    %%io.stdout.printf("{}equal X\n---\n", if (cmp == Cmp.Equal) "    " else "NOT ");
}

fn testConversion(value: f64) -> %void {
    var buf: [24]u8 = undefined;
    var cbuf: [24]u8 = []u8{0} ** 24;
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
            %%io.stdout.printf("zfpconv_dtoa iterations executed={}\n", iterations);
            %%io.stdout.printf("zfpconv_dtoa bytes produced={}\n", sz);
        }
    }
    else {
        %%io.stderr.printf("Using C implementation, {} build, please wait...\n", buildstyle);
        { var n: f64 = 0.33; iterations=0;
            while (iterations < test_iterations; iterations += 1) {
                sz +%= usize(fpconv_dtoa(n, &buf[0]));
                n += 0.33;
            };
            %%io.stdout.printf("fpconv_dtoa iterations executed={}\n", iterations);
            %%io.stdout.printf("fpconv_dtoa bytes produced={}\n", sz);
        }
    }
}
