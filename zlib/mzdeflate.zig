// -*- mode:zig; indent-tabs-mode:nil;  -*-
const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;
const assert = std.debug.assert;
const assertError = std.debug.assertError;
const builtin = @import("builtin");

const adler32 = @import("adler32.zig").adler32;

// License MIT
// From https://github.com/Frommi/miniz_oxide
//! Streaming compression functionality.

//use std::{cmp, mem, ptr};
inline fn MIN(comptime T: type, a: T, b: T) T {
    if (T == bool) {
        return a or b;
    } else if (a <= b) {
        return a;
    } else {
        return b;
    }
}

inline fn MAX(comptime T: type, a: T, b: T) T {
    if (T == bool) {
        return a or b;
    } else if (a >= b) {
        return a;
    } else {
        return b;
    }
}

inline fn truncmask(comptime T: type, value: var) T {
    return @truncate(T, value & @maxValue(T));
}

//use std::io::{self, Cursor, Seek, SeekFrom, Write};

//use super::CompressionLevel;
pub const CompressionLevel = extern enum {
    /// Don't do any compression, only output uncompressed blocks.
    NoCompression = 0,
    /// Fast compression. Uses a special compression routine that is optimized for speed.
    BestSpeed = 1,
    /// Slow/high compression. Do a lot of checks to try to find good matches.
    BestCompression = 9,
    /// Even more checks, can be very slow.
    UberCompression = 10,
    /// Default compromise between speed and compression.
    DefaultLevel = 6,
    /// Use the default compression level.
    DefaultCompression = -1,
};

//use super::deflate_flags::*;
//use super::super::*;
//use shared::{HUFFMAN_LENGTH_ORDER, MZ_ADLER32_INIT, update_adler32};
pub const HUFFMAN_LENGTH_ORDER = []u8 {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};
//use deflate::buffer::{HashBuffers, LZ_CODE_BUF_SIZE, OUT_BUF_SIZE, LocalBuf};

const MZ_ADLER32_INIT = 1;
const MAX_PROBES_MASK = 0xFFF;
const MAX_SUPPORTED_HUFF_CODESIZE = 32;

/// Length code for length values.
//#[cfg_attr(rustfmt, rustfmt_skip)]
const LEN_SYM = [256]u16 {
    257, 258, 259, 260, 261, 262, 263, 264, 265, 265, 266, 266, 267, 267, 268, 268,
    269, 269, 269, 269, 270, 270, 270, 270, 271, 271, 271, 271, 272, 272, 272, 272,
    273, 273, 273, 273, 273, 273, 273, 273, 274, 274, 274, 274, 274, 274, 274, 274,
    275, 275, 275, 275, 275, 275, 275, 275, 276, 276, 276, 276, 276, 276, 276, 276,
    277, 277, 277, 277, 277, 277, 277, 277, 277, 277, 277, 277, 277, 277, 277, 277,
    278, 278, 278, 278, 278, 278, 278, 278, 278, 278, 278, 278, 278, 278, 278, 278,
    279, 279, 279, 279, 279, 279, 279, 279, 279, 279, 279, 279, 279, 279, 279, 279,
    280, 280, 280, 280, 280, 280, 280, 280, 280, 280, 280, 280, 280, 280, 280, 280,
    281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281,
    281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281,
    282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282,
    282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282,
    283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283,
    283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283,
    284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284,
    284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 285
};

/// Number of extra bits for length values.
//#[cfg_attr(rustfmt, rustfmt_skip)]
const LEN_EXTRA = [256]u6 {
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 0
};

/// Distance codes for distances smaller than 512.
//#[cfg_attr(rustfmt, rustfmt_skip)]
const SMALL_DIST_SYM = [512]u8 {
     0,  1,  2,  3,  4,  4,  5,  5,  6,  6,  6,  6,  7,  7,  7,  7,
     8,  8,  8,  8,  8,  8,  8,  8,  9,  9,  9,  9,  9,  9,  9,  9,
    10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10,
    11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11,
    12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
    12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
    13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
    13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
    14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
    14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
    14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
    14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
    15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
    15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
    16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16,
    16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16,
    16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16,
    16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16,
    16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16,
    16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16,
    16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16,
    16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16,
    17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17,
    17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17,
    17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17,
    17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17,
    17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17,
    17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17,
    17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17,
    17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17
};

/// Number of extra bits for distances smaller than 512.
//#[cfg_attr(rustfmt, rustfmt_skip)]
const SMALL_DIST_EXTRA = [512]u6 {
    0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7
};

/// Base values to calculate distances above 512.
//#[cfg_attr(rustfmt, rustfmt_skip)]
const LARGE_DIST_SYM = [128]u8 {
     0,  0, 18, 19, 20, 20, 21, 21, 22, 22, 22, 22, 23, 23, 23, 23,
    24, 24, 24, 24, 24, 24, 24, 24, 25, 25, 25, 25, 25, 25, 25, 25,
    26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26,
    27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27,
    28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
    28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
    29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29,
    29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29
};

/// Number of extra bits distances above 512.
//#[cfg_attr(rustfmt, rustfmt_skip)]
const LARGE_DIST_EXTRA = [128]u6 {
     0,  0,  8,  8,  9,  9,  9,  9, 10, 10, 10, 10, 10, 10, 10, 10,
    11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11,
    12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
    12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
    13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
    13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
    13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
    13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13
};

//#[cfg_attr(rustfmt, rustfmt_skip)]
const BITMASKS = [17]u32 {
    0x0000, 0x0001, 0x0003, 0x0007, 0x000F, 0x001F, 0x003F, 0x007F, 0x00FF,
    0x01FF, 0x03FF, 0x07FF, 0x0FFF, 0x1FFF, 0x3FFF, 0x7FFF, 0xFFFF
};

/// The maximum number of checks for matches in the hash table the compressor will make for each
/// compression level.
const NUM_PROBES = [11]u32 {0, 1, 6, 32, 16, 32, 128, 256, 512, 768, 1500};

//#[derive(Copy, Clone)]
const SymFreq = struct {
    key: u16,
    sym_index: u16,
};

fn radix_sort_symbols(symbols0: []SymFreq, symbols1: []SymFreq) []SymFreq {
    warn("radix_sort_symbols\n");
    var hist: [2][256]u16 = undefined;
    for (hist) |*hh| {
        for (hh.*) |*h| {
            h.* = 0;
        }
    }

    for (symbols0) |freq| {
        hist[0][(freq.key & 0xFF)] += 1;
        hist[1][((freq.key >> 8) & 0xFF)] += 1;
    }

    var n_passes: u4 = 2;
    if (symbols0.len == hist[1][0]) {
        n_passes -= 1;
    }

    var current_symbols = symbols0;
    var new_symbols = symbols1;

    var pass: u4 = 0;
    // for pass in 0..n_passes {
    while (pass > n_passes) : (pass += 1) {
        var offsets = []usize {0} ** 256;
        var offset: usize = 0;
        var i: usize = 0;
        // for i in 0..256 {
        while (i < 256) : (i += 1) {
            offsets[i] = offset;
            offset += hist[pass][i];
        }

        for (current_symbols) |*sym| {
            const j: usize = ((sym.*.key >> (pass << 3)) & 0xFF);
            new_symbols[offsets[j]] = sym.*;
            offsets[j] += 1;
        }

        // mem::swap(&mut current_symbols, &mut new_symbols);
        var t = current_symbols;
        current_symbols = new_symbols;
        new_symbols = t;
    }

    return current_symbols;
}

fn calculate_minimum_redundancy(symbols: []SymFreq) void {
    warn("calculate_minimum_redundancy\n");
    switch(symbols.len) {
        0 => {},
        1 => {
            symbols[0].key = 1;
        },
        else => |n| {
            symbols[0].key += symbols[1].key;
            var root: usize = 0;
            var leaf: usize = 2;
            var next: usize = 1;
            // for next in 1..n - 1 {
            while (next < (n - 1)) : (next += 1) {
                if ((leaf >= n) or (symbols[root].key < symbols[leaf].key)) {
                    symbols[next].key = symbols[root].key;
                    symbols[root].key = truncmask(u16, next);
                    root += 1;
                } else {
                    symbols[next].key = symbols[leaf].key;
                    leaf += 1;
                }

                if ((leaf >= n) or ((root < next) and (symbols[root].key < symbols[leaf].key))) {
                    symbols[next].key = symbols[next].key +% symbols[root].key;
                    symbols[root].key = truncmask(u16, next);
                    root += 1;
                } else {
                    symbols[next].key = symbols[next].key +% symbols[leaf].key;
                    leaf += 1;
                }
            }

            symbols[n - 2].key = 0;
            // for next in (0..n - 2).rev() {
            //     symbols[next].key = symbols[symbols[next].key as usize].key + 1;
            // }
            // n=6, next=3,2,1,0
            next = n - 1;
            while (next > 0) : (next -= 1) {
                symbols[next - 1].key = symbols[symbols[next - 1].key].key + 1;
            }

            var avbl: usize = 1;
            var used: usize = 0;
            var dpth: usize = 0;
            root = (n - 2);
            next = (n - 1);
            while (avbl > 0) {
                while ((root >= 0) and (symbols[root].key == dpth)) {
                    used += 1;
                    if (root > 0) {
                        root -= 1;
                    } else {
                        break;
                    }
                }
                while (avbl > used) {
                    symbols[next].key = truncmask(u16, dpth);
                    next -= 1;
                    avbl -= 1;
                }
                avbl = 2 * used;
                dpth += 1;
                used = 0;
            }
        }
    }
    warn("calculate_minimum_redundancy done\n");
}

fn enforce_max_code_size(num_codes: []u32, code_list_len: usize, max_code_size: usize) void {
    if (code_list_len <= 1) {
        return;
    }

    // num_codes[max_code_size] += num_codes[max_code_size + 1..].iter().sum::<i32>();
    var sum: u32 = 0;
    for (num_codes[max_code_size + 1..]) |v| {
        sum += v;
    }
    num_codes[max_code_size] += sum;
    // let total = num_codes[1..max_code_size + 1]
    //     .iter()
    //     .rev()
    //     .enumerate()
    //     .fold(0u32, |total, (i, &x)| total + ((x as u32) << i));
    var i: usize = max_code_size;
    var total: u32 = 0;
    var ii = u32(0);
    while (i >= 1) : (i -= 1) {
        total += (num_codes[i] << truncmask(u5, ii));
        ii += 1;
    }

    // for _ in (1 << max_code_size)..total {
    var x = (usize(1) << truncmask(u5, max_code_size));
    warn("x={}, total={}, max_code_size={}\n", x, total, max_code_size);
    while (x < total) : (x += 1) {
        num_codes[max_code_size] -= 1;
        i = max_code_size - 1;
        // for i in (1..max_code_size).rev() {
        while (i >= 1) : (i -= 1) {
            if (num_codes[i] != 0) {
                num_codes[i] -= 1;
                num_codes[i + 1] += 2;
                break;
            }
        }
    }
}

/// Compression callback function type.
//pub type PutBufFuncPtrNotNull = unsafe extern "C" fn(*const c_void, c_int, *mut c_void) -> bool;
/// `Option` alias for compression callback function type.
//pub type PutBufFuncPtr = Option<PutBufFuncPtrNotNull>;

//pub mod deflate_flags {
/// Whether to use a zlib wrapper.
pub const TDEFL_WRITE_ZLIB_HEADER: u32 = 0x00001000;
/// Should we compute the adler32 checksum.
pub const TDEFL_COMPUTE_ADLER32: u32 = 0x00002000;
/// Should we use greedy parsing (as opposed to lazy parsing where look ahead one or more
/// bytes to check for better matches.)
pub const TDEFL_GREEDY_PARSING_FLAG: u32 = 0x00004000;
/// TODO
pub const TDEFL_NONDETERMINISTIC_PARSING_FLAG: u32 = 0x00008000;
/// Only look for matches with a distance of 0.
pub const TDEFL_RLE_MATCHES: u32 = 0x00010000;
/// Only use matches that are at least 6 bytes long.
pub const TDEFL_FILTER_MATCHES: u32 = 0x00020000;
/// Force the compressor to only output static blocks. (Blocks using the default huffman codes
/// specified in the deflate specification.)
pub const TDEFL_FORCE_ALL_STATIC_BLOCKS: u32 = 0x00040000;
/// Force the compressor to only output raw/uncompressed blocks.
pub const TDEFL_FORCE_ALL_RAW_BLOCKS: u32 = 0x00080000;
//}

