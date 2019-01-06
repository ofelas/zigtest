// -*- mode:zig; -*-
const builtin = @import("builtin");
const std = @import("std");
const io = std.io;
const mem = std.mem;
const math = std.math;
const Cmp = math.Cmp;
const os = std.os;
const warn = std.debug.warn;

const isDebug = !release_fast and !release_safe;

// foreign functions
extern fn fpconv_dtoa(fp: f64, dest: ?*u8) c_int;
extern fn atof(p: ?*const u8) f64;

// the "fast" atof() function, actually it's atod...
const fast_atof = @import("zfast_atof.zig");
const zfp = @import("zfpconv.zig");
const zfpconv_dtoa = zfp.zfpconv_dtoa;

const buildstyle = if (builtin.mode ==   builtin.Mode.Debug) "Debug" else "Release";

fn reverseConvert(buf: *zfp.BUFTYPE, sz: usize, value: f64) !void {
    var v: f64 = undefined;
    var nbuf: [24]u8 = undefined;
    buf.*[sz] = 0;
    v = try fast_atof.zatod(buf[0..sz]);
    const nsz: usize = zfpconv_dtoa(v, &nbuf);
    //const cmp = mem.cmp(u8, buf[0..sz], nbuf[0..nsz]);
    warn("R Converting with zatod '{}' ({} bytes) => '{}' ({} bytes)\n",
                       buf[0..], sz, nbuf[0..], nsz);
    // Why must these arguments have the same size?
    // error: incompatible types: '[0]u8' and '[4]u8'
    //warn("{}equal X\n---\n", if (cmp == Cmp.Equal) "    " else "NOT ");
}

fn testConversion(value: f64) !void {
    var buf: [24]u8 = undefined;
    var cbuf: [24]u8 = []u8{0} ** 24;
    var lval = value;

    var sz = zfpconv_dtoa(value, &buf);
    warn("zig='{}' using zfpconv_dtoa -> '{}'\n", value, buf[0..sz]);
    try reverseConvert(&buf, sz, value);

    // C version
    var v: c_int = fpconv_dtoa(value, &cbuf[0]);
    warn("zig='{}' using fpconv_dtoa -> '{}'\n", value, cbuf[0..usize(@intCast(u32, v))]);
    try reverseConvert(&cbuf, usize(@intCast(u32, v)), value);
}

const FloatClass = enum {
    FP_NORMAL,
    FP_ZERO,
    FP_SUBNORMAL,
    FP_INFINITE,
    FP_NAN,
};

pub fn fpclassify(f: var) FloatClass {
    const T = @typeOf(f);
    switch (T) {
        f32 => return FloatClass.FP_NORMAL,
        f64 => {
            const bits = @bitCast(u64, f) & (std.math.maxInt(u64) >> 1);
            if (bits == (u64(0x7FF) << 52)) {
                return FloatClass.FP_INFINITE;
            } else if (bits > (u64(0x7FF) << 52)) {
                return FloatClass.FP_NAN;
            } //else if (bits < (u64(0x7FF) << 52))
            if ((bits + (1 << 52)) >= (1 << 53)) {
                return FloatClass.FP_NORMAL;
            }
            else if (bits == 0) {
                return FloatClass.FP_ZERO;
            }
            return FloatClass.FP_SUBNORMAL;
        },
        else => {
            @compileError("isNormal not implemented for " ++ @typeName(T));
        },
    }
}

pub fn main() !void {
    var buf: [24]u8 = undefined;
    var sz: usize = 0;

    try testConversion(123.456);
    try testConversion(-123.456);
    try testConversion(-0.456e-9);
    try testConversion(-10.0);
    try testConversion(10.0);
    try testConversion(0.1);
    try testConversion(10e10);
    try testConversion(10e138);
    try testConversion(1000e-3);

    const test_iterations: usize = 10000000;
    var iterations: usize = 0;

    var args = os.ArgIterator.init();
    _ = args.skip();

    if (args.next(std.debug.global_allocator)) |arg| {
       warn("Using Zig implementation, " ++ buildstyle ++ " build, please wait...\n");
        { var n: f64 = 0.33;
            while (iterations < test_iterations) : (iterations += 1) {
                sz +%= zfpconv_dtoa(n, &buf);
                n += 1.33;
            }
            warn("zfpconv_dtoa iterations executed={}\n", iterations);
            warn("zfpconv_dtoa bytes produced={}\n", sz);
        }
    }
    else {
        warn("Using C implementation, {} build, please wait...\n", buildstyle);
        { var n: f64 = 0.33; iterations=0;
            while (iterations < test_iterations) : (iterations += 1) {
                sz +%= @intCast(u32, fpconv_dtoa(n, &buf[0]));
                n += 0.33;
            }
            warn("fpconv_dtoa iterations executed={}\n", iterations);
            warn("fpconv_dtoa bytes produced={}\n", sz);
        }
    }

    // 0x1.8d00000000000p+5 = 0xC.68p+2 = 49.625, 
    var f: f64 = math.nan_f64;
    var fc = @inlineCall(fpclassify, f);
    var u = @bitCast(u64, f);
    warn("{} {} {}\n", fc, f, u);
    f = math.inf_f64; 
    fc = @inlineCall(fpclassify, f);
    warn("{} {}\n", fc, f);
    f = 1.33;
    while (f > 0.0) {
        u = @bitCast(u64, f);
        fc = fpclassify(f);
        const nsz: usize = zfpconv_dtoa(f, &buf);
        warn("{} {} {} {x16}\n", fc, f, buf[0..nsz], u);
        switch (fc) {
            FloatClass.FP_NORMAL => std.debug.assert(math.isNormal(f) == true),
            FloatClass.FP_SUBNORMAL => std.debug.assert(math.isNormal(f) == false),
            else => {},
        }
        f /= 2.0;
    }
    f = 0.0;
    u = @bitCast(u64, f);
    fc = fpclassify(f);
    warn("{} {} {x16}\n", fc, f, u);
    f = -0.1e-306;
    u = @bitCast(u64, f);
    warn("{} {} {x16}\n", fpclassify(f), f, u);
}
