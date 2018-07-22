// -*- mode:zig; indent-tabs-mode:nil; -*-
// adler32.c -- compute the Adler-32 checksum of a data stream
// Copyright (C) 1995-2011, 2016 Mark Adler
// For conditions of distribution and use, see copyright notice in zlib.h
//

pub const uLongf = u32;
pub const uLong  = u32;
pub const zSize = usize;
pub const ULONGF_MAX = @MaxValue(@typeOf(uLongf));
pub const Bytef = u8;
pub const zOffset = u32;
pub const zOffset64 = usize;

/// largest prime smaller than 65536
const BASE: u16 = 65521;
/// NMAX is the largest n such that 255n(n+1)/2 + (n+1)(BASE-1) <= 2^32-1
const NMAX: u16 = 5552;

inline fn MOD(v: uLong) uLong {
    return v % BASE;
}

// adler32 inner function
inline fn adler32_z(padler: uLong, buf: []const Bytef) uLong {
    var len = buf.len;
    var i: usize = 0;
    var adler = padler; // make a local working copy

    // split Adler-32 into component sums
    var sum2: uLong = (adler >> 16) & 0xffff;
    adler &= 0xffff;

    // in case user likes doing a byte at a time, keep it fast
    if (len == 1) {
        adler += (buf)[0];
        if (adler >= BASE) {
            adler -= BASE;
        }
        sum2 += adler;
        if (sum2 >= BASE) {
            sum2 -= BASE;
        }
        return (adler | (sum2 << 16));
    }

    // initial Adler-32 value (deferred check for len == 1 speed)
    if (len == 0) {
        return uLongf(1);
    }

    // in case short lengths are provided, keep it somewhat fast
    if (len < 16) {
        while (len > 0) : (len -= 1) {
            adler += (buf)[i];
            i += 1;
            sum2 += adler;
        }
        if (adler >= BASE) {
            adler -= BASE;
        }
        sum2 %= BASE;            // only added so many BASE's
        return (adler | (sum2 << 16));
    }

    // do length NMAX blocks -- requires just one modulo operation
    while (len >= NMAX) {
        len -= NMAX;
        var n = NMAX / 16;          // NMAX is divisible by 16
        while (n > 0) : (n -= 1) {
            comptime var iter = 0;
            inline while (iter < 16) : (iter += 1) {
                    adler += (buf)[i];
                    i += 1;
                    sum2 += adler;
                }
        }
        adler %= BASE;
        sum2 %= BASE;
    }

    // do remaining bytes (less than NMAX, still just one modulo)
    if (len > 0) {                  // avoid modulos if none remaining
        while (len >= 16) {
            len -= 16;
            comptime var iter = 0;
            inline while (iter < 16) : (iter += 1) {
                adler += (buf)[i];
                i += 1;
                sum2 += adler;
            }
        }
        while (len > 0) : (len -= 1) {
            //adler += *buf++; // }
            adler += (buf)[i];
            i += 1;
            sum2 += adler;
        }
        adler %= BASE;
        sum2 %= BASE;
    }

    // return recombined sums
    return (adler | (sum2 << 16));
}

/// Update an adler32 checksum.
pub fn adler32(adler: uLong, buf: []const Bytef) uLong {
    return adler32_z(adler, buf);
}

/// @ofelas: untested combine functions...
fn adler32_combine_(adler1: uLong, adler2: uLong, len2: zOffset64) uLong
{
    sum1: uLong = undefined;
    sum2: uLong = undefined;
    rem: uLong = undefined;

    // for negative len, return invalid adler32 as a clue for debugging 
    if (len2 < 0) {
        return ULONGF_MAX;
    }

    // the derivation of this formula is left as an exercise for the reader
    MOD63(len2);                // assumes len2 >= 0
    rem = uLong(len2);
    sum1 = adler1 & 0xffff;
    sum2 = rem * sum1;
    MOD(sum2);
    sum1 += (adler2 & 0xffff) + BASE - 1;
    sum2 += ((adler1 >> 16) & 0xffff) + ((adler2 >> 16) & 0xffff) + BASE - rem;
    if (sum1 >= BASE) sum1 -= BASE;
    if (sum1 >= BASE) sum1 -= BASE;
    if (sum2 >= (uLong(BASE) << 1)) sum2 -= (ulong(BASE) << 1);
    if (sum2 >= BASE) sum2 -= BASE;
    return (sum1 | (sum2 << 16));
}

/// doc
pub fn adler32_combine(adler1: uLong, adler2: uLong, len2: zOffset) uLong {
    return adler32_combine_(adler1, adler2, len2);
}

/// doc
pub fn adler32_combine64(adler1: uLong, adler2: uLong, len2: zOffset64) uLong {
    return adler32_combine_(adler1, adler2, len2);
}

test "adler32 main exported function" {
    const warn = @import("std").debug.warn;
    const assert = @import("std").debug.assert;

    const TEST = struct {msg: []const u8, res: uLong};
    const adler32tests = []TEST {
        TEST {.msg = "hello", .res = 0x62c0215},
        TEST {.msg = "The quick brown fox jumps over the lazy dog", .res = 0x5bdc0fda},
        TEST {.msg = "", .res = 1},
    };
    warn("\n");

    for (adler32tests) |item| {
        var res: uLong = 0;
        if (item.msg.len > 6) {
            // two step
            res = adler32(1, item.msg[0..6]);
            res = adler32(res, item.msg[6..]);
        } else {
            // one step
            res = adler32(1, item.msg[0..]);
        }
        if (res != item.res) {
            warn("Oh, crap...{x08} != {x08}\n", item.res, res);
        }
        assert(res == item.res);
    }
}