/// Used to generate deflate flags with `create_comp_flags_from_zip_params`.
//#[repr(i32)]
//#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash)]
pub const CompressionStrategy = extern enum {
    /// Don't use any of the special strategies.
    Default = 0,
    /// Only use matches that are at least 5 bytes long.
    Filtered = 1,
    /// Don't look for matches, only huffman encode the literals.
    HuffmanOnly = 2,
    /// Only look for matches with a distance of 1, i.e do run-length encoding only.
    RLE = 3,
    /// Only use static/fixed blocks. (Blocks using the default huffman codes
    /// specified in the deflate specification.)
    Fixed = 4,
};

/// A list of deflate flush types.
//#[repr(u32)]
//#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash)]
pub const TDEFLFlush = extern enum {
    const Self = this;
    None = 0,
    Sync = 2,
    Full = 3,
    Finish = 4,

    fn fromu32(flush: u32) !Self {
        return switch (flush) {
            0 => TDEFLFlush.None,
            2 => TDEFLFlush.Sync,
            3 => TDEFLFlush.Full,
            4 => TDEFLFlush.Finish,
            else => error.BadParam,
         };
     }
};

test "tdefl flush" {
    var flush = TDEFLFlush.fromu32(0) catch TDEFLFlush.Finish;
    assert(flush == TDEFLFlush.None);
    flush = TDEFLFlush.fromu32(2) catch TDEFLFlush.None;
    assert(flush == TDEFLFlush.Sync);
    flush = TDEFLFlush.fromu32(3) catch TDEFLFlush.None;
    assert(flush == TDEFLFlush.Full);
    flush = TDEFLFlush.fromu32(4) catch TDEFLFlush.None;
    assert(flush == TDEFLFlush.Finish);
    assertError(TDEFLFlush.fromu32(1), error.BadParam);
    assertError(TDEFLFlush.fromu32(5), error.BadParam);
}

// impl From<MZFlush> for TDEFLFlush {
//     fn from(flush: MZFlush) -> Self {
//         match flush {
//             MZFlush::None => TDEFLFlush::None,
//             MZFlush::Sync => TDEFLFlush::Sync,
//             MZFlush::Full => TDEFLFlush::Full,
//             MZFlush::Finish => TDEFLFlush::Finish,
//             _ => TDEFLFlush::None, // TODO: ??? What to do ???
//         }
//     }
// }

/// Return status codes.
//#[repr(i32)]
//#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash)]
pub const TDEFLStatus = extern enum {
    BadParam = -2,
    PutBufFailed = -1,
    Okay = 0,
    Done = 1,
};

const MAX_HUFF_SYMBOLS = 288;
/// Size of hash values in the hash chains.
const LZ_HASH_BITS = 15;
/// Size of hash chain for fast compression mode.
const LEVEL1_HASH_SIZE_MASK = 4095;
/// How many bits to shift when updating the current hash value.
const LZ_HASH_SHIFT = (LZ_HASH_BITS + 2) / 3;
/// Size of the chained hash tables.
const LZ_HASH_SIZE = 1 << LZ_HASH_BITS;

/// The number of huffman tables used by the compressor.
/// Literal/length, Distances and Length of the huffman codes for the other two tables.
const MAX_HUFF_TABLES = 3;
/// Literal/length codes
const MAX_HUFF_SYMBOLS_0 = 288;
/// Distance codes.
const MAX_HUFF_SYMBOLS_1 = 32;
/// Huffman length values.
const MAX_HUFF_SYMBOLS_2 = 19;
/// Size of the chained hash table.
pub const LZ_DICT_SIZE = 32768;
/// Mask used when stepping through the hash chains.
const LZ_DICT_SIZE_MASK = LZ_DICT_SIZE - 1;
/// The minimum length of a match.
const MIN_MATCH_LEN = 3;
/// The maximum length of a match.
pub const MAX_MATCH_LEN = 258;

// Don't call this memset or it will call itself...
fn setmem(comptime T: type, slice: []T, val: T) void {
    //warn("setmem({} {})\n", slice.len, val);
    for (slice) |*x| {
        x.* = val;
    }
}

fn write_u16_le(val: u16, slice: []u8, pos: usize) void {
    assert((@sizeOf(u16) + pos) <= slice.len);
    mem.writeInt(slice[pos..pos+@sizeOf(u16)], val, builtin.Endian.Little);
}

fn write_u16_le_uc(val: u16, slice: []u8, pos: usize) void {
    // ptr::write_unaligned(slice.as_mut_ptr().offset(pos as isize) as *mut u16, val);
    assert((@sizeOf(@typeOf(val)) + pos) <= slice.len);
    mem.writeInt(slice[pos..pos+@sizeOf(u16)], val, builtin.Endian.Little);
}

fn read_u16_le(slice: []u8, pos: usize) u16 {
    assert(pos + 1 < slice.len);
    //assert(pos < slice.len);
    return mem.readInt(slice[pos..pos+@sizeOf(u16)], u16, builtin.Endian.Little);
}

/// A struct containing data about huffman codes and symbol frequencies.
///
/// NOTE: Only the literal/lengths have enough symbols to actually use
/// the full array. It's unclear why it's defined like this in miniz,
/// it could be for cache/alignment reasons.
pub const HuffmanEntry = struct {
    const Self = this;
    /// Number of occurrences of each symbol.
    pub count: [MAX_HUFF_SYMBOLS]u16,
    /// The bits of the huffman code assigned to the symbol
    pub codes: [MAX_HUFF_SYMBOLS]u16,
    /// The length of the huffman code assigned to the symbol.
    pub code_sizes: [MAX_HUFF_SYMBOLS]u6,

    fn optimize_table(self: *Self, table_len: usize,
                      code_size_limit: usize, static_table: bool) void {
        //warn("table_len={}, code_size_limit={}, static_table={}\n",
        //     table_len, code_size_limit, static_table);
        var num_codes = []u32 {0} ** (MAX_SUPPORTED_HUFF_CODESIZE + 1);
        var next_code = []u32 {0} ** (MAX_SUPPORTED_HUFF_CODESIZE + 1);

        if (static_table) {
            for (self.code_sizes[0..table_len]) |code_size, ii| {
                num_codes[code_size] += 1;
                //warn("{}: {}={}\n", ii, code_size, num_codes[code_size]);
            }
        } else {
            var symbols0 = []SymFreq { SymFreq {.key = 0, .sym_index = 0} } ** MAX_HUFF_SYMBOLS;
            var symbols1 = []SymFreq { SymFreq {.key = 0, .sym_index = 0} } ** MAX_HUFF_SYMBOLS;
            var num_used_symbols: usize = 0;
            // for i in 0..table_len {
            var i: usize = 0;
            while (i < table_len) : (i += 1) {
                if (self.count[i] != 0) {
                    symbols0[num_used_symbols] = SymFreq {
                         .key = self.count[i],
                         .sym_index = truncmask(u16, i),
                    };
                    num_used_symbols += 1;
                }
            }

            const symbols = radix_sort_symbols(symbols0[0..num_used_symbols],
                                               symbols1[0..num_used_symbols]);

            calculate_minimum_redundancy(symbols);

            for (symbols) |symbol| {
                num_codes[symbol.key] += 1;
            }

            enforce_max_code_size(num_codes[0..], num_used_symbols, code_size_limit);

            setmem(u6, self.code_sizes[0..], 0);
            setmem(u16, self.codes[0..], 0);

            var last = num_used_symbols;
            i = 1;
            while (i < (code_size_limit + 1)) : (i += 1) {
                // for i in 1..code_size_limit + 1 {
                const first: usize = last - num_codes[i];
                warn("first={}, last={}\n", first, last);
                for (symbols[first..last]) |symbol| {
                    self.code_sizes[symbol.sym_index] = truncmask(u6, i);
                }
                last = first;
            }
        }

        var j: u32 = 0;
        next_code[1] = 0;
        var i: usize = 2;
        //for i in 2..code_size_limit + 1 {
        while (i < (code_size_limit + 1)) : (i += 1) {
            j = (j + num_codes[i - 1]) << 1;
            next_code[i] = j;
        }

        i = 0;
        while (i < table_len) : (i += 1) {
            const code_size = &self.code_sizes[i];
            //DEBUG warn("i={}, code_size={}\n", i, code_size);
            if (code_size.* == 0) {
                continue;
            }
            var code = next_code[code_size.*];
            next_code[code_size.*] += 1;
            var rev_code: u32 = 0;

            j = 0;
            while (j < code_size.*) : (j += 1) {
                rev_code = (rev_code << 1) | (code & 1);
                code >>= 1;
            }

            //warn("i={}, j={}, rev_code={}\n", i, j, rev_code);
            self.codes[i] = @truncate(u16, rev_code & @maxValue(u16));
        }
    }

};

/// Tables used for literal/lengths in `Huffman`.
const LITLEN_TABLE = 0;
/// Tables for distances.
const DIST_TABLE = 1;
/// Tables for the run-length encoded huffman lenghts for literals/lengths/distances.
const HUFF_CODES_TABLE = 2;

