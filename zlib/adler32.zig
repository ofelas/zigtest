// -*- mode:zig; indent-tabs-mode:nil; comment-start:"// "; comment-end:""; -*-
///* adler32.c -- compute the Adler-32 checksum of a data stream
// * Copyright (C) 1995-2011, 2016 Mark Adler
// * For conditions of distribution and use, see copyright notice in zlib.h
// */

//#include "zutil.h"
//local uLong adler32_combine_ OF((uLong adler1, uLong adler2, z_off64_t len2));
pub const uLongf = u32;
pub const uLong  = u32;
pub const zSize = usize;
pub const ULONGF_MAX = @MaxValue(@typeOf(uLongf));
pub const Bytef = u8;
pub const zOffset = u32;
pub const zOffset64 = usize;

// #define BASE 65521U     /* largest prime smaller than 65536 *\/ */
// #define NMAX 5552 */
const BASE: u16 = 65521;
const NMAX: u16 = 5552;
// /* NMAX is the largest n such that 255n(n+1)/2 + (n+1)(BASE-1) <= 2^32-1 *\/ */

// #define DO1(buf,i)  {adler += (buf)[i]; sum2 += adler;} */
// #define DO2(buf,i)  DO1(buf,i); DO1(buf,i+1); */
// #define DO4(buf,i)  DO2(buf,i); DO2(buf,i+2); */
// #define DO8(buf,i)  DO4(buf,i); DO4(buf,i+4); */
// #define DO16(buf)   DO8(buf,0); DO8(buf,8); */

// /* use NO_DIVIDE if your processor does not do division in hardware -- */
//    try it both ways to see which is faster *\/ */
// #ifdef NO_DIVIDE */
// /* note that this assumes BASE is 65521, where 65536 % 65521 == 15 */
//    (thank you to John Reiser for pointing this out) *\/ */
// #  define CHOP(a) \ */
//     do { \ */
//         unsigned long tmp = a >> 16; \ */
//         a &= 0xffffUL; \ */
//         a += (tmp << 4) - tmp; \ */
//     } while (0) */
// #  define MOD28(a) \ */
//     do { \ */
//         CHOP(a); \ */
//         if (a >= BASE) a -= BASE; \ */
//     } while (0) */
// #  define MOD(a) \ */
//     do { \ */
//         CHOP(a); \ */
//         MOD28(a); \ */
//     } while (0) */
// #  define MOD63(a) \ */
//     do { /* this assumes a is not negative *\/ \ */
//         z_off64_t tmp = a >> 32; \ */
//         a &= 0xffffffffL; \ */
//         a += (tmp << 8) - (tmp << 5) + tmp; \ */
//         tmp = a >> 16; \ */
//         a &= 0xffffL; \ */
//         a += (tmp << 4) - tmp; \ */
//         tmp = a >> 16; \ */
//         a &= 0xffffL; \ */
//         a += (tmp << 4) - tmp; \ */
//         if (a >= BASE) a -= BASE; \ */
//     } while (0) */
// #else */
// #  define MOD(a) a %= BASE */
// #  define MOD28(a) a %= BASE */
// #  define MOD63(a) a %= BASE */
// #endif */

inline fn MOD(v: uLong) uLong {
    return v % BASE;
}

inline fn MOD28(v: uLong) uLong {
    return v % BASE;
}

//* ========================================================================= */
inline fn adler32_z(padler: uLong, buf: []const Bytef) uLong {
    var len = buf.len;
    var i: usize = 0;
    var adler = padler; // make a local working copy

    //* split Adler-32 into component sums */
    var sum2: uLong = (adler >> 16) & 0xffff;
    adler &= 0xffff;

    //* in case user likes doing a byte at a time, keep it fast */
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

    //* initial Adler-32 value (deferred check for len == 1 speed) */
    if (len == 0) {
        return uLongf(1);
    }

    //* in case short lengths are provided, keep it somewhat fast */
    if (len < 16) {
        while (len > 0) : (len -= 1) {
            adler += (buf)[i];
            i += 1;
            sum2 += adler;
        }
        if (adler >= BASE) {
            adler -= BASE;
        }
        sum2 %= BASE;            //* only added so many BASE's */
        return (adler | (sum2 << 16));
    }

    //* do length NMAX blocks -- requires just one modulo operation */
    while (len >= NMAX) {
        len -= NMAX;
        var n = NMAX / 16;          //* NMAX is divisible by 16 */
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

    //* do remaining bytes (less than NMAX, still just one modulo) */
    if (len > 0) {                  //* avoid modulos if none remaining */
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

    //* return recombined sums */
    return (adler | (sum2 << 16));
}

//* ========================================================================= */
/// Update an adler32 checksum.
///
pub fn adler32(adler: uLong, buf: []const Bytef) uLong {
    return adler32_z(adler, buf);
}

// @ofelas: untested combine functions...
//* ========================================================================= */
fn adler32_combine_(adler1: uLong, adler2: uLong, len2: zOffset64) uLong
{
    sum1: uLong = undefined;
    sum2: uLong = undefined;
    rem: uLong = undefined;

    //* for negative len, return invalid adler32 as a clue for debugging */
    if (len2 < 0) {
        return ULONGF_MAX;
    }

    //* the derivation of this formula is left as an exercise for the reader */
    MOD63(len2);                //* assumes len2 >= 0 */
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

//* ========================================================================= */
pub fn adler32_combine(adler1: uLong, adler2: uLong, len2: zOffset) uLong {
    return adler32_combine_(adler1, adler2, len2);
}

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
    };
    warn("\n");

    for (adler32tests) |item| {
        var res = adler32(1, item.msg[0..]);
        if (res != item.res) {
            warn("Oh, crap...\n");
        } else {
            warn("{}, {x08} == {x08}\n", item.msg, item.res, res);
        }
        assert(res == item.res);
    }
}