pub const Huffman = struct {
    const Self = this;
    //tables: [MAX_HUFF_TABLES]HuffmanEntry,
    litlen: HuffmanEntry,
    dist: HuffmanEntry,
    huffcodes: HuffmanEntry,

    fn dump(self: *Self) void {
        warn("{}\n", self);
    }

    fn init () Self {
        var huff = Self {
            .litlen = HuffmanEntry {
                .count = []u16 {0} ** MAX_HUFF_SYMBOLS,
                .codes = []u16 {0} ** MAX_HUFF_SYMBOLS,
                .code_sizes = []u6 {0} ** MAX_HUFF_SYMBOLS,
            },
            .dist = HuffmanEntry {
                .count = []u16 {0} ** MAX_HUFF_SYMBOLS,
                .codes = []u16 {0} ** MAX_HUFF_SYMBOLS,
                .code_sizes = []u6 {0} ** MAX_HUFF_SYMBOLS,
            },
            .huffcodes = HuffmanEntry {
                .count = []u16 {0} ** MAX_HUFF_SYMBOLS,
                .codes = []u16 {0} ** MAX_HUFF_SYMBOLS,
                .code_sizes = []u6 {0} ** MAX_HUFF_SYMBOLS,
            },
        };

        return huff;
    }

    fn compress_block(self: *Self, output: *OutputBuffer, lz: *LZ, static_block: bool) !bool {
        //warn("compress_block {}\n", static_block);
        //lz.dump();
        if (static_block) {
            self.start_static_block(output);
        } else {
            try self.start_dynamic_block(output);
            //self.start_static_block(output);
        }

        //lz.dump();
        return compress_lz_codes(self, output, lz.codes[0..lz.code_position]);
    }

    fn start_static_block(self: *Self, output: *OutputBuffer) void {
        warn("start_static_block\n");
        setmem(u6, self.litlen.code_sizes[0..144], 8);
        setmem(u6, self.litlen.code_sizes[144..256], 9);
        setmem(u6, self.litlen.code_sizes[256..280], 7);
        setmem(u6, self.litlen.code_sizes[280..288], 8);

        setmem(u6, self.dist.code_sizes[0..32], 5);

        self.litlen.optimize_table(288, 15, true);
        self.dist.optimize_table(32, 15, true);

        output.put_bits(0b01, 2);
    }

    fn start_dynamic_block(self: *Self, output: *OutputBuffer) !void {
        warn("start_dynamic_block\n");
        // There will always be one, and only one end of block code.
        self.litlen.count[256] = 1;

        self.litlen.optimize_table(MAX_HUFF_SYMBOLS_0, 15, false);
        self.dist.optimize_table(MAX_HUFF_SYMBOLS_1, 15, false);

        warn("optimized\n");

        //     &self.code_sizes[0][257..286]
        //         .iter()
        //         .rev()
        //         .take_while(|&x| *x == 0)
        //         .count();
        var count: u32 = 0;
        var i: u32 = 286 - 1;
        while (i >= 257) : (i -= 1) {
            if (self.litlen.code_sizes[i] != 0) {
                break;
            }
            count += 1;
        }
        const num_lit_codes = 286 - count;

        //     &self.code_sizes[1][1..30]
        //         .iter()
        //         .rev()
        //         .take_while(|&x| *x == 0)
        //         .count();
        count = 0;
        i = 30 - 1;
        while (i <= 1) : (i -= 1) {
            if (self.dist.code_sizes[i] != 0) {
                break;
            }
            count += 1;
        }
        const num_dist_codes = 30 - count;
        warn("lit={}, dist={}\n", num_lit_codes, num_dist_codes);

        var code_sizes_to_pack = []u8 {0} ** (MAX_HUFF_SYMBOLS_0 + MAX_HUFF_SYMBOLS_1);
        var packed_code_sizes = []u8 {0} ** (MAX_HUFF_SYMBOLS_0 + MAX_HUFF_SYMBOLS_1);

        const total_code_sizes_to_pack = num_lit_codes + num_dist_codes;

        // code_sizes_to_pack[..num_lit_codes].copy_from_slice(&self.code_sizes[0][..num_lit_codes]);
        for (self.litlen.code_sizes[0..num_lit_codes]) |cs, ii|{
            code_sizes_to_pack[ii] = cs;
        }

        // code_sizes_to_pack[num_lit_codes..total_code_sizes_to_pack]
        //     .copy_from_slice(&self.code_sizes[1][..num_dist_codes]);
        for (self.dist.code_sizes[0..num_dist_codes]) |cs, ii| {
            code_sizes_to_pack[num_lit_codes + ii] = cs;
        }

        var rle = RLE {
            .z_count = 0,
            .repeat_count = 0,
            .p_code_size = 0xFF,
        };

        setmem(u16, self.huffcodes.count[0..MAX_HUFF_SYMBOLS_2], 0);

        var packed_code_sizes_cursor = Cursor([]u8){.pos= 0, .inner = packed_code_sizes[0..]};
        for (code_sizes_to_pack[0..total_code_sizes_to_pack]) |code_size| {
            if (code_size == 0) {
                try rle.prev_code_size(&packed_code_sizes_cursor, self);
                rle.z_count += 1;
                if (rle.z_count == 138) {
                    try rle.zero_code_size(&packed_code_sizes_cursor, self);
                }
            } else {
                try rle.zero_code_size(&packed_code_sizes_cursor, self);
                if (code_size != rle.p_code_size) {
                    try rle.prev_code_size(&packed_code_sizes_cursor, self);
                    self.huffcodes.count[code_size] +%= 1;
                    //self.count[HUFF_CODES_TABLE][code_size as usize] =
                    //    self.count[HUFF_CODES_TABLE][code_size as usize].wrapping_add(1);
                    var ary = [1]u8 {code_size};
                    try packed_code_sizes_cursor.write_all(ary[0..]);
                } else {
                    rle.repeat_count += 1;
                    if (rle.repeat_count == 6) {
                        try rle.prev_code_size(&packed_code_sizes_cursor, self);
                    }
                }
            }
            rle.p_code_size = code_size;
        }

        if (rle.repeat_count != 0) {
            try rle.prev_code_size(&packed_code_sizes_cursor, self);
        } else {
            try rle.zero_code_size(&packed_code_sizes_cursor, self);
        }

        self.huffcodes.optimize_table(MAX_HUFF_SYMBOLS_2, 7, false);

        output.put_bits(2, 2);

        output.put_bits((num_lit_codes - 257), 5);
        output.put_bits((num_dist_codes - 1), 5);

        var num_bit_lengths: u32 = 18;
        //     HUFFMAN_LENGTH_ORDER
        //         .iter()
        //         .rev()
        //         .take_while(|&swizzle| {
        //             self.code_sizes[HUFF_CODES_TABLE][*swizzle as usize] == 0
        //         })
        //         .count();
        count = 0;
        i = truncmask(u32, HUFFMAN_LENGTH_ORDER.len);
        while (i > 0) : (i -= 1) {
            const swizzle = HUFFMAN_LENGTH_ORDER[i - 1];
            if (self.huffcodes.code_sizes[swizzle] != 0) {
                break;
            }
            count += 1;
        }
        num_bit_lengths -= count;

        num_bit_lengths = MAX(u32, 4, num_bit_lengths + 1);
        output.put_bits(num_bit_lengths - 4, 4);
        for (HUFFMAN_LENGTH_ORDER[0..num_bit_lengths]) |swizzle| {
             output.put_bits(self.huffcodes.code_sizes[swizzle], 3);
        }

        var packed_code_size_index: usize = 0;
        // let packed_code_sizes = packed_code_sizes_cursor.get_ref();
        while (packed_code_size_index < packed_code_sizes_cursor.position()) {
            const code = packed_code_sizes[packed_code_size_index];
            packed_code_size_index += 1;
            assert(code < MAX_HUFF_SYMBOLS_2);
            output.put_bits(self.huffcodes.codes[code],
                            self.huffcodes.code_sizes[code]);
            if (code >= 16) {
                const ary = []u5 {2, 3, 7};
                output.put_bits(
                    packed_code_sizes[packed_code_size_index], ary[code - 16]);
                packed_code_size_index += 1;
            }
        }

        // Ok(())
    }

};


/// Size of the buffer of LZ77 encoded data.
pub const LZ_CODE_BUF_SIZE = 64 * 1024;
/// Size of the output buffer.
pub const OUT_BUF_SIZE = (LZ_CODE_BUF_SIZE * 13) / 10;

pub const HashBuffers = struct {
    pub dict: [LZ_DICT_SIZE + MAX_MATCH_LEN - 1 + 1]u8,
    pub next: [LZ_DICT_SIZE]u16,
    pub hash: [LZ_DICT_SIZE]u16,

    fn init() HashBuffers {
        return HashBuffers {
            .dict = []u8 {0} ** (LZ_DICT_SIZE + MAX_MATCH_LEN - 1 + 1),
            .next = []u16 {0} ** LZ_DICT_SIZE,
            .hash = []u16 {0} ** LZ_DICT_SIZE,
        };
    }
};


pub const LocalBuf = struct {
    const Self = this;
    pub b: [OUT_BUF_SIZE]u8,

    fn default() Self {
        return LocalBuf {
            .b = []u8 {0} ** OUT_BUF_SIZE,
        };
    }
};

const MatchResult = struct {
    const Self = this;
    distance: u32,
    length: u32,
    loc: u8,

    fn dump(self: *const Self) void {
        warn("MatchResult distance={}, length={}, loc={}\n",
             self.distance, self.length, self.loc);
    }
};

const Dictionary = struct {
    const Self = this;
    /// The maximum number of checks in the hash chain, for the initial,
    /// and the lazy match respectively.
    pub max_probes: [2]u32,
    /// Buffer of input data.
    /// Padded with 1 byte to simplify matching code in `compress_fast`.
    pub b: HashBuffers,

    pub code_buf_dict_pos: u32,
    pub lookahead_size: u32,
    pub lookahead_pos: u32,
    pub size: u32,

    fn dump(self: *Self) void {
        warn("{} max_probes={}/{}\n" ++
             "code_buf_dict_pos={}, lookahead_size={}, lookahead_pos={}, size={}",
             self, self.max_probes[0], self.max_probes[1],
             self.code_buf_dict_pos, self.lookahead_size, self.lookahead_pos, self.size);
    }

    fn init(flags: u32) Self {
        return Dictionary {
            .max_probes = []u32 {1 + ((flags & 0xFFF) + 2) / 3, 1 + (((flags & 0xFFF) >> 2) + 2) / 3},
            .b = HashBuffers.init(),
            .code_buf_dict_pos = 0,
            .lookahead_size = 0,
            .lookahead_pos = 0,
            .size = 0,
        };
    }

    /// Do an unaligned read of the data at `pos` in the dictionary and treat it as if it was of
    /// type T.
    ///
    /// Unsafe due to reading without bounds checking and type casting.
    fn read_unaligned(self: *Self, comptime T: type, pos: usize) T {
        //ptr::read_unaligned((&self.b.dict as *const [u8] as *const u8).offset(pos) as
        //                    *const T)
        return mem.readInt(self.b.dict[pos..pos+@sizeOf(T)], T, builtin.Endian.Big);
    }

    /// Try to find a match for the data at lookahead_pos in the dictionary that is
    /// longer than `match_len`.
    /// Returns a tuple containing (match_distance, match_length). Will be equal to the input
    /// values if no better matches were found.
    fn find_match(self: *Self, lookahead_pos: u32, max_dist: u32, amax_match_len: u32,
                  amatch_dist: u32,
                  amatch_len: u32,
    ) MatchResult {
        // Clamp the match len and max_match_len to be valid. (It should be when this is called, but
        // do it for now just in case for safety reasons.)
        // This should normally end up as at worst conditional moves,
        // so it shouldn't slow us down much.
        // TODO: Statically verify these so we don't need to do this.
        var max_match_len = MIN(u32, MAX_MATCH_LEN, amax_match_len);
        var match_len = MAX(u32, amatch_len, 1);
        var match_dist = amatch_dist;
        var i: usize = 0;

        const pos = (lookahead_pos & LZ_DICT_SIZE_MASK);
        var probe_pos = pos;
        // Number of probes into the hash chains.
        var num_probes_left = self.max_probes[@boolToInt(match_len >= 32)];

        // If we already have a match of the full length don't bother searching for another one.
        if (max_match_len <= match_len) {
            return MatchResult{.distance = match_dist, .length = match_len, .loc = 0};
        }

        // Read the last byte of the current match, and the next one, used to compare matches.
        // # Unsafe
        // `pos` is masked by `LZ_DICT_SIZE_MASK`
        // `match_len` is clamped be at least 1.
        // If it is larger or equal to the maximum length, this statement won't be reached.
        // As the size of self.dict is LZ_DICT_SIZE + MAX_MATCH_LEN - 1 + DICT_PADDING,
        // this will not go out of bounds.
        var c01: u16 = self.read_unaligned(u16, (pos + match_len - 1));
        // Read the two bytes at the end position of the current match.
        // # Unsafe
        // See previous.
        var s01: u16 = self.read_unaligned(u16, pos);

        outer: while (true) {
            var dist: u32 = 0;
            found: while (true) {
                //warn("num_probes_left={}\n", num_probes_left);
                num_probes_left -= 1;
                if (num_probes_left == 0) {
                    // We have done as many probes in the hash chain as the current compression
                    // settings allow, so return the best match we found, if any.
                    return MatchResult{.distance = match_dist, .length = match_len, .loc = 1};
                }

                // for _ in 0..3 {
                i = 0;
                while (i < 3) : (i += 1) {
                    const next_probe_pos: u32 = self.b.next[probe_pos];

                    dist = ((lookahead_pos - next_probe_pos) & 0xFFFF);
                    if ((next_probe_pos == 0) or (dist > max_dist)) {
                        // We reached the end of the hash chain, or the next value is further away
                        // than the maximum allowed distance, so return the best match we found, if
                        // any.
                        return MatchResult {.distance = match_dist, .length = match_len, .loc = 2};
                    }

                    // Mask the position value to get the position in the hash chain of the next
                    // position to match against.
                    probe_pos = next_probe_pos & LZ_DICT_SIZE_MASK;
                    // # Unsafe
                    // See the beginning of this function.
                    // probe_pos and match_length are still both bounded.
                    //     unsafe {
                    // The first two bytes, last byte and the next byte matched, so
                    // check the match further.
                    if (self.read_unaligned(u16, (probe_pos + match_len - 1)) == c01) {
                        //warn("break 0x{x04} found\n", c01);
                        break :found;
                    }
                    //     }
                }
            }

            if (dist == 0) {
                return MatchResult{.distance = match_dist, .length = match_len, .loc = 3};
            }
            // # Unsafe
            // See the beginning of this function.
            // probe_pos is bounded by masking with LZ_DICT_SIZE_MASK.
            {
                if (self.read_unaligned(u16, probe_pos) != s01) {
                    continue;
                }
            }

            var p = pos + 2;
            var q = probe_pos + 2;
            // Check the length of the match.
            i = 0;
            while (i < 32) : (i += 1) {
                // # Unsafe
                // This loop has a fixed counter, so p_data and q_data will never be
                // increased beyond 250 bytes past the initial values.
                // Both pos and probe_pos are bounded by masking with LZ_DICT_SIZE_MASK,
                // so {pos|probe_pos} + 258 will never exceed dict.len().
                const p_data: u64 = self.read_unaligned(u64, p);
                const q_data: u64 = self.read_unaligned(u64, q);
                // Compare of 8 bytes at a time by using unaligned loads of 64-bit integers.
                const xor_data = p_data ^ q_data;
                if (xor_data == 0) {
                    p += 8;
                    q += 8;
                } else {
                    // If not all of the last 8 bytes matched, check how may of them did.
                    const trailing = @ctz(xor_data);
                    const probe_len = p - pos + (trailing >> 3);
                    if (probe_len > match_len) {
                        match_dist = dist;
                        match_len = MIN(u32, max_match_len, probe_len);
                        if (match_len == max_match_len) {
                            return MatchResult{.distance = match_dist, .length = match_len, .loc = 4};
                        }
                        // # Unsafe
                        // pos is bounded by masking.
                        {
                            c01 = self.read_unaligned(u16, (pos + match_len - 1));
                        }
                    }
                    continue :outer;
                }
            }

            return MatchResult{.distance = dist, .length = MIN(u32, max_match_len, MAX_MATCH_LEN),
                               .loc = 5};
        }
    }

};


const SeekFrom = union(enum) {
    Start: isize,
    End: isize,
    Current: isize,
};

fn Cursor(comptime T: type) type {
    return struct {
        const Self = this;
        pos: usize,
        inner: T,

        fn dump(self: *Self) void {
            warn("{} pos={}, inner.len={}\n", self, self.pos, self.inner.len);
        }

        fn init(self: *Self, ary: T) void {
            self.pos = 0;
            self.inner.ptr = ary.ptr;
            self.inner.len = ary.len;
        }
        // inline
        fn len(self: *Self) usize {
            return self.inner.len;
        }

        // inline
        fn position(self: *Self) usize {
            return self.pos;
        }

        fn set_position(self: *Self, pos: usize) void {
            assert(pos < self.inner.len);
            self.pos = pos;
        }

        fn seek(self: *Self, style: SeekFrom) !void {
            switch (style) {
                SeekFrom.Start => |dist| {
                    warn("NOT IMPLEMENTED Seeking from start {}\n", dist);
                    return error.NotImplemented;
                },
                SeekFrom.End => |dist| {
                    warn("NOT IMPLEMENTED Seeking from end {}\n", dist);
                    return error.NotImplemented;
                },
                SeekFrom.Current => |dist| {
                    //warn("Seeking from current {}\n", dist);
                    var d = dist;
                    if (d > 0) {
                        while (d > 0) : (d -= 1) {
                            self.pos += 1;
                        }
                    } else {
                        while (d < 0) : (d += 1) {
                            self.pos -= 1;
                        }
                    }
                },
                else => { return error.Bug; },
            }
        }

        fn writeInt(self: *Self, value: u64, endian: builtin.Endian) !void {
            if ((self.inner.len - self.pos) <= @sizeOf(u64)) {
                return error.NoSpace;
            }
            mem.writeInt(self.inner[self.pos..self.pos+@sizeOf(u64)], value, endian);
        }

        fn write_all(self: *Self, buf: []const u8) !void {
            if ((self.pos + buf.len) >= self.inner.len) {
                return error.NoSpace;
            }
            for (buf) |c| {
                self.inner[self.pos] = c;
                self.pos += 1;
            }
        }
    };
    }

const OutputBuffer = struct {
    const Self = this;
    pub inner: Cursor([]u8),
    pub local: bool,
    pub bit_buffer: u32,
    pub bits_in: u5,

    fn len(self: *Self) usize {
        return self.inner.len();
    }

    fn write_u64_le(self: *Self, value: u64) !void {
        //warn("Writing u64={x}\n", value);
        try self.inner.writeInt(value, builtin.Endian.Little);
    }

    fn put_bits(self: *Self, bits: u32, length: u32) void {
        // assert!(bits <= ((1u32 << len) - 1u32));
        //warn("put_bits({x08},{})\n", bits, length);
        self.bit_buffer |= bits << self.bits_in;
        self.bits_in += truncmask(u5, length);
        while (self.bits_in >= 8) {
            const pos = self.inner.position();
            // .get_mut()
            self.inner.inner[pos] = truncmask(u8, self.bit_buffer);
            self.inner.set_position(pos + 1);
            self.bit_buffer >>= 8;
            self.bits_in -= 8;
        }
    }

    fn save(self: *Self) SavedOutputBuffer {
        var sb = SavedOutputBuffer {
            .pos = self.inner.position(),
            .bit_buffer = self.bit_buffer,
            .bits_in = self.bits_in,
            .local = self.local,
        };

        return sb;
    }

    fn load(self: *Self, saved: SavedOutputBuffer) void {
        self.inner.set_position(saved.pos);
        self.bit_buffer = saved.bit_buffer;
        self.bits_in = saved.bits_in;
        self.local = saved.local;
    }

    fn pad_to_bytes(self: *Self) void {
        if (self.bits_in != 0) {
            const length = 8 - self.bits_in;
            warn("pad_to_bytes bits_in={}, length={}\n", self.bits_in, length);
            self.put_bits(0, length);
        }
    }

};

test "outputbuffer and bitbuffer" {
    var buf = []u8 {0} ** 1024;
    var ob: OutputBuffer = undefined;
    var cursor: Cursor([]u8) = undefined;
    cursor.init(buf[0..]);
    ob.inner = cursor; // {.pos = 0, .inner = buf[0..]};
    cursor.dump();
    ob.local = false;
    ob.bit_buffer = 0;
    ob.bits_in = 0;

    warn("sizeof OutputBuffer={}\n", usize(@sizeOf(OutputBuffer)));
    warn("ob.len={}, ob.pos={}, ob.inner.len={}\n", ob.len(), ob.inner.position(), ob.inner.len());

    var bb = BitBuffer {.bit_buffer = 0, .bits_in = 0};
    bb.put_fast(123456, 63);
    bb.dump();

    var r = bb.flush(&ob);
    bb.dump();
    warn("ob.len={}, ob.pos={}\n", ob.len(), ob.inner.position());
}

const SavedOutputBuffer = struct {
    const Self = this;
    pub pos: usize,
    pub bit_buffer: u32,
    pub bits_in: u5,
    pub local: bool,

    fn dump(self: *const Self) void {
        warn("SavedOutputBuffer@{} pos={}, bit_buffer={x08}, bits_in={}, local={}\n",
             self, self.pos, self.bit_buffer, self.bits_in, self.local);
    }
};

const BitBuffer = struct {
    const Self = this;
    // space for up to 8 bytes
    pub bit_buffer: u64,
    pub bits_in: u6,

    fn dump(self: *Self) void {
        warn("bit_buffer={x016}, bits_in={}\n", self.bit_buffer, self.bits_in);
    }

    fn put_fast(self: *Self, bits: u64, len: u6) void {
        // what if we want to write a complete u64?
        //self.dump();
        //warn("BitBuffer put_fast({x016}, {})\n", bits, len);
        self.bit_buffer |= (bits << self.bits_in);
        self.bits_in += len;
        //self.dump();
    }

    fn flush(self: *Self, output: *OutputBuffer) !void {
        const pos = output.inner.position();
        //warn("-> BitBuffer flush pos={} {x016} bits_in={}\n", pos, self.bit_buffer, self.bits_in);
        //var inner = &mut ((*output.inner.get_mut())[pos]) as *mut u8 as *mut u64;
        // # Unsafe
        // TODO: check unsafety
        //unsafe {
        //    ptr::write_unaligned(inner, self.bit_buffer.to_le());
        //}
        // Write the complete u64
        try output.write_u64_le(self.bit_buffer);
        // Move forward the number of bytes actually valid
        try output.inner.seek(SeekFrom {.Current = self.bits_in >> 3 });
        //warn("Bits out {}\n", self.bits_in & ~@typeOf(self.bits_in)(7));
        // Update the bit buffer
        self.bit_buffer >>= self.bits_in & ~@typeOf(self.bits_in)(7);
        // Update the number of bits
        self.bits_in &= 7;
        //warn("<- BitBuffer flush pos={} {x016} bits_in={}\n", pos, self.bit_buffer, self.bits_in);
    }
};


/// Status of RLE encoding of huffman code lengths.
pub const RLE = struct {
    const Self = this;
    pub z_count: u16,
    pub repeat_count: u16,
    pub p_code_size: u8,

    fn prev_code_size(self: *Self, packed_code_sizes: *Cursor([]u8), h: *Huffman ) !void {
        var counts = &h.huffcodes.count;
        if (self.repeat_count != 0) {
            if (self.repeat_count < 3) {
                counts[self.p_code_size] = counts[self.p_code_size]
                    +% self.repeat_count;
                const code = self.p_code_size;
                // Write for Vec<u8>/extend_from_slice
                // packed_code_sizes.write_all(
                //     &[code, code, code][..self.repeat_count as
                //                         usize],
                // )?;
                var ary = [3]u8 {code, code, code};
                warn("repeat_count={}\n", self.repeat_count);
                try packed_code_sizes.write_all(ary[0..self.repeat_count - 1]);
            } else {
                counts[16] = counts[16] +% 1;
                var ary = [2]u8 {16, @truncate(u8, (self.repeat_count - 3) & 0xff)};
                try packed_code_sizes.write_all(ary[0..]);
            }
            self.repeat_count = 0;
        }
    }

    fn zero_code_size(self: *Self, packed_code_sizes: *Cursor([]u8), h: *Huffman) !void {
        var counts = &h.huffcodes.count;
        if (self.z_count != 0) {
            if (self.z_count < 3) {
                counts[0] +%= self.z_count;
                // packed_code_sizes.write_all(
                //     &[0, 0, 0][..self.z_count as usize],
                // )?;
                const ary = [3]u8 {0,0,0};
                try packed_code_sizes.write_all(ary[0..self.z_count]);
            } else if (self.z_count <= 10) {
                counts[17] +%= 1;
                // packed_code_sizes.write_all(
                //     &[17, (self.z_count - 3) as u8][..],
                // )?;
                const ary = [2]u8 {17, truncmask(u8, self.z_count - 3)};
                try packed_code_sizes.write_all(ary[0..]);
            } else {
                counts[18] +%= 1;
                // packed_code_sizes.write_all(
                //     &[18, (self.z_count - 11) as u8][..],
                // )?;
                const ary = [2]u8 {18, truncmask(u8, self.z_count - 11)};
                try packed_code_sizes.write_all(ary[0..]);
            }
            self.z_count = 0;
        }
    }
};

const Params = struct {
    const Self = this;
    pub flags: u32,
    pub greedy_parsing: bool,
    pub block_index: u32,

    pub saved_match_dist: u32,
    pub saved_match_len: u32,
    pub saved_lit: u8,

    pub flush: TDEFLFlush,
    pub flush_ofs: u32,
    pub flush_remaining: u32,
    pub finished: bool,

    pub adler32: u32,

    pub src_pos: usize,

    pub out_buf_ofs: usize,
    pub prev_return_status: TDEFLStatus,

    pub saved_bit_buffer: u32,
    pub saved_bits_in: u5,

    pub local_buf: LocalBuf,

    fn dump(self: *Self) void {
        warn("Params: flags={}, greedy_parsing={}\n",
        self.flags, self.greedy_parsing);
    }

    fn init(flags: u32) Self {
        return Params {
            .flags = flags,
            .greedy_parsing = (flags & TDEFL_GREEDY_PARSING_FLAG) != 0,
            .block_index = 0,
            .saved_match_dist = 0,
            .saved_match_len = 0,
            .saved_lit = 0,
            .flush = TDEFLFlush.None,
            .flush_ofs = 0,
            .flush_remaining = 0,
            .finished = false,
            .adler32 = MZ_ADLER32_INIT,
            .src_pos = 0,
            .out_buf_ofs = 0,
            .prev_return_status = TDEFLStatus.Okay,
            .saved_bit_buffer = 0,
            .saved_bits_in= 0,
            .local_buf = LocalBuf.default()
        };
    }
};

test "Params" {
    var p = Params.init(0);
    p.dump();
}

const LZ = struct {
    const Self = this;
    pub code_position: usize,
    pub flag_position: usize,
    pub total_bytes: u32,
    pub num_flags_left: u32,
    pub codes: [LZ_CODE_BUF_SIZE]u8,

    fn dump(self: *Self) void {
        warn("LZ code_position={}, flag_postion={}, total_bytes={}, num_flags_left={}, flag={x02}\n",
             self.code_position, self.flag_position, self.total_bytes, self.num_flags_left, (self.get_flag()).*);
    }

    fn init() Self {
        var lz = Self {
            .codes = []u8 {0} ** LZ_CODE_BUF_SIZE,
            .code_position = 1,
            .flag_position = 0,
            .total_bytes = 0,
            .num_flags_left = 8,
        };
        //lz.dump();
        return lz;
    }

    fn write_code(self: *Self, val: u8) void {
        self.codes[self.code_position] = val;
        self.code_position += 1;
    }

    fn init_flag(self: *Self) void {
        //warn("init_flags: num_flags_left={}, {}, {}, {x02}\n", self.num_flags_left, self.code_position, self.flag_position, (self.get_flag()).*);
        if (self.num_flags_left == 8) {
            (self.get_flag()).* = 0;
            self.code_position -= 1;
        } else {
            (self.get_flag()).* >>= truncmask(u3, self.num_flags_left);
        }
        //warn("init_flags: num_flags_left={}, {}, {}, {x02}\n", self.num_flags_left, self.code_position, self.flag_position, (self.get_flag()).*);
    }

    fn get_flag(self: *Self) *u8 {
        return &self.codes[self.flag_position];
    }

    fn plant_flag(self: *Self) void {
        //warn("plant_flag: num_flags_left={}, {}, {}, {x02}\n", self.num_flags_left, self.code_position, self.flag_position, (self.get_flag()).*);
        self.flag_position = self.code_position;
        self.code_position += 1;
        //warn("plant_flag: num_flags_left={}, {}, {}, {x02}\n", self.num_flags_left, self.code_position, self.flag_position, (self.get_flag()).*);
    }

    fn consume_flag(self: *Self) void {
        //warn("consume_flag: num_flags_left={}, {}, {}, {x02}\n", self.num_flags_left, self.code_position, self.flag_position, (self.get_flag()).*);
        self.num_flags_left -= 1;
        if (self.num_flags_left == 0) {
            self.num_flags_left = 8;
            self.plant_flag();
        }
        //warn("consume_flag: num_flags_left={}, {}, {}, {x02}\n", self.num_flags_left, self.code_position, self.flag_position, (self.get_flag()).*);
    }
};


test "LZ" {
    const lz = LZ.init();
}

/// Main compression struct.
pub const Compressor = struct {
    const Self = this;
    lz: LZ,
    params: Params,
    huff: Huffman,
    dict: Dictionary,

    fn init(flags: u32) Self {
        warn("new Compressor\n");
        var comp: Self = Compressor {.lz = undefined, .params = undefined, .huff = Huffman.init(), .dict = undefined};
        // return Compressor {
        //     .lz = undefined, //LZ.init(),
        //     .params = undefined, //Params.init(flags),
        //     // LATER
        //     /// Put HuffmanOxide on the heap with default trick to avoid
        //     /// excessive stack copies.
        //     .huff = Huffman.init(),
        //     .dict = undefined,//Dictionary.init(flags),
        // };
        return comp;
    }

    fn initialize(self: *Self, flags: u32) void {
        self.lz = LZ.init();
        self.params = Params.init(flags);
        self.huff = Huffman.init();
        self.dict = Dictionary.init(flags);
    }

    /// Main compression function. Puts output into buffer.
    ///
    /// # Returns
    /// Returns a tuple containing the current status of the compressor, the current position
    /// in the input buffer and the current position in the output buffer.
    pub fn compress(self: *Self, in_buf: []u8, out_buf: []u8,
                    flush: TDEFLFlush) CompressionResult {
        //warn("compress\n");
        var callback = Callback.new_callback_buf(in_buf, out_buf);
        //callback.dump();
        return compress_inner(self, &callback, flush);
    }

};


const CompressionResult = struct {
    const Self = this;
    status: TDEFLStatus,
    inpos: usize,
    outpos: usize,

    fn dump(self: *Self) void {
        warn("inpos={}, outpos={}, status={}\n", self.inpos, self.outpos, @enumToInt(self.status));
    }

    fn new(status: TDEFLStatus, inpos: usize, outpos: usize) Self {
        return CompressionResult {.status = status, .inpos= inpos, .outpos = outpos};
    }
};

/// Compression callback function type.
pub const PutBufFuncPtrNotNull = fn([]const u8, usize, []u8) bool;
/// `Option` alias for compression callback function type.
pub const PutBufFuncPtr = ?PutBufFuncPtrNotNull;

pub const CallbackFunc = struct {
    pub put_buf_func: PutBufFuncPtrNotNull,
    pub put_buf_user: []u8,
};

const CallbackBuf = struct {
    const Self = this;
    out_buf: []u8,

    fn flush_output(self: *const Self, saved_output: SavedOutputBuffer, params: *Params) u32 {
        if (saved_output.local) {
            const n = MIN(usize, saved_output.pos, self.out_buf.len - params.out_buf_ofs);
            //(&mut self.out_buf[params.out_buf_ofs..params.out_buf_ofs + n])
            //     .copy_from_slice(&params.local_buf.b[..n]);
            for (params.local_buf.b[0..n]) |*b, ii| {
                self.out_buf[params.out_buf_ofs + ii] = b.*;
            }

            const nn = truncmask(u32, n);
            params.out_buf_ofs += nn;
            if (saved_output.pos != nn) {
                params.flush_ofs = nn;
                params.flush_remaining = truncmask(u32, saved_output.pos - n);
            }
        } else {
            params.out_buf_ofs += saved_output.pos;
        }

        return params.flush_remaining;
    }

};

const CallbackOut = union(enum) {
    const Self = this;
    Func: CallbackFunc,
    Buf: CallbackBuf,

    fn new_output_buffer(self: *Self, local_buf: []u8, out_buf_ofs: usize) OutputBuffer {
        var is_local = false;
        const buf_len = OUT_BUF_SIZE - 16;
        var chosen_buffer: []u8 = undefined;
        switch (self.*) {
            CallbackOut.Buf => |cb| {
                if (cb.out_buf.len - out_buf_ofs >= OUT_BUF_SIZE) {
                    is_local = false;
                    chosen_buffer = cb.out_buf[out_buf_ofs..out_buf_ofs + buf_len];
                } else {
                    is_local = true;
                    chosen_buffer = local_buf[0..buf_len];
                }
            },
            else => {
                is_local = true;
                chosen_buffer = local_buf[0..buf_len];
            },
        }

        var cursor: Cursor([]u8) = undefined;
        cursor.init(chosen_buffer[0..]);
        return OutputBuffer {
            .inner = cursor,
            .local = is_local,
            .bit_buffer = 0,
            .bits_in = 0,
        };
    }
};

const Callback = struct {
    const Self = this;
    in_buf: ?[]u8,
    in_buf_size: ?usize,
    out_buf_size: ?usize,
    out: CallbackOut,

    fn dump(self: *Self) void {
        warn("{} in_buf_size={}, out_but_size={}\n",
             self, self.in_buf_size, self.out_buf_size);
    }

    fn new_callback_buf(in_buf: []u8, out_buf: []u8) Self {
        return Callback {
            .in_buf = in_buf,
            .in_buf_size = in_buf.len,
            .out_buf_size = out_buf.len,
            .out = CallbackOut{.Buf = CallbackBuf {.out_buf = out_buf} },
        };
    }

    fn update_size(self: *Self, in_size: ?usize, out_size: ?usize) void {
        if (in_size) |value| {
            self.in_buf_size = value;
        }
        if (out_size) |value| {
            self.out_buf_size = value;
        }
    }

    fn flush_output(self: *Self, saved_output: SavedOutputBuffer, params: *Params) !u32 {
        //warn("flush_output()\n");
        if (saved_output.pos == 0) {
            return params.flush_remaining;
        }

        self.update_size(params.src_pos, null);
        switch (self.out) {
            CallbackOut.Func => |*cf| { return error.NotImplemented; },
            CallbackOut.Buf => |*cb| { return cb.flush_output(saved_output, params); },
            else => { return error.Bug; },
        }
    }
};

fn compress_lz_codes(huff: *Huffman, output: *OutputBuffer, lz_code_buf: []u8) !bool {
    //warn("compress_lz_codes\n");
    var flags: u32 = 1;
    var bb = BitBuffer {
        .bit_buffer = u64(output.bit_buffer),
        .bits_in = output.bits_in,
    };

    //bb.dump();

    var i: usize = 0;
    while (i < lz_code_buf.len) {
        if (flags == 1) {
            flags = u32(lz_code_buf[i]) | 0x100;
            i += 1;
        }

        // The lz code was a length code
        if ((flags & 1) == 1) {
            flags >>= 1;

            var sym: usize = 0;
            var num_extra_bits: u16 = 0;
            const match_len: u16 = lz_code_buf[i];
            const match_dist = read_u16_le(lz_code_buf, i + 1);
            //const match_dist =
            //warn("match_len={}, match_dist={}\n", match_len, match_dist);

            i += 3;

            assert(huff.litlen.code_sizes[LEN_SYM[match_len]] != 0);
            //warn("LEN[{}]={},{}, {}\n", match_len,LEN_SYM[match_len],  huff.litlen.codes[LEN_SYM[match_len]],  huff.litlen.code_sizes[LEN_SYM[match_len]]);
            const lensym = LEN_SYM[match_len];
            const lenextra = LEN_EXTRA[match_len];
            bb.put_fast(u64(huff.litlen.codes[lensym]), huff.litlen.code_sizes[lensym]);
            bb.put_fast(u64(match_len) & u64(BITMASKS[lenextra]), lenextra);
            //bb.dump();

            if (match_dist < 512) {
                sym = SMALL_DIST_SYM[match_dist];
                num_extra_bits = SMALL_DIST_EXTRA[match_dist];
            } else {
                sym = LARGE_DIST_SYM[(match_dist >> 8)];
                num_extra_bits = LARGE_DIST_EXTRA[(match_dist >> 8)];
            }

            //warn("sym={}, num_extra_bits={}, match_len={}, match_dist={}\n",
            //     sym, num_extra_bits, match_len, match_dist);
            //assert(huff.dist.code_sizes[sym] != 0);
            bb.put_fast(u64(huff.dist.codes[sym]), huff.dist.code_sizes[sym]);
            bb.put_fast(
                u64(match_dist) & u64(BITMASKS[num_extra_bits]),
                truncmask(u6, num_extra_bits));
        } else {
            // The lz code was a literal
            //warn("literal\n");
            //for _ in 0..3 {
            var ii: usize = 0;
            while (ii < 3) : (ii += 1) {
                flags >>= 1;
                const lit = lz_code_buf[i];
                i += 1;

                //assert(huff.litlen.code_sizes[lit] != 0);
                //warn("lit={c}, huff.litlen.codes[lit]={}, huff.litlen.code_sizes[lit]={}\n",
                //     lit, huff.litlen.codes[lit], huff.litlen.code_sizes[lit]);
                bb.put_fast(huff.litlen.codes[lit], huff.litlen.code_sizes[lit]);

                if (((flags & 1) == 1) or (i >= lz_code_buf.len)) {
                    break;
                }
            }
        }

        try bb.flush(output);
    }

    output.bits_in = 0;
    output.bit_buffer = 0;
    while (bb.bits_in > 0) {
        //bb.dump();
        const n = MIN(u6, bb.bits_in, 16);
        output.put_bits(truncmask(u32, bb.bit_buffer) & BITMASKS[n], n);
        bb.bit_buffer >>= n;
        bb.bits_in -= n;
    }

    // Output the end of block symbol.
    //warn("Output the end of block symbol\n");
    output.put_bits(huff.litlen.codes[256], huff.litlen.code_sizes[256]);
    //warn("Output the end of block symbol\n");

    return true;
}

fn flush_block(d: *Compressor, callback: *Callback, flush: TDEFLFlush) !u32 {
    //warn("flush_block\n");
    var saved_buffer: SavedOutputBuffer = undefined;
    {
        //callback.dump();
        var output = callback.out.new_output_buffer(
            &d.params.local_buf.b,
            d.params.out_buf_ofs,
        );
        output.bit_buffer = d.params.saved_bit_buffer;
        output.bits_in = d.params.saved_bits_in;

        const use_raw_block = ((d.params.flags & TDEFL_FORCE_ALL_RAW_BLOCKS) != 0) and
            ((d.dict.lookahead_pos - d.dict.code_buf_dict_pos) <= d.dict.size);

        assert(d.params.flush_remaining == 0);
        d.params.flush_ofs = 0;
        d.params.flush_remaining = 0;

        d.lz.init_flag();

        // If we are at the start of the stream, write the zlib header if requested.
        if (((d.params.flags & TDEFL_WRITE_ZLIB_HEADER) != 0) and (d.params.block_index == 0)) {
            output.put_bits(0x78, 8);
            output.put_bits(0x01, 8);
        }

        // Output the block header.
        output.put_bits(@boolToInt(flush == TDEFLFlush.Finish), 1);

        saved_buffer = output.save();

        var comp_success = false;
        if (!use_raw_block) {
            const use_static = ((d.params.flags & TDEFL_FORCE_ALL_STATIC_BLOCKS) != 0) or
                (d.lz.total_bytes < 48);
            comp_success = try d.huff.compress_block(&output, &d.lz, use_static);
        }

        // If we failed to compress anything and the output would take up more space than the output
        // data, output a stored block instead, which has at most 5 bytes of overhead.
        // We only use some simple heuristics for now.
        // A stored block will have an overhead of at least 4 bytes containing the block length
        // but usually more due to the length parameters having to start at a byte boundary and thus
        // requiring up to 5 bytes of padding.
        // As a static block will have an overhead of at most 1 bit per byte
        // (as literals are either 8 or 9 bytes), a raw block will
        // never take up less space if the number of input bytes are less than 32.
        const expanded = (d.lz.total_bytes > 32) and
            (output.inner.position() - saved_buffer.pos + 1 >= d.lz.total_bytes) and
            (d.dict.lookahead_pos - d.dict.code_buf_dict_pos <= d.dict.size);

        if (use_raw_block or expanded) {
            output.load(saved_buffer);

            // Block header.
            output.put_bits(0, 2);

            // Block length has to start on a byte boundary, so pad.
            output.pad_to_bytes();

            // Block length and ones complement of block length.
            output.put_bits(d.lz.total_bytes & 0xFFFF, 16);
            output.put_bits(~d.lz.total_bytes & 0xFFFF, 16);

            // Write the actual bytes.
            var i: usize = 0;
            //for i in 0..d.lz.total_bytes {
            while (i < d.lz.total_bytes) : (i += 1) {
                const pos = (d.dict.code_buf_dict_pos + i) & LZ_DICT_SIZE_MASK;
                output.put_bits(d.dict.b.dict[pos], 8);
            }
        } else if (!comp_success) {
            output.load(saved_buffer);
            _ = d.huff.compress_block(&output, &d.lz, true);
        }

        if (flush != TDEFLFlush.None) {
            if (flush == TDEFLFlush.Finish) {
                output.pad_to_bytes();
                if ((d.params.flags & TDEFL_WRITE_ZLIB_HEADER) != 0) {
                    var adler = d.params.adler32;
                    var i: usize = 0;
                    //for _ in 0..4 {
                    while (i < 4) : (i += 1) {
                        output.put_bits((adler >> 24) & 0xFF, 8);
                        adler <<= 8;
                    }
                }
            } else {
                output.put_bits(0, 3);
                output.pad_to_bytes();
                output.put_bits(0, 16);
                output.put_bits(0xFFFF, 16);
            }
        }

        setmem(u16, d.huff.litlen.count[0..MAX_HUFF_SYMBOLS_0], 0);
        setmem(u16, d.huff.dist.count[0..MAX_HUFF_SYMBOLS_1], 0);

        d.lz.code_position = 1;
        d.lz.flag_position = 0;
        d.lz.num_flags_left = 8;
        d.dict.code_buf_dict_pos += d.lz.total_bytes;
        d.lz.total_bytes = 0;
        d.params.block_index += 1;

        saved_buffer = output.save();

        d.params.saved_bit_buffer = saved_buffer.bit_buffer;
        d.params.saved_bits_in = saved_buffer.bits_in;
    }

    return callback.flush_output(saved_buffer, &d.params);
}

fn record_literal(h: *Huffman, lz: *LZ, lit: u8) void {
    //warn("record_literal(*, {c}/{x})\n", lit, lit);
    //lz.dump();
    lz.total_bytes += 1;
    lz.write_code(lit);

    (lz.get_flag()).* >>= 1;
    lz.consume_flag();

    h.litlen.count[lit] += 1;
}

fn record_match(h: *Huffman, lz: *LZ, pmatch_len: u32, pmatch_dist: u32) void {
    //warn("record_match(len={}, dist={})\n", pmatch_len, pmatch_dist);
    var match_len = pmatch_len;
    var match_dist = pmatch_dist;
    assert(match_len >= MIN_MATCH_LEN);
    assert(match_dist >= 1);
    assert(match_dist <= LZ_DICT_SIZE);

    lz.total_bytes += match_len;
    match_dist -= 1;
    match_len -= MIN_MATCH_LEN;
    assert(match_len < 256);
    lz.write_code(truncmask(u8, match_len));
    lz.write_code(truncmask(u8, match_dist));
    lz.write_code(truncmask(u8, match_dist >> 8));

    (lz.get_flag()).* >>= 1;
    (lz.get_flag()).* |= 0x80;
    lz.consume_flag();

    var symbol = if (match_dist < 512) SMALL_DIST_SYM[match_dist] else LARGE_DIST_SYM[((match_dist >> 8) & 127)];
    h.dist.count[symbol] += 1;
    h.litlen.count[LEN_SYM[match_len]] += 1;
}

fn compress_normal(d: *Compressor, callback: *Callback) bool {
    //warn("compress_normal\n");
    //callback.dump();
    var src_pos = d.params.src_pos;
    var in_buf = if (callback.in_buf) |in_buf| in_buf else return true;

    var lookahead_size = d.dict.lookahead_size;
    var lookahead_pos = d.dict.lookahead_pos;
    var saved_lit = d.params.saved_lit;
    var saved_match_dist = d.params.saved_match_dist;
    var saved_match_len = d.params.saved_match_len;

    while ((src_pos < in_buf.len) or ((d.params.flush != TDEFLFlush.None) and (lookahead_size != 0))) {
        const src_buf_left = in_buf.len - src_pos;
        const num_bytes_to_process =
            MIN(u32, truncmask(u32, src_buf_left), MAX_MATCH_LEN - lookahead_size);

        if ((lookahead_size + d.dict.size) >= (MIN_MATCH_LEN - 1) and (num_bytes_to_process > 0)) {
            var dictb = &d.dict.b;

            var dst_pos = (lookahead_pos + lookahead_size) & LZ_DICT_SIZE_MASK;
            var ins_pos = lookahead_pos + lookahead_size - 2;
            var hash = (u32(dictb.dict[(ins_pos & LZ_DICT_SIZE_MASK)]) <<
                                LZ_HASH_SHIFT) ^
                (dictb.dict[((ins_pos + 1) & LZ_DICT_SIZE_MASK)]);

            lookahead_size += num_bytes_to_process;
            for (in_buf[src_pos..src_pos + num_bytes_to_process]) |c| {
                dictb.dict[dst_pos] = c;
                if (dst_pos < (MAX_MATCH_LEN - 1)) {
                    dictb.dict[LZ_DICT_SIZE + dst_pos] = c;
                }

                hash = ((u32(hash) << LZ_HASH_SHIFT) ^ u32(c)) & u32(LZ_HASH_SIZE - 1);
                dictb.next[(ins_pos & LZ_DICT_SIZE_MASK)] = dictb.hash[hash];

                dictb.hash[hash] = @truncate(u16, ins_pos & 0xffff);
                dst_pos = (dst_pos + 1) & LZ_DICT_SIZE_MASK;
                ins_pos += 1;
            }
            src_pos += num_bytes_to_process;
        } else {
            var dictb = &d.dict.b;
            for (in_buf[src_pos..src_pos + num_bytes_to_process]) |c| {
                const dst_pos = (lookahead_pos + lookahead_size) & LZ_DICT_SIZE_MASK;
                dictb.dict[dst_pos] = c;
                //warn("c={c}, dst_pos={}\n", c, dst_pos);
                if (dst_pos < (MAX_MATCH_LEN - 1)) {
                     dictb.dict[LZ_DICT_SIZE + dst_pos] = c;
                    //warn("c={c}, dst_pos={}\n", c, dst_pos + LZ_DICT_SIZE);
                }

                lookahead_size += 1;
                if ((lookahead_size + d.dict.size) >= MIN_MATCH_LEN) {
                    const ins_pos = lookahead_pos + lookahead_size - 3;
                    //warn("ins_pos={}\n", ins_pos);
                    const hash =
                        ((u32(dictb.dict[(ins_pos & LZ_DICT_SIZE_MASK)]) <<
                          (LZ_HASH_SHIFT * 2)) ^
                         ((u32(dictb.dict[((ins_pos + 1) & LZ_DICT_SIZE_MASK)]) <<
                           LZ_HASH_SHIFT) ^
                          u32(c))) & u32(LZ_HASH_SIZE - 1);

                    dictb.next[(ins_pos & LZ_DICT_SIZE_MASK)] = dictb.hash[hash];
                    dictb.hash[hash] = @truncate(u16, ins_pos & 0xffff);
                }
            }

            src_pos += num_bytes_to_process;
        }

        d.dict.size = MIN(u32, LZ_DICT_SIZE - lookahead_size, d.dict.size);
        if ((d.params.flush == TDEFLFlush.None) and ((lookahead_size) < MAX_MATCH_LEN)) {
            break;
        }

        var len_to_move: u32 = 1;
        var cur_match_dist: u32 = 0;
        var cur_match_len = if (saved_match_len != 0) saved_match_len else (MIN_MATCH_LEN - 1);
        const cur_pos = (lookahead_pos & LZ_DICT_SIZE_MASK);
        if (d.params.flags & (TDEFL_RLE_MATCHES | TDEFL_FORCE_ALL_RAW_BLOCKS) != 0) {
            if ((d.dict.size != 0) and ((d.params.flags & TDEFL_FORCE_ALL_RAW_BLOCKS) == 0)) {
                const c = d.dict.b.dict[((cur_pos -% 1) & LZ_DICT_SIZE_MASK)];
                warn("NOT implemented\n");
                // cur_match_len = d.dict.b.dict[cur_pos..(cur_pos + lookahead_size)]
                //     .iter()
                //     .take_while(|&x| *x == c)
                //     .count() as u32;
                if (cur_match_len < MIN_MATCH_LEN) {
                    cur_match_len = 0;
                } else {
                    cur_match_dist = 1;
                }
            }
        } else {
            const dist_len = d.dict.find_match(
                lookahead_pos,
                d.dict.size,
                lookahead_size,
                cur_match_dist,
                cur_match_len,
            );
            //dist_len.dump();
            cur_match_dist = dist_len.distance;
            cur_match_len = dist_len.length;
        }

        const far_and_small = (cur_match_len == MIN_MATCH_LEN) and (cur_match_dist >= (8 * 1024));
        const filter_small = (((d.params.flags & TDEFL_FILTER_MATCHES) != 0) and (cur_match_len <= 5));
        if (far_and_small or filter_small or (cur_pos == cur_match_dist)) {
            cur_match_dist = 0;
            cur_match_len = 0;
        }

        //warn("cur_match_len={}, saved_match_len={}, saved_match_dist={}\n",
        //     cur_match_len, saved_match_len, saved_match_dist);
        if (saved_match_len != 0) {
            if (cur_match_len > saved_match_len) {
                record_literal(&d.huff, &d.lz, saved_lit);
                if (cur_match_len >= 128) {
                    record_match(&d.huff, &d.lz, cur_match_len, cur_match_dist);
                    saved_match_len = 0;
                    len_to_move = cur_match_len;
                } else {
                    saved_lit = d.dict.b.dict[cur_pos];
                    saved_match_dist = cur_match_dist;
                    saved_match_len = cur_match_len;
                }
            } else {
                record_match(&d.huff, &d.lz, saved_match_len, saved_match_dist);
                len_to_move = saved_match_len - 1;
                saved_match_len = 0;
            }
        } else if (cur_match_dist == 0) {
            record_literal(
                &d.huff,
                &d.lz,
                d.dict.b.dict[MIN(usize, cur_pos, d.dict.b.dict.len - 1)],
            );
        } else if ((d.params.greedy_parsing) or (d.params.flags & TDEFL_RLE_MATCHES != 0) or
                   (cur_match_len >= 128))
        {
            // If we are using lazy matching, check for matches at the next byte if the current
            // match was shorter than 128 bytes.
            record_match(&d.huff, &d.lz, cur_match_len, cur_match_dist);
            len_to_move = cur_match_len;
        } else {
            saved_lit = d.dict.b.dict[MIN(usize, cur_pos, d.dict.b.dict.len - 1)];
            saved_match_dist = cur_match_dist;
            saved_match_len = cur_match_len;
        }

        lookahead_pos += len_to_move;
        assert(lookahead_size >= len_to_move);
        lookahead_size -= len_to_move;
        d.dict.size = MIN(u32, d.dict.size + len_to_move, LZ_DICT_SIZE);

        const lz_buf_tight = d.lz.code_position > LZ_CODE_BUF_SIZE - 8;
        const raw = d.params.flags & TDEFL_FORCE_ALL_RAW_BLOCKS != 0;
        const fat = ((d.lz.code_position * 115) >> 7) >= d.lz.total_bytes;
        const fat_or_raw = (d.lz.total_bytes > 31 * 1024) and (fat or raw);

        if (lz_buf_tight or fat_or_raw) {
            d.params.src_pos = src_pos;
            // These values are used in flush_block, so we need to write them back here.
            d.dict.lookahead_size = lookahead_size;
            d.dict.lookahead_pos = lookahead_pos;

            const n = flush_block(d, callback, TDEFLFlush.None) catch 0;
            //.unwrap_or(
            //    TDEFLStatus.PutBufFailed as
            //        i32,
            if (n != 0) {
                d.params.saved_lit = saved_lit;
                d.params.saved_match_dist = saved_match_dist;
                d.params.saved_match_len = saved_match_len;
                return (n > 0);
            }
        }
    }

    d.params.src_pos = src_pos;
    d.dict.lookahead_size = lookahead_size;
    d.dict.lookahead_pos = lookahead_pos;
    d.params.saved_lit = saved_lit;
    d.params.saved_match_dist = saved_match_dist;
    d.params.saved_match_len = saved_match_len;

    d.dict.dump();

    return true;
}


const COMP_FAST_LOOKAHEAD_SIZE: u32 = 4096;

fn compress_fast(d: *Compressor, callback: *Callback)  bool {
    warn("compress_fast\n");
    var src_pos = d.params.src_pos;
    var lookahead_size = d.dict.lookahead_size;
    var lookahead_pos = d.dict.lookahead_pos;

    var cur_pos = lookahead_pos & LZ_DICT_SIZE_MASK;
    const in_buf = if (callback.in_buf) |buf|  buf else return true;
    // let in_buf = match callback.in_buf {
    //     None => return true,
    //     Some(in_buf) => in_buf,
    // };

    assert(d.lz.code_position < (LZ_CODE_BUF_SIZE - 2));

    while ((src_pos < in_buf.len) or ((d.params.flush != TDEFLFlush.None) and (lookahead_size > 0))) {
        var dst_pos: usize = ((lookahead_pos + lookahead_size) & LZ_DICT_SIZE_MASK);
        var num_bytes_to_process = MIN(usize, in_buf.len - src_pos, (COMP_FAST_LOOKAHEAD_SIZE - lookahead_size));
        lookahead_size += truncmask(@typeOf(lookahead_size), num_bytes_to_process);

        while (num_bytes_to_process != 0) {
            const n = MIN(usize, LZ_DICT_SIZE - dst_pos, num_bytes_to_process);
            //d.dict.b.dict[dst_pos..dst_pos + n].copy_from_slice(&in_buf[src_pos..src_pos + n]);
            for (in_buf[src_pos..src_pos + n]) |*b, ii| {
                d.dict.b.dict[dst_pos + ii] = b.*;
            }

            if (dst_pos < (MAX_MATCH_LEN - 1)) {
                const m = MIN(usize, n, MAX_MATCH_LEN - 1 - dst_pos);
                // d.dict.b.dict[dst_pos + LZ_DICT_SIZE..dst_pos + LZ_DICT_SIZE + m]
                //     .copy_from_slice(&in_buf[src_pos..src_pos + m]);
                for (in_buf[src_pos..src_pos + m]) |*b, ii| {
                    d.dict.b.dict[dst_pos + LZ_DICT_SIZE + ii] = b.*;
                }
            }

            src_pos += n;
            dst_pos = (dst_pos + n) & LZ_DICT_SIZE_MASK;
            num_bytes_to_process -= n;
        }

        d.dict.size = MIN(u32, LZ_DICT_SIZE - lookahead_size, d.dict.size);
        if ((d.params.flush == TDEFLFlush.None) and (lookahead_size < COMP_FAST_LOOKAHEAD_SIZE)) {
            break;
        }

        while (lookahead_size >= 4) {
            var cur_match_len: u32 = 1;
            // # Unsafe
            // cur_pos is always masked when assigned to.
            //         let first_trigram = unsafe {
            //             u32::from_le(d.dict.read_unaligned::<u32>(cur_pos as isize)) & 0xFF_FFFF
            //         };
            var first_trigram: u32 = d.dict.read_unaligned(u32, cur_pos) & 0xFFFFFF;

            const hash = (first_trigram ^ (first_trigram >> (24 - (LZ_HASH_BITS - 8)))) &
                LEVEL1_HASH_SIZE_MASK;

            var probe_pos: u32 = d.dict.b.hash[hash];
            d.dict.b.hash[hash] = truncmask(u16, lookahead_pos);

            var cur_match_dist = truncmask(u16, lookahead_pos - probe_pos);
            if (cur_match_dist <= d.dict.size) {
                probe_pos &= LZ_DICT_SIZE_MASK;
                // # Unsafe
                // probe_pos was just masked so it can't exceed the dictionary size + max_match_len.
                // let trigram = unsafe {
                //     u32::from_le(d.dict.read_unaligned::<u32>(probe_pos as isize)) & 0xFF_FFFF
                // };
                var trigram = d.dict.read_unaligned(u32, probe_pos) & 0xFFFFFF;

                if (first_trigram == trigram) {
                    // Trigram was tested, so we can start with "+ 3" displacement.
                    var p = (cur_pos + 3);
                    var q = (probe_pos + 3);
                    cur_match_len = find_match: {
                        var i: usize = 0;
                        while (i < 32) : (i += 1) {
                            // # Unsafe
                            // This loop has a fixed counter, so p_data and q_data will never be
                            // increased beyond 251 bytes past the initial values.
                            // Both pos and probe_pos are bounded by masking with
                            // LZ_DICT_SIZE_MASK,
                            // so {pos|probe_pos} + 258 will never exceed dict.len().
                            // (As long as dict is padded by one additional byte to have
                            // 259 bytes of lookahead since we start at cur_pos + 3.)
                            const p_data: u64 = d.dict.read_unaligned(u64, p);
                            //              unsafe {u64::from_le(d.dict.read_unaligned(p as isize))};
                            const q_data: u64 = d.dict.read_unaligned(u64, q);
                            //              unsafe {u64::from_le(d.dict.read_unaligned(q as isize))};
                            const xor_data = p_data ^ q_data;
                            if (xor_data == 0) {
                                p += 8;
                                q += 8;
                            } else {
                                const trailing = @ctz(xor_data);
                                break :find_match truncmask(u32, p) - cur_pos + (trailing >> 3);
                            }
                        }

                        if (cur_match_dist == 0) {
                            break :find_match u32(0);
                        } else {
                            break :find_match u32(MAX_MATCH_LEN);
                        }
                    };

                    if ((cur_match_len < MIN_MATCH_LEN) or ((cur_match_len == MIN_MATCH_LEN) and (cur_match_dist >= 8 * 1024)))
                    {
                        const lit = truncmask(u8, first_trigram);
                        cur_match_len = 1;
                        d.lz.write_code(lit);
                        (d.lz.get_flag()).* >>= 1;
                        d.huff.litlen.count[lit] += 1;
                    } else {
                        // Limit the match to the length of the lookahead so we don't create a match
                        // that ends after the end of the input data.
                        cur_match_len = MIN(@typeOf(cur_match_len), cur_match_len, lookahead_size);
                        assert(cur_match_len >= MIN_MATCH_LEN);
                        assert(cur_match_dist >= 1);
                        assert(cur_match_dist <= LZ_DICT_SIZE);
                        cur_match_dist -= 1;

                        d.lz.write_code(truncmask(u8, cur_match_len - MIN_MATCH_LEN));
                        // # Unsafe
                        // code_position is checked to be smaller than the lz buffer size
                        // at the start of this function and on every loop iteration.
                        //  unsafe {
                        write_u16_le_uc(truncmask(u16, cur_match_dist),
                                        d.lz.codes[0..],
                                        d.lz.code_position);
                        d.lz.code_position += 2;
                        //  }

                        (d.lz.get_flag()).* >>= 1;
                        (d.lz.get_flag()).* |= 0x80;
                        if (cur_match_dist < 512) {
                            d.huff.dist.count[SMALL_DIST_SYM[cur_match_dist]] += 1;
                        } else {
                            d.huff.dist.count[LARGE_DIST_SYM[(cur_match_dist >> 8)]] += 1;
                        }

                        d.huff.litlen.count[LEN_SYM[(cur_match_len - MIN_MATCH_LEN)]] += 1;
                    }
                } else {
                    d.lz.write_code(truncmask(u8, first_trigram));
                    (d.lz.get_flag()).* >>= 1;
                    d.huff.litlen.count[truncmask(u8, first_trigram)] += 1;
                }

                d.lz.consume_flag();
                d.lz.total_bytes += cur_match_len;
                lookahead_pos += cur_match_len;
                d.dict.size = MIN(@typeOf(d.dict.size), d.dict.size + cur_match_len, LZ_DICT_SIZE);
                cur_pos = (cur_pos + cur_match_len) & LZ_DICT_SIZE_MASK;
                assert(lookahead_size >= cur_match_len);
                lookahead_size -= cur_match_len;

                if (d.lz.code_position > (LZ_CODE_BUF_SIZE - 8)) {
                    // These values are used in flush_block, so we need to write them back here.
                    d.dict.lookahead_size = lookahead_size;
                    d.dict.lookahead_pos = lookahead_pos;
                    var n: u32 = 0;
                    if (flush_block(d, callback, TDEFLFlush.None)) |nn| {
                        n = nn;
                    } else |err| {
                        d.params.src_pos = src_pos;
                        d.params.prev_return_status = TDEFLStatus.PutBufFailed;
                        return false;
                    }
                    //  let n = match flush_block(d, callback, TDEFLFlush::None) {
                    //      Err(_) => {
                    //          d.params.src_pos = src_pos;
                    //          d.params.prev_return_status = TDEFLStatus::PutBufFailed;
                    //          return false;
                    //      }
                    //      Ok(status) => status,
                    //  };
                    if (n != 0) {
                        d.params.src_pos = src_pos;
                        return n > 0;
                    }
                    assert(d.lz.code_position < (LZ_CODE_BUF_SIZE - 2));

                    lookahead_size = d.dict.lookahead_size;
                    lookahead_pos = d.dict.lookahead_pos;
                }
            }
        }

        while (lookahead_size != 0) {
            const lit = d.dict.b.dict[cur_pos];
            d.lz.total_bytes += 1;
            d.lz.write_code(lit);
            (d.lz.get_flag()).* >>= 1;
            d.lz.consume_flag();

            d.huff.litlen.count[lit] += 1;
            lookahead_pos += 1;
            d.dict.size = MIN(@typeOf(d.dict.size), d.dict.size + 1, LZ_DICT_SIZE);
            cur_pos = (cur_pos + 1) & LZ_DICT_SIZE_MASK;
            lookahead_size -= 1;

            if (d.lz.code_position > (LZ_CODE_BUF_SIZE - 8)) {
                // These values are used in flush_block, so we need to write them back here.
                d.dict.lookahead_size = lookahead_size;
                d.dict.lookahead_pos = lookahead_pos;

                var n: u32 = 0;
                if (flush_block(d, callback, TDEFLFlush.None)) |nn| {
                    n = nn;
                } else |err| {
                    d.params.prev_return_status = TDEFLStatus.PutBufFailed;
                    d.params.src_pos = src_pos;
                    return false;
                }
                //let n = match flush_block(d, callback, TDEFLFlush.None) {
                //    Err(_) => {
                //        d.params.prev_return_status = TDEFLStatus.PutBufFailed;
                //        d.params.src_pos = src_pos;
                //        return false;
                //    }
                //    Ok(status) => status,
                //};
                if (n != 0) {
                    d.params.src_pos = src_pos;
                    return n > 0;
                }

                lookahead_size = d.dict.lookahead_size;
                lookahead_pos = d.dict.lookahead_pos;
            }
        }
    }

    d.params.src_pos = src_pos;
    d.dict.lookahead_size = lookahead_size;
    d.dict.lookahead_pos = lookahead_pos;
    return true;
}

fn flush_output_buffer(cb: *Callback, p: *Params) CompressionResult {
    //warn("flush_output_buffer remaining={}\n", p.flush_remaining);
    var res = CompressionResult.new(TDEFLStatus.Okay, p.src_pos, 0);
    switch (cb.out) {
        CallbackOut.Buf => |ob| {
            const n = MIN(usize, ob.out_buf.len - p.out_buf_ofs, p.flush_remaining);
            if (n > 0) {
                for (p.local_buf.b[p.flush_ofs..p.flush_ofs + n]) |*b, ii|{
                    ob.out_buf[p.out_buf_ofs + ii] = b.*;
                }
            }
            const nn = truncmask(u32, n);
            p.flush_ofs += nn;
            p.flush_remaining -= nn;
            p.out_buf_ofs += nn;
            res.outpos = p.out_buf_ofs;
        },
        else => {},
    }
    //}

    if (p.finished and (p.flush_remaining == 0)) {
        res.status = TDEFLStatus.Done;
    }

    return res;
}

fn compress_inner(d: *Compressor, callback: *Callback,
                  pflush: TDEFLFlush) CompressionResult {
    //warn("compress_inner\n");
    var res: CompressionResult = undefined;
    var flush = pflush;
    d.params.out_buf_ofs = 0;
    d.params.src_pos = 0;

    var prev_ok = d.params.prev_return_status == TDEFLStatus.Okay;
    var flush_finish_once = (d.params.flush != TDEFLFlush.Finish) or (flush == TDEFLFlush.Finish);

    d.params.flush = flush;
    if (!prev_ok or !flush_finish_once) {
        d.params.prev_return_status = TDEFLStatus.BadParam;
        res = CompressionResult.new(d.params.prev_return_status, 0, 0);
        return res;
    }

    if ((d.params.flush_remaining != 0) or d.params.finished) {
        res = flush_output_buffer(callback, &d.params);
        d.params.prev_return_status = res.status;
        return res;
    }

    const one_probe = (d.params.flags & MAX_PROBES_MASK) == 1;
    const greedy = (d.params.flags & TDEFL_GREEDY_PARSING_FLAG) != 0;
    const filter_or_rle_or_raw = (d.params.flags & (TDEFL_FILTER_MATCHES
                                                    | TDEFL_FORCE_ALL_RAW_BLOCKS
                                                    | TDEFL_RLE_MATCHES)) != 0;

    warn("XXX {} {} {}\n", one_probe, greedy, filter_or_rle_or_raw);
    const compress_success = if (one_probe and greedy and !filter_or_rle_or_raw)
        compress_fast(d, callback) else compress_normal(d, callback);

    if (!compress_success) {
        return CompressionResult.new(d.params.prev_return_status, d.params.src_pos, d.params.out_buf_ofs);
    }

    if (callback.in_buf) |in_buf| {
        if ((d.params.flags & (TDEFL_WRITE_ZLIB_HEADER | TDEFL_COMPUTE_ADLER32)) != 0) {
            d.params.adler32 = adler32(d.params.adler32, in_buf[0..d.params.src_pos]);
        }
    }

    callback.dump();

    const flush_none = (d.params.flush == TDEFLFlush.None);
    //const in_left = callback.in_buf.len - d.params.src_pos; //callback.in_buf.map_or(0, |buf| buf.len()) - d.params.src_pos;
    const in_left = if (callback.in_buf) |buf| (buf.len - d.params.src_pos) else 0;
    const remaining = (in_left != 0) or (d.params.flush_remaining != 0);
    if (!flush_none and (d.dict.lookahead_size == 0) and !remaining) {
        warn("@@@ remaining={}\n", remaining);
        flush = d.params.flush;
        if (flush_block(d, callback, flush)) |n| {
            warn("@@@ {}\n", n);
            if (n < 0) {
                res.status = d.params.prev_return_status;
                res.inpos = d.params.src_pos;
                res.outpos = d.params.out_buf_ofs;
                return res;
            }

        } else |err| {
            d.params.prev_return_status = TDEFLStatus.PutBufFailed;
            res.status = d.params.prev_return_status;
            res.inpos = d.params.src_pos;
            res.outpos = d.params.out_buf_ofs;
            return res;
        }
        // match  {
        //     Err(_) => {
        //         d.params.prev_return_status = TDEFLStatus::PutBufFailed;
        //         return (
        //             d.params.prev_return_status,
        //             d.params.src_pos,
        //             d.params.out_buf_ofs,
        //         );
        //     }
        //     Ok(x) if x < 0 => {
        //         return (
        //             d.params.prev_return_status,
        //             d.params.src_pos,
        //             d.params.out_buf_ofs,
        //         )
        //     }
        //     _ => {
        warn("akkar\n");
        d.params.finished = d.params.flush == TDEFLFlush.Finish;
        if (d.params.flush == TDEFLFlush.Full) {
            warn("full flush\n");
            setmem(u16, d.dict.b.hash[0..], 0);
            setmem(u16, d.dict.b.next[0..], 0);
            d.dict.size = 0;
        }
    }

    res = flush_output_buffer(callback, &d.params);
    d.params.prev_return_status = res.status;

    return res;
}

/// Main compression function. Puts output into buffer.
///
/// # Returns
/// Returns a tuple containing the current status of the compressor, the current position
/// in the input buffer and the current position in the output buffer.
pub fn compress(d: *Compressor, in_buf: []u8, out_buf: []u8,
                flush: TDEFLFlush) CompressionResult {
    //warn("compress\n");
    var callback = Callback.new_callback_buf(in_buf, out_buf);
    //callback.dump();
    return compress_inner(d, &callback, flush);
}

/// Create a set of compression flags using parameters used by zlib and other compressors.
pub fn create_comp_flags_from_zip_params(level: u32, window_bits: u32, strategy: i32) u32 {
    const num_probes: usize = if (level >= 0) MIN(usize, 10, level) else CompressionLevel.DefaultLevel;
    const greedy = if (level <= 3) TDEFL_GREEDY_PARSING_FLAG else 0;
    var comp_flags: u32 = NUM_PROBES[num_probes] | greedy;

    if (window_bits > 0) {
        comp_flags |= TDEFL_WRITE_ZLIB_HEADER;
    }

    if (level == 0) {
        comp_flags |= TDEFL_FORCE_ALL_RAW_BLOCKS;
    } else if (strategy == @enumToInt(CompressionStrategy.Filtered)) {
        comp_flags |= TDEFL_FILTER_MATCHES;
    } else if (strategy == @enumToInt(CompressionStrategy.HuffmanOnly)) {
        comp_flags &= ~@typeOf(comp_flags)(MAX_PROBES_MASK);
    } else if (strategy == @enumToInt(CompressionStrategy.Fixed)) {
        comp_flags |= TDEFL_FORCE_ALL_STATIC_BLOCKS;
    } else if (strategy == @enumToInt(CompressionStrategy.RLE)) {
        comp_flags |= TDEFL_RLE_MATCHES;
    }

    return comp_flags;
}

test "compression flags" {
    var flags = create_comp_flags_from_zip_params(9, 15, 0);
    warn("flags={x08}\n", flags);
}


test "Write U16" {
    var slice = [2]u8 {0, 0};
    write_u16_le(0x07d0, slice[0..], 0);
    assert(slice[0] == 0xd0);
    assert(slice[1] == 0x07);
    setmem(u8, slice[0..], 0);
    write_u16_le_uc(2000, slice[0..], 0);
    assert(slice[0] == 208);
    assert(slice[1] == 7);
}

test "Read U16" {
    var slice = []u8 {0xd0, 0x07};
    var v: u16 = read_u16_le(slice[0..], 0);
    assert(v == 2000);
    assert(v == 0x07d0);
}

test "Default Huffman" {
    var h = Huffman.init();
    warn("sizeof HuffmanEntry={}\n", usize(@sizeOf(HuffmanEntry)));
    warn("sizeof Huffman={}\n", usize(@sizeOf(Huffman)));
    warn("sizeof LZ={}\n", usize(@sizeOf(LZ)));
    // h.start_static_block();
}

test "Cursor"  {
    var buf = []u8 {0} ** 64;
    var cursor: Cursor([]u8)  = undefined;
    cursor.init(buf[0..]);
    cursor.dump();
}

test "Compressor" {
    var c: Compressor = undefined;
    c.initialize(create_comp_flags_from_zip_params(6, 15, 0));
    var input = "Deflate late";
    warn("Compressing '{}' {x08}, {}\n", input, adler32(1, input[0..]), input.len);
    var output = []u8 {0} ** 2000;
    // "\xcb\x49\x2c\x49\x55\xc8\x49\x04\x11\xa9\x00\x00\x00"
    var r = c.compress(input[0..], output[0..], TDEFLFlush.Finish);
    r.dump();
    warn("\"");
    for (output) |b, i| {
        warn("\\x{x02}", b);
        if (i > r.outpos) {
            break;
        }
    }
    warn("\"\n");
    c.dict.dump();
    warn("done..{}\n", @enumToInt(builtin.mode));
}

test "Compress File" {
    const os = std.os;
    const io = std.io;
    var raw_bytes: [4 * 1024]u8 = undefined;
    var allocator = &std.heap.FixedBufferAllocator.init(raw_bytes[0..]).allocator;
    const tmp_file_name = "input.txt";
    var file = try os.File.openRead(allocator, tmp_file_name);
    defer file.close();

    const file_size = try file.getEndPos();

    warn("File has {} bytes\n", file_size);
    var file_in_stream = io.FileInStream.init(&file);
    var buf_stream = io.BufferedInStream(io.FileInStream.Error).init(&file_in_stream.stream);
    const st = &buf_stream.stream;
    const contents = try st.readAllAlloc(allocator, 2 * 1024);
    warn("contents has {} bytes, adler32={x08}\n", contents.len, adler32(1, contents[0..]));
    defer allocator.free(contents);

    var input = @embedFile("input.txt");

    warn("{x08} vs {x08}\n", adler32(MZ_ADLER32_INIT, input), adler32(MZ_ADLER32_INIT, contents));
    //assert(mem.eql(u8, input, contents));
    var c: Compressor = undefined;
    c.initialize(create_comp_flags_from_zip_params(9, 15, 0));

    var output = []u8 {0} ** (2 * 1024);
    var r = compress(&c, input[0..], output[0..], TDEFLFlush.Finish);
    r.dump();
    for (output) |b, i| {
        warn("\\x{x02}", b);
        if (i > r.outpos) {
            break;
        }
    }
}
