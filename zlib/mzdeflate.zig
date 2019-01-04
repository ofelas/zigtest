// -*- mode:zig; indent-tabs-mode:nil;  -*-

const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;
const assert = std.debug.assert;
const assertError = std.debug.assertError;
const assertOrPanic = std.debug.assertOrPanic;
const builtin = @import("builtin");

const crc32 = std.hash.crc.Crc32;
const adler32 = @import("adler32.zig").adler32;
const mzutil = @import("mzutil.zig");
const Cursor = mzutil.Cursor;
const MIN = mzutil.MIN;
const MAX = mzutil.MAX;
const OutputBuffer = mzutil.OutputBuffer;
const SavedOutputBuffer = mzutil.SavedOutputBuffer;
const SeekFrom = mzutil.SeekFrom;
const setmem = mzutil.setmem;
const typeNameOf = mzutil.typeNameOf;
const deriveDebug = mzutil.deriveDebug;

const maxValue = mzutil.maxValue;

// License MIT
// From https://github.com/Frommi/miniz_oxide
//! Streaming compression functionality.

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

pub const HUFFMAN_LENGTH_ORDER = []u8 {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};

const MZ_ADLER32_INIT = 1;
const MAX_PROBES_MASK = 0xFFF;
const MAX_SUPPORTED_HUFF_CODESIZE = 32;

/// Length code for length values.
const LEN_SYM: [256]u16 = []const u16 {
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
const LEN_EXTRA: [256]u8 = []const u8 {
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
const SMALL_DIST_SYM: [512]u8 = []const u8 {
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
const SMALL_DIST_EXTRA: [512]u8 = []const u8 {
    0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7
};

/// Base values to calculate distances above 512.
//#[cfg_attr(rustfmt, rustfmt_skip)]
const LARGE_DIST_SYM: [128]u8 = []const u8 {
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
const LARGE_DIST_EXTRA: [128]u4 = []const u4 {
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
const BITMASKS: [17]u16 = []const u16 {
    0x0000, 0x0001, 0x0003, 0x0007, 0x000F, 0x001F, 0x003F, 0x007F, 0x00FF,
    0x01FF, 0x03FF, 0x07FF, 0x0FFF, 0x1FFF, 0x3FFF, 0x7FFF, 0xFFFF
};

/// The maximum number of checks for matches in the hash table the compressor will make for each
/// compression level.
const NUM_PROBES: [11]u16 = []const u16 {0, 1, 6, 32, 16, 32, 128, 256, 512, 768, 1500};

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

fn LZ_DICT_POS(pos: u32) u32 {
    return pos &  u32(LZ_DICT_SIZE_MASK);
}

const COMP_FAST_LOOKAHEAD_SIZE: u32 = 4096;

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
    const Self = @This();
    None = 0,
    Sync = 2,
    Full = 3,
    Finish = 4,

    fn from_u32(flush: u32) !Self {
        return switch (flush) {
            0 => TDEFLFlush.None,
            2 => TDEFLFlush.Sync,
            3 => TDEFLFlush.Full,
            4 => TDEFLFlush.Finish,
            else => error.BadParam,
         };
     }
};

//#[derive(Copy, Clone)]
const SymFreq = struct {
    const Self = @This();
    key: u16,
    sym_index: u16,

    fn format(
        self: *const Self,
        comptime fmt: []const u8,
        context: var,
        comptime Errors: type,
        output: fn (@typeOf(context), []const u8) Errors!void,
    ) Errors!void {
        // We hereby take over all printing...
        return deriveDebug(context, "{}", Errors, output, self.*, 0);
    }
};

const debug = false;

fn radix_sort_symbols(symbols0: []SymFreq, symbols1: []SymFreq) []SymFreq {
    if (debug) warn("radix_sort_symbols s0.len={}, s1.len={}\n", symbols0.len, symbols1.len);
    var hist = [][256]u16 {[]u16 {0} ** 256} ** 2;
    assert(symbols0.len == symbols1.len);

    for (symbols0) |*freq| {
        hist[0][@truncate(u8, freq.*.key)] += 1;
        hist[1][@truncate(u8, (freq.*.key >> 8))] += 1;
    }

    var current_symbols = symbols0;
    var new_symbols = symbols1;

    const n_passes: u4 = 2 - u4(@boolToInt(symbols0.len == hist[1][0]));
    var pass: @typeOf(n_passes) = 0;
    // for pass in 0..n_passes {
    while (pass < n_passes) : (pass += 1) {
        var offsets = []u16 {0} ** 256;
        var offset: u16 = 0;
        // for i in 0..256 {
        for (offsets) |*ofp, ii| {
            ofp.* = offset;
            offset += hist[pass][ii];
        }

        for (current_symbols) |*sym| {
            const idx = (sym.*.key >> (pass * 8)) & 0xff;
            new_symbols[offsets[idx]] = sym.*;
            offsets[idx] += 1;
        }

        mem.swap(@typeOf(current_symbols), &current_symbols, &new_symbols);
    }
    if (debug) {
        for (current_symbols) |*sym, ii| {
            warn("[{}]={}\n", ii, sym);
        }
    }

    return current_symbols;
}

fn calculate_minimum_redundancy(symbols: []SymFreq) void {
    if (debug) warn("calculate_minimum_redundancy, symbols.len={}\n", symbols.len);
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
                    symbols[root].key = @truncate(u16, next);
                    root += 1;
                } else {
                    symbols[next].key = symbols[leaf].key;
                    leaf += 1;
                }

                if ((leaf >= n) or ((root < next) and (symbols[root].key < symbols[leaf].key))) {
                    symbols[next].key = symbols[next].key +% symbols[root].key;
                    symbols[root].key = @truncate(u16, next);
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
            var inext = @bitCast(isize, n) - 3;
            while (inext >= 0) : (inext -= 1) {
                const idx = @bitCast(usize, inext);
                symbols[idx].key = symbols[symbols[idx].key].key + 1;
            }

            var avbl: usize = 1;
            var used: usize = 0;
            var dpth: usize = 0;
            var iroot = @bitCast(isize, n) - 2;
            inext = @bitCast(isize, n) - 1;
            while (avbl > 0) {
                while ((iroot >= 0) and (symbols[@bitCast(usize, iroot)].key == dpth)) {
                    used += 1;
                    iroot -= 1;
                }
                while (avbl > used) {
                    assert(inext >= 0);
                    symbols[@bitCast(usize, inext)].key = @truncate(u16, dpth);
                    inext -= 1;
                    avbl -= 1;
                }
                avbl = 2 * used;
                dpth += 1;
                used = 0;
            }
        }
    }
    if (debug) warn("calculate_minimum_redundancy done\n");
}

fn enforce_max_code_size(num_codes: []i32, code_list_len: usize, max_code_size: usize) void {
    if (debug) warn("num_codes.len={}, code_list_len={}, max_code_size={}\n",
                    num_codes.len, code_list_len, max_code_size);

    if (code_list_len <= 1) {
        return;
    }

    // num_codes[max_code_size] += num_codes[max_code_size + 1..].iter().sum::<i32>();
    for (num_codes[max_code_size + 1..]) |v| {
        num_codes[max_code_size] += v;
    }
    // let total = num_codes[1..max_code_size + 1]
    //     .iter()
    //     .rev()
    //     .enumerate()
    //     .fold(0u32, |total, (i, &x)| total + ((x as u32) << i));
    var total: u32 = 0;
    var i = max_code_size;
    while (i >= 1) : (i -= 1) {
        total += (@bitCast(u32, num_codes[i]) << @truncate(u5, max_code_size - i));
    }
    var x = (u32(1) << @truncate(u5, max_code_size));
    // for _ in (1 << max_code_size)..total {
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

test "tdefl flush" {
    var flush = TDEFLFlush.from_u32(0) catch TDEFLFlush.Finish;
    assert(flush == TDEFLFlush.None);
    flush = TDEFLFlush.from_u32(2) catch TDEFLFlush.None;
    assert(flush == TDEFLFlush.Sync);
    flush = TDEFLFlush.from_u32(3) catch TDEFLFlush.None;
    assert(flush == TDEFLFlush.Full);
    flush = TDEFLFlush.from_u32(4) catch TDEFLFlush.None;
    assert(flush == TDEFLFlush.Finish);
    assertError(TDEFLFlush.from_u32(1), error.BadParam);
    assertError(TDEFLFlush.from_u32(5), error.BadParam);
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
    const Self = @This();
    BadParam = -2,
    PutBufFailed = -1,
    Okay = 0,
    Done = 1,

    pub fn format(
        self: *const Self,
        comptime fmt: []const u8,
        context: var,
        comptime Errors: type,
        output: fn (@typeOf(context), []const u8) Errors!void,
    ) Errors!void {
        return deriveDebug(context, "{}", Errors, output, self.*, 0);
    }
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

fn write_u16_le(val: u16, slice: []u8, pos: usize) void {
    assert((@sizeOf(u16) + pos) <= slice.len);
    mem.writeIntSlice(u16, slice[pos..pos+@sizeOf(u16)], val, builtin.Endian.Little);
}

fn write_u16_le_uc(val: u16, slice: []u8, pos: usize) void {
    // ptr::write_unaligned(slice.as_mut_ptr().offset(pos as isize) as *mut u16, val);
    assert((@sizeOf(@typeOf(val)) + pos) <= slice.len);
    mem.writeIntSlice(u16, slice[pos..pos+@sizeOf(u16)], val, builtin.Endian.Little);
}

fn read_u16_le(slice: []u8, pos: usize) u16 {
    assert(pos + 1 < slice.len);
    assert(pos < slice.len);
    return mem.readIntSlice(u16, slice[pos..pos+@sizeOf(u16)], builtin.Endian.Little);
}

/// A struct containing data about huffman codes and symbol frequencies.
///
/// NOTE: Only the literal/lengths have enough symbols to actually use
/// the full array. It's unclear why it's defined like @This() in miniz,
/// it could be for cache/alignment reasons.
pub const HuffmanEntry = struct {
    const Self = @This();
    /// Number of occurrences of each symbol.
    pub count: [MAX_HUFF_SYMBOLS]u16,
    /// The bits of the huffman code assigned to the symbol
    pub codes: [MAX_HUFF_SYMBOLS]u16,
    /// The length of the huffman code assigned to the symbol.
    pub code_sizes: [MAX_HUFF_SYMBOLS]u6,

    fn optimize_table(self: *Self, table_len: usize,
                      code_size_limit: usize, static_table: bool) void {
        if (debug) {
            warn("{} table_len={}, code_size_limit={}, static_table={}\n",
                 self, table_len, code_size_limit, static_table);
        }
        var num_codes = []i32 {0} ** (MAX_SUPPORTED_HUFF_CODESIZE + 1);
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
                    // symbols0[num_used_symbols] = SymFreq {
                    //      .key = self.count[i],
                    //      .sym_index = @truncate(u16, i),
                    // };
                    symbols0[num_used_symbols].key = self.count[i];
                    symbols0[num_used_symbols].sym_index = @truncate(u16, i);
                    //symbols0[num_used_symbols].dump();
                    num_used_symbols += 1;
                }
            }
            if (debug) warn("num_used_symbols={}\n", num_used_symbols);
            const symbols = radix_sort_symbols(symbols0[0..num_used_symbols],
                                               symbols1[0..num_used_symbols]);

            calculate_minimum_redundancy(symbols);

            for (symbols) |*symbol| {
                num_codes[symbol.*.key] += 1;
            }

            enforce_max_code_size(num_codes[0..], num_used_symbols, code_size_limit);

            setmem(u6, self.code_sizes[0..], 0);
            setmem(u16, self.codes[0..], 0);

            var last: usize = num_used_symbols;
            // for i in 1..code_size_limit + 1 {
            i = 1;
            while (i < (code_size_limit + 1)) : (i += 1) {
                const first: usize = last - @bitCast(u32, num_codes[i]);
                //warn("first={}, last={}\n", first, last);
                for (symbols[first..last]) |*symbol| {
                    self.code_sizes[symbol.*.sym_index] = @truncate(u6, i);
                }
                last = first;
            }
        }

        var j: u32 = 0;
        next_code[1] = 0;
        var i: usize = 2;
        //for i in 2..code_size_limit + 1 {
        while (i < (code_size_limit + 1)) : (i += 1) {
            j = (j + @bitCast(u32, num_codes[i - 1])) << 1;
            next_code[i] = j;
        }

        i = 0;
        while (i < table_len) : (i += 1) {
            const code_size = &self.code_sizes[i];
            const huff_code = &self.codes[i];
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
            //warn("i={}, j={}, rev_code={x04}\n", i, j, rev_code);
            huff_code.* = @truncate(u16, rev_code);
        }
    }

};

// inline makes @This() fail
fn copy_from_slice(comptime D: type, dest: []D, comptime S: type, src: []S) void {
    // warn("copy_from_slice({} <- {})\n", @typeName(D), @typeName(S));
    // choose between var runs or warn("") in the loops or else @This()
    // fails to do what we expect.
    // for and while has the same problem.
    var i: usize = 0;
    {
        @setRuntimeSafety(false);
        assert(dest.len >= src.len);
        // could check the signedness
        if (D.bit_count >= S.bit_count) {
            for (src) |v, ii| {
                dest[ii] = v;
                i += 1;
            }
        } else {
            @compileLog("cannot copy ", S, " to ", D);
        }
        // i = 0;
        // while (i < dest.len) : (i += 1) {
        //     dest[i] = src[i];
        // }
    }
    // @This() if and warn must be present
    // release-safe -> reached unreachable code
    if (i > dest.len) {
        warn("i={}, dest.len{}\n", i, dest.len);
    }
}

pub const Huffman = struct {
    const Self = @This();
    litlen: HuffmanEntry,
    dist: HuffmanEntry,
    huffcodes: HuffmanEntry,

    fn format(
        self: *const Self,
        comptime fmt: []const u8,
        context: var,
        comptime Errors: type,
        output: fn (@typeOf(context), []const u8) Errors!void,
    ) Errors!void {
        // We hereby take over all printing...
        return deriveDebug(context, "{}", Errors, output, self.*, 0);
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
        if (static_block) {
            self.start_static_block(output);
        } else {
            try self.start_dynamic_block(output);
        }

        return compress_lz_codes(self, output, lz.*.codes[0..lz.*.code_position]);
    }

    fn start_static_block(self: *Self, output: *OutputBuffer) void {
        if (debug) warn("{} start_static_block\n", self);
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
        if (debug) warn("{} start_dynamic_block\n", self);
        var area = []u8 {0} ** ((MAX_HUFF_SYMBOLS_0 + MAX_HUFF_SYMBOLS_1) * 2);
        var code_sizes_to_pack = area[0..(MAX_HUFF_SYMBOLS_0 + MAX_HUFF_SYMBOLS_1)];
        var packed_code_sizes = area[(MAX_HUFF_SYMBOLS_0 + MAX_HUFF_SYMBOLS_1)..];

        self.litlen.count[256] = 1;

        self.litlen.optimize_table(MAX_HUFF_SYMBOLS_0, 15, false);
        self.dist.optimize_table(MAX_HUFF_SYMBOLS_1, 15, false);

        var count: u32 = 0;
        var i: u32 = 285;
        const num_lit_codes = 286 - while (i >= 257) : (i -= 1) {
            if (self.litlen.code_sizes[i] != 0) {
                // warn("self.litlen.code_sizes[{}]={}\n", i, self.litlen.code_sizes[i ]);
                break count;
            }
            count += 1;
        } else  count;

        count = 0;
        i = 30 - 1;
        const num_dist_codes = 30 - while (i >= 1) : (i -= 1) {
            if (self.dist.code_sizes[i] != 0) {
                break count;
            }
            count += 1;
        } else count;
        if (debug) warn("lit={}, dist={}\n", num_lit_codes, num_dist_codes);

        const total_code_sizes_to_pack = num_lit_codes + num_dist_codes;

        copy_from_slice(@typeOf(code_sizes_to_pack[0]),
                        code_sizes_to_pack[0..num_lit_codes],
                        @typeOf(self.litlen.code_sizes[0]),
                        self.litlen.code_sizes[0..num_lit_codes]);
        //for (self.litlen.code_sizes[0..num_lit_codes]) |lcs, xx|{
        //    warn("");
        //    code_sizes_to_pack[xx] = lcs;
        //}

        copy_from_slice(
            @typeOf(code_sizes_to_pack[0]),
            code_sizes_to_pack[num_lit_codes..total_code_sizes_to_pack],
            @typeOf(self.dist.code_sizes[0]),
            self.dist.code_sizes[0..num_dist_codes]);
        // for (self.dist.code_sizes[0..num_dist_codes]) |dcs, yy| {
        //     //warn("dist total {} {}\n", total_code_sizes_to_pack, num_lit_codes + yy);
        //     code_sizes_to_pack[num_lit_codes + yy] = dcs;
        // }

        var rle = RLE {
            .z_count = 0,
            .repeat_count = 0,
            .p_code_size = 0xFF,
        };
        var ary: [3]u8 = undefined;

        setmem(u16, self.huffcodes.count[0..], 0);

        var packed_code_sizes_cursor = Cursor([]u8){.pos= 0, .inner = packed_code_sizes[0..]};
        // for (code_sizes_to_pack[0..total_code_sizes_to_pack]) |*code_size, ii| {
        //     warn("code_sizes_to_pack[{}]={}\n", ii, code_size.*);
        // }
        for (code_sizes_to_pack[0..total_code_sizes_to_pack]) |*code_size, ii| {
            if (code_size.* == 0) {
                try rle.prev_code_size(&packed_code_sizes_cursor, self);
                rle.z_count += 1;
                if (rle.z_count == 138) {
                    try rle.zero_code_size(&packed_code_sizes_cursor, self);
                }
            } else {
                try rle.zero_code_size(&packed_code_sizes_cursor, self);
                if (code_size.* != rle.p_code_size) {
                    try rle.prev_code_size(&packed_code_sizes_cursor, self);
                    self.huffcodes.count[code_size.*] +%= 1;
                    packed_code_sizes_cursor.write_one(code_size.*);
                } else {
                    rle.repeat_count += 1;
                    if (rle.repeat_count == 6) {
                        try rle.prev_code_size(&packed_code_sizes_cursor, self);
                    }
                }
            }
            rle.p_code_size = code_size.*;
        }

        if (rle.repeat_count != 0) {
            try rle.prev_code_size(&packed_code_sizes_cursor, self);
        } else {
            try rle.zero_code_size(&packed_code_sizes_cursor, self);
        }
        if (debug) warn("{}\n", &rle);

        // WIP: Seems we are failing in @This() region, a problem with
        // code sizes it seems
        self.huffcodes.optimize_table(MAX_HUFF_SYMBOLS_2, 7, false);

        output.put_bits(2, 2);

        output.put_bits((num_lit_codes - 257), 5);
        output.put_bits((num_dist_codes - 1), 5);

        count = 0;
        i = @truncate(u32, HUFFMAN_LENGTH_ORDER.len);
        while (i > 0) : (i -= 1) {
            const swizzle = HUFFMAN_LENGTH_ORDER[i - 1];
            if (self.huffcodes.code_sizes[swizzle] != 0) {
                break;
            }
            count += 1;
        }
        var num_bit_lengths: u32 = 18 - count;

        num_bit_lengths = MAX(u32, 4, num_bit_lengths + 1);
        output.put_bits(num_bit_lengths - 4, 4);
        for (HUFFMAN_LENGTH_ORDER[0..num_bit_lengths]) |swizzle| {
            //warn("self.huffcodes.code_sizes[{}]={}\n", swizzle, self.huffcodes.code_sizes[swizzle]);
            output.put_bits(self.huffcodes.code_sizes[swizzle], 3);
        }

        var packed_code_size_index: usize = 0;
        const p_code_sizes = packed_code_sizes_cursor.inner[0..];
        // for (p_code_sizes[0..packed_code_sizes_cursor.position()]) |p, ii| {
        //     warn("packed_codes_sizes[{}]={}\n", ii, p);
        // }
        while (packed_code_size_index < packed_code_sizes_cursor.position()) {
            var code = p_code_sizes[packed_code_size_index];
            packed_code_size_index += 1;
            assert(code < MAX_HUFF_SYMBOLS_2);
            // warn("self.huffcodes.codes[{}] = {}, self.huffcodes.code_sizes[{}]) = {}\n",
            //      code, self.huffcodes.codes[code], code, self.huffcodes.code_sizes[code]);
            output.put_bits(self.huffcodes.codes[code], self.huffcodes.code_sizes[code]);
            if (code >= 16) {
                ary = []u8 {2, 3, 7};
                assert(code - 16 <= 2);
                //warn("code={}\n", code);
                output.put_bits(
                    p_code_sizes[packed_code_size_index], ary[code - 16]);
                packed_code_size_index += 1;
            }
        }
        if (debug) warn("packed_code_size_index={}\n", packed_code_size_index);
    }

    inline fn record_literal(h: *Huffman, lz: *LZ, lit: u8) void {
        //if (debug) warn("record_literal(*, {c}/{x})\n", lit, lit);
        lz.total_bytes += 1;
        lz.write_code(lit);

        (lz.get_flag()).* >>= 1;
        lz.consume_flag();

        h.litlen.count[lit] += 1;
    }

    fn record_match(h: *Huffman, lz: *LZ, pmatch_len: u32, pmatch_dist: u32) void {
        //if (debug) warn("record_match(len={}, dist={})\n", pmatch_len, pmatch_dist);
        var match_len = pmatch_len;
        var match_dist = pmatch_dist;
        assert(match_len >= MIN_MATCH_LEN);
        assert(match_dist >= 1);
        assert(match_dist <= LZ_DICT_SIZE);

        lz.total_bytes += match_len;
        match_dist -= 1;
        match_len -= MIN_MATCH_LEN;
        assert(match_len < 256);
        lz.write_code(@truncate(u8, match_len));
        lz.write_code(@truncate(u8, match_dist));
        lz.write_code(@truncate(u8, match_dist >> 8));

        (lz.get_flag()).* >>= 1;
        (lz.get_flag()).* |= 0x80;
        lz.consume_flag();

        var symbol = if (match_dist < 512) SMALL_DIST_SYM[match_dist] else LARGE_DIST_SYM[((match_dist >> 8) & 127)];
        h.dist.count[symbol] += 1;
        h.litlen.count[LEN_SYM[match_len]] += 1;
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
    const Self = @This();
    pub b: [OUT_BUF_SIZE]u8,

    fn default() Self {
        return LocalBuf {
            .b = []u8 {0} ** OUT_BUF_SIZE,
        };
    }
};

const MatchResult = struct {
    const Self = @This();
    distance: u32,
    length: u32,
    loc: u8,

    // fn format(
    //     self: *const Self,
    //     comptime fmt: []const u8,
    //     context: var,
    //     comptime Errors: type,
    //     output: fn (@typeOf(context), []const u8) Errors!void,
    // ) Errors!void {
    //     // We hereby take over all printing...
    //     return deriveDebug(context, "{}", Errors, output, self.*, 0);
    // }
};

const Dictionary = struct {
    const Self = @This();
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

    // fn format(
    //     self: *const Self,
    //     comptime fmt: []const u8,
    //     context: var,
    //     comptime Errors: type,
    //     output: fn (@typeOf(context), []const u8) Errors!void,
    // ) Errors!void {
    //     // We hereby take over all printing...
    //     return deriveDebug(context, "{}", Errors, output, self.*, 0);
    // }

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
        return mem.readIntSlice(T, self.b.dict[pos..pos+@sizeOf(T)], builtin.endian);
    }

    /// Try to find a match for the data at lookahead_pos in the dictionary that is
    /// longer than `match_len`.
    /// Returns a tuple containing (match_distance, match_length). Will be equal to the input
    /// values if no better matches were found.
    fn find_match(self: *Self, lookahead_pos: u32, max_dist: u32, amax_match_len: u32,
                  amatch_dist: u32,
                  amatch_len: u32,
    ) MatchResult {
        // Clamp the match len and max_match_len to be valid. (It should be when @This() is called, but
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
        // If it is larger or equal to the maximum length, @This() statement won't be reached.
        // As the size of self.dict is LZ_DICT_SIZE + MAX_MATCH_LEN - 1 + DICT_PADDING,
        // @This() will not go out of bounds.
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
                    // See the beginning of @This() function.
                    // probe_pos and match_length are still both bounded.
                    // The first two bytes, last byte and the next byte matched, so
                    // check the match further.
                    if (self.read_unaligned(u16, (probe_pos + match_len - 1)) == c01) {
                        break :found;
                    }
                }
            }

            if (dist == 0) {
                return MatchResult{.distance = match_dist, .length = match_len, .loc = 3};
            }
            // See the beginning of @This() function.
            // probe_pos is bounded by masking with LZ_DICT_SIZE_MASK.
            if (self.read_unaligned(u16, probe_pos) != s01) {
                continue;
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
                        // pos is bounded by masking.
                        c01 = self.read_unaligned(u16, (pos + match_len - 1));
                    }
                    continue :outer;
                }
            }

            return MatchResult{.distance = dist, .length = MIN(u32, max_match_len, MAX_MATCH_LEN),
                               .loc = 5};
        }
    }

};

test "outputbuffer and bitbuffer" {
    var buf = []u8 {0x22} ** 1024;
    var ob: OutputBuffer = undefined;
    var cursor: Cursor([]u8) = undefined;
    cursor.init(buf[0..]);
    ob.inner = cursor; // {.pos = 0, .inner = buf[0..]};
    warn("{}\n", &cursor);
    ob.local = false;
    ob.bit_buffer = 0;
    ob.bits_in = 0;

    warn("sizeof OutputBuffer={}\n", usize(@sizeOf(OutputBuffer)));
    warn("ob.len={}, ob.pos={}, ob.inner.len={}\n", ob.len(), ob.inner.position(), ob.inner.len());

    var bb = BitBuffer {.bit_buffer = 0, .bits_in = 0};
    bb.put_fast(123456, 63);
    warn("{}\n", &bb);

    var r = bb.flush(&ob);
    warn("{}\n", &bb);
    warn("ob.len={}, ob.pos={}\n", ob.len(), ob.inner.position());
}

const BitBuffer = struct {
    const Self = @This();
    // space for up to 8 bytes
    pub bit_buffer: u64,
    pub bits_in: u32,

    // fn format(
    //     self: *const Self,
    //     comptime fmt: []const u8,
    //     context: var,
    //     comptime Errors: type,
    //     output: fn (@typeOf(context), []const u8) Errors!void,
    // ) Errors!void {
    //     // We hereby take over all printing...
    //     return deriveDebug(context, "{}", Errors, output, self.*, 0);
    // }


    inline fn put_fast(self: *Self, bits: u64, len: u8) void {
        // what if we want to write a complete u64?
        //warn("BitBuffer put_fast({x016}, {})\n", bits, len);
        self.bit_buffer |= (bits << @truncate(u6, self.bits_in));
        self.bits_in += len;
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
        const shift = @truncate(u6, self.bits_in);
        self.bit_buffer >>= shift & ~@typeOf(shift)(7);
        // Update the number of bits
        self.bits_in &= 7;
        //warn("<- BitBuffer flush pos={} {x016} bits_in={}\n", pos, self.bit_buffer, self.bits_in);
    }
};


/// Status of RLE encoding of huffman code lengths.
pub const RLE = struct {
    const Self = @This();
    pub z_count: u32,
    pub repeat_count: u32,
    pub p_code_size: u8,

    // fn format(
    //     self: *const Self,
    //     comptime fmt: []const u8,
    //     context: var,
    //     comptime Errors: type,
    //     output: fn (@typeOf(context), []const u8) Errors!void,
    // ) Errors!void {
    //     // We hereby take over all printing...
    //     return deriveDebug(context, "{}", Errors, output, self.*, 0);
    // }


    fn prev_code_size(self: *Self, packed_code_sizes: *Cursor([]u8), h: *Huffman ) !void {
        var counts = &h.huffcodes.count;
        if (self.repeat_count > 0) {
            if (self.repeat_count < 3) {
                counts.*[self.p_code_size] +%= @truncate(@typeOf(counts.*[0]), self.repeat_count);
                const code = self.p_code_size;
                var ary = [3]u8 {code, code, code};
                //warn("repeat_count={}\n", self.repeat_count);
                try packed_code_sizes.*.write_all(ary[0..self.repeat_count]);
            } else {
                counts.*[16] +%=  1;
                var ary = [2]u8 {16, @truncate(u8, (self.repeat_count - 3))};
                try packed_code_sizes.*.write_all(ary[0..2]);
            }
            self.repeat_count = 0;
        }
    }

    fn zero_code_size(self: *Self, packed_code_sizes: *Cursor([]u8), h: *Huffman) !void {
        var counts = &h.huffcodes.count;
        if (self.z_count > 0) {
            if (self.z_count < 3) {
                counts.*[0] +%= @truncate(@typeOf(counts.*[0]), self.z_count);
                // packed_code_sizes.write_all(
                //     &[0, 0, 0][..self.z_count as usize],
                // )?;
                const ary = [3]u8 {0,0,0};
                try packed_code_sizes.write_all(ary[0..self.z_count]);
            } else if (self.z_count <= 10) {
                counts.*[17] +%= 1;
                // packed_code_sizes.write_all(
                //     &[17, (self.z_count - 3) as u8][..],
                // )?;
                const ary = [2]u8 {17, @truncate(u8, self.z_count - 3)};
                try packed_code_sizes.write_all(ary[0..]);
            } else {
                counts.*[18] +%= 1;
                // packed_code_sizes.write_all(
                //     &[18, (self.z_count - 11) as u8][..],
                // )?;
                const ary = [2]u8 {18, @truncate(u8, self.z_count - 11)};
                try packed_code_sizes.write_all(ary[0..]);
            }
            self.z_count = 0;
        }
    }
};

const Params = struct {
    const Self = @This();
    pub gzip: bool,
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
    pub saved_bits_in: u32,

    pub local_buf: LocalBuf,

    fn format(
        self: *const Self,
        comptime fmt: []const u8,
        context: var,
        comptime Errors: type,
        output: fn (@typeOf(context), []const u8) Errors!void,
    ) Errors!void {
        // We hereby take over all printing...
        return deriveDebug(context, "{}", Errors, output, self.*, 0);
    }

    fn init(flags: u32, gzip: bool) Self {
        const initcsum: u32 = if (gzip) u32(0) else MZ_ADLER32_INIT;
        return Params {
            .gzip = gzip,
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
            .adler32 = initcsum,
            .src_pos = 0,
            .out_buf_ofs = 0,
            .prev_return_status = TDEFLStatus.Okay,
            .saved_bit_buffer = 0,
            .saved_bits_in= 0,
            .local_buf = LocalBuf.default()
        };
    }
};

test "mzdeflate.Params" {
    const p = Params.init(0, false);
    warn("{}\n", p);
}

const LZ = struct {
    const Self = @This();
    pub code_position: usize,
    pub flag_position: usize,
    pub total_bytes: u32,
    pub num_flags_left: u32,
    pub codes: [LZ_CODE_BUF_SIZE]u8,

    fn format(
        self: *const Self,
        comptime fmt: []const u8,
        context: var,
        comptime Errors: type,
        output: fn (@typeOf(context), []const u8) Errors!void,
    ) Errors!void {
        // We hereby take over all printing...
        return deriveDebug(context, "{}", Errors, output, self.*, 0);
    }
    
    fn init() Self {
        var lz = Self {
            .code_position = 1,
            .flag_position = 0,
            .total_bytes = 0,
            .num_flags_left = 8,
            .codes = []u8 {0} ** LZ_CODE_BUF_SIZE,
        };
        return lz;
    }

    fn write_code(self: *Self, val: u8) void {
        self.codes[self.code_position] = val;
        self.code_position += 1;
    }

    fn init_flag(self: *Self) void {
        if (self.num_flags_left == 8) {
            (self.get_flag()).* = 0;
            self.code_position -= 1;
        } else {
            (self.get_flag()).* >>= @truncate(u3, self.num_flags_left);
        }
    }

    fn get_flag(self: *Self) *u8 {
        return &self.codes[self.flag_position];
    }

    fn plant_flag(self: *Self) void {
        self.flag_position = self.code_position;
        self.code_position += 1;
    }

    fn consume_flag(self: *Self) void {
        self.num_flags_left -= 1;
        if (self.num_flags_left == 0) {
            self.num_flags_left = 8;
            self.plant_flag();
        }
    }
};


test "LZ" {
    const lz = LZ.init();
}

const CompressionResult = struct {
    const Self = @This();
    status: TDEFLStatus,
    inpos: usize,
    outpos: usize,

    fn new(status: TDEFLStatus, inpos: usize, outpos: usize) Self {
        return CompressionResult {.status = status, .inpos= inpos, .outpos = outpos};
    }

    fn format(
        self: *const Self,
        comptime fmt: []const u8,
        context: var,
        comptime Errors: type,
        output: fn (@typeOf(context), []const u8) Errors!void,
    ) Errors!void {
        // We hereby take over all printing...
        return deriveDebug(context, "{}", Errors, output, self.*, 0);
    }
};

/// Main compression struct.
pub const Compressor = struct {
    const Self = @This();
    lz: LZ,
    params: Params,
    huff: Huffman,
    dict: Dictionary,

    fn init(flags: u32, gzip: bool) Self {
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

    fn initialize(self: *Self, flags: u32, gzip: bool) void {
        self.lz = LZ.init();
        self.params = Params.init(flags, gzip);
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
        var callback = Callback.new_callback_buf(in_buf, out_buf);
        return self.compress_inner(&callback, flush);
    }

    fn compress_fast(d: *Compressor, callback: *Callback) bool {
        if (debug) warn("compress_fast\n");
        var src_pos = d.params.src_pos;
        var lookahead_size = d.dict.lookahead_size;
        var lookahead_pos = d.dict.lookahead_pos;

        var cur_pos = lookahead_pos & LZ_DICT_SIZE_MASK;
        const in_buf = if (callback.in_buf) |buf|  buf else return true;

        assert(d.lz.code_position < (LZ_CODE_BUF_SIZE - 2));

        while ((src_pos < in_buf.len) or ((d.params.flush != TDEFLFlush.None)
                                          and (lookahead_size > 0))) {
            var dst_pos: usize = ((lookahead_pos + lookahead_size) & LZ_DICT_SIZE_MASK);
            var num_bytes_to_process = MIN(usize, in_buf.len - src_pos,
                                           (COMP_FAST_LOOKAHEAD_SIZE - lookahead_size));
            lookahead_size += @truncate(@typeOf(lookahead_size), num_bytes_to_process);

            while (num_bytes_to_process != 0) {
                const n = MIN(usize, LZ_DICT_SIZE - dst_pos, num_bytes_to_process);
                //d.dict.b.dict[dst_pos..dst_pos + n].copy_from_slice(&in_buf[src_pos..src_pos + n]);
                // copy_from_slice(@typeOf(d.dict.b.dict[0]),
                //                 d.dict.b.dict[dst_pos..dst_pos + n],
                //                 @typeOf(in_buf[0]),
                //                 in_buf[src_pos..src_pos + n]);
                for (in_buf[src_pos..src_pos + n]) |b, ii| {
                    d.dict.b.dict[dst_pos + ii] = b;
                }
                //mem.copy(u8, d.dict.b.dict[dst_pos..dst_pos + n], in_buf[src_pos..src_pos + n]);

                if (dst_pos < (MAX_MATCH_LEN - 1)) {
                    const m = MIN(usize, n, MAX_MATCH_LEN - 1 - dst_pos);
                    // d.dict.b.dict[dst_pos + LZ_DICT_SIZE..dst_pos + LZ_DICT_SIZE + m]
                    //     .copy_from_slice(&in_buf[src_pos..src_pos + m]);
                    for (in_buf[src_pos..src_pos + m]) |b, ii| {
                        d.dict.b.dict[dst_pos + LZ_DICT_SIZE + ii] = b;
                    }
                    // mem.copy(u8,
                    //          d.dict.b.dict[dst_pos + LZ_DICT_SIZE..dst_pos + LZ_DICT_SIZE + m],
                    //          in_buf[src_pos..src_pos + m]);
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
                d.dict.b.hash[hash] = @truncate(u16, lookahead_pos);

                var cur_match_dist = @truncate(u16, lookahead_pos - probe_pos);
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
                                    break :find_match @truncate(u32, p) - cur_pos + (trailing >> 3);
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
                            const lit = @truncate(u8, first_trigram);
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

                            d.lz.write_code(@truncate(u8, cur_match_len - MIN_MATCH_LEN));
                            // # Unsafe
                            // code_position is checked to be smaller than the lz buffer size
                            // at the start of @This() function and on every loop iteration.
                            //  unsafe {
                            write_u16_le_uc(@truncate(u16, cur_match_dist),
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
                        d.lz.write_code(@truncate(u8, first_trigram));
                        (d.lz.get_flag()).* >>= 1;
                        d.huff.litlen.count[@truncate(u8, first_trigram)] += 1;
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
                        if (d.flush_block(callback, TDEFLFlush.None)) |nn| {
                            n = nn;
                            if (n != 0) {
                                d.params.src_pos = src_pos;
                                return n > 0;
                            }
                            assert(d.lz.code_position < (LZ_CODE_BUF_SIZE - 2));

                            lookahead_size = d.dict.lookahead_size;
                            lookahead_pos = d.dict.lookahead_pos;
                        } else |err| {
                            d.params.src_pos = src_pos;
                            d.params.prev_return_status = TDEFLStatus.PutBufFailed;
                            return false;
                        }
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
                    if (d.flush_block(callback, TDEFLFlush.None)) |nn| {
                        n = nn;
                        if (n != 0) {
                            d.params.src_pos = src_pos;
                            return n > 0;
                        }

                        lookahead_size = d.dict.lookahead_size;
                        lookahead_pos = d.dict.lookahead_pos;
                    } else |err| {
                        d.params.prev_return_status = TDEFLStatus.PutBufFailed;
                        d.params.src_pos = src_pos;
                        return false;
                    }
                }
            }
        }

        d.params.src_pos = src_pos;
        d.dict.lookahead_size = lookahead_size;
        d.dict.lookahead_pos = lookahead_pos;

        return true;
    }

    fn compress_inner(self: *Compressor, callback: *Callback,
                      pflush: TDEFLFlush) CompressionResult {
        if (debug) warn("compress_inner\n");
        var res: CompressionResult = undefined;
        var flush = pflush;
        self.params.out_buf_ofs = 0;
        self.params.src_pos = 0;

        var prev_ok = self.params.prev_return_status == TDEFLStatus.Okay;
        var flush_finish_once = (self.params.flush != TDEFLFlush.Finish) or (flush == TDEFLFlush.Finish);

        self.params.flush = flush;
        if (!prev_ok or !flush_finish_once) {
            self.params.prev_return_status = TDEFLStatus.BadParam;
            res = CompressionResult.new(self.params.prev_return_status, 0, 0);
            return res;
        }

        if ((self.params.flush_remaining != 0) or self.params.finished) {
            res = callback.flush_output_buffer(&self.params);
            self.params.prev_return_status = res.status;
            return res;
        }

        const one_probe = (self.params.flags & MAX_PROBES_MASK) == 1;
        const greedy = (self.params.flags & TDEFL_GREEDY_PARSING_FLAG) != 0;
        const filter_or_rle_or_raw = (self.params.flags & (TDEFL_FILTER_MATCHES
                                                           | TDEFL_FORCE_ALL_RAW_BLOCKS
                                                           | TDEFL_RLE_MATCHES)) != 0;

        const compress_success = if (one_probe and greedy and !filter_or_rle_or_raw)
            self.compress_fast(callback) else self.compress_normal(callback);

        if (!compress_success) {
            return CompressionResult.new(self.params.prev_return_status, self.params.src_pos, self.params.out_buf_ofs);
        }

        if (callback.in_buf) |in_buf| {
            if ((self.params.flags & (TDEFL_WRITE_ZLIB_HEADER | TDEFL_COMPUTE_ADLER32)) != 0) {
                if (self.params.gzip) {
                    self.params.adler32 = crc32.hash(in_buf[0..self.params.src_pos]);
                } else {
                    self.params.adler32 = adler32(self.params.adler32, in_buf[0..self.params.src_pos]);
                }
            }
        }

        const flush_none = (self.params.flush == TDEFLFlush.None);
        const in_left = if (callback.in_buf) |buf| (buf.len - self.params.src_pos) else 0;
        const remaining = (in_left != 0) or (self.params.flush_remaining != 0);
        if (!flush_none and (self.dict.lookahead_size == 0) and !remaining) {
            flush = self.params.flush;
            if (self.flush_block(callback, flush)) |n| {
                // given that we get a u32, @This() will never happen...investigate
                if (n < 0) {
                    res.status = self.params.prev_return_status;
                    res.inpos = self.params.src_pos;
                    res.outpos = self.params.out_buf_ofs;
                    return res;
                }
                self.params.finished = self.params.flush == TDEFLFlush.Finish;
                if (self.params.flush == TDEFLFlush.Full) {
                    if (debug) warn("full flush\n");
                    setmem(@typeOf(self.dict.b.hash[0]), self.dict.b.hash[0..], 0);
                    setmem(@typeOf(self.dict.b.next[0]), self.dict.b.next[0..], 0);
                    self.dict.size = 0;
                }
            } else |err| {
                self.params.prev_return_status = TDEFLStatus.PutBufFailed;
                res.status = self.params.prev_return_status;
                res.inpos = self.params.src_pos;
                res.outpos = self.params.out_buf_ofs;
                return res;
            }
        }

        res = callback.flush_output_buffer(&self.params);
        self.params.prev_return_status = res.status;

        return res;
    }

    fn flush_block(self: *Compressor, callback: *Callback, flush: TDEFLFlush) !u32 {
        if (debug) warn("flush_block\n");
        var saved_buffer: SavedOutputBuffer = undefined;
        var output = callback.out.new_output_buffer(
            &self.params.local_buf.b,
            self.params.out_buf_ofs,
        );
        output.bit_buffer = self.params.saved_bit_buffer;
        output.bits_in = self.params.saved_bits_in;

        const use_raw_block = ((self.params.flags & TDEFL_FORCE_ALL_RAW_BLOCKS) != 0) and
            ((self.dict.lookahead_pos - self.dict.code_buf_dict_pos) <= self.dict.size);

        assert(self.params.flush_remaining == 0);
        self.params.flush_ofs = 0;
        self.params.flush_remaining = 0;

        self.lz.init_flag();

        // If we are at the start of the stream, write the zlib header if requested.
        if (((self.params.flags & TDEFL_WRITE_ZLIB_HEADER) != 0) and (self.params.block_index == 0)) {
            if (!self.params.gzip) {
                output.put_bits(0x78, 8);
                output.put_bits(0x01, 8);
            }
        }

        // Output the block header.
        output.put_bits(@boolToInt(flush == TDEFLFlush.Finish), 1);

        saved_buffer = output.save();

        var comp_success = false;
        if (!use_raw_block) {
            const use_static = ((self.*.params.flags & TDEFL_FORCE_ALL_STATIC_BLOCKS) != 0) or
                (self.*.lz.total_bytes < 48);
            comp_success = try self.*.huff.compress_block(&output, &self.*.lz, use_static);
        }

        // If we failed to compress anything and the output would take
        // up more space than the output data, output a stored block
        // instead, which has at most 5 bytes of overhead.  We only
        // use some simple heuristics for now.  A stored block will
        // have an overhead of at least 4 bytes containing the block
        // length but usually more due to the length parameters having
        // to start at a byte boundary and thus requiring up to 5
        // bytes of padding.  As a static block will have an overhead
        // of at most 1 bit per byte (as literals are either 8 or 9
        // bytes), a raw block will never take up less space if the
        // number of input bytes are less than 32.
        const expanded = (self.lz.total_bytes > 32)
            and ((output.inner.position() - saved_buffer.pos + 1) >= self.lz.total_bytes)
            and ((self.dict.lookahead_pos - self.dict.code_buf_dict_pos) <= self.dict.size);

        if (use_raw_block or expanded) {
            output.load(saved_buffer);

            // Block header.
            output.put_bits(0, 2);

            // Block length has to start on a byte boundary, so pad.
            output.pad_to_bytes();

            // Block length and ones complement of block length.
            output.put_bits(self.lz.total_bytes & 0xFFFF, 16);
            output.put_bits(~self.lz.total_bytes & 0xFFFF, 16);

            // Write the actual bytes.
            var i: usize = 0;
            //for i in 0..self.lz.total_bytes {
            while (i < self.lz.total_bytes) : (i += 1) {
                const pos = (self.dict.code_buf_dict_pos + i) & LZ_DICT_SIZE_MASK;
                output.put_bits(self.dict.b.dict[pos], 8);
            }
        } else if (!comp_success) {
            output.load(saved_buffer);
            _ = self.huff.compress_block(&output, &self.lz, true);
        }

        if (flush != TDEFLFlush.None) {
            if (flush == TDEFLFlush.Finish) {
                output.pad_to_bytes();
                if (((self.params.flags & TDEFL_WRITE_ZLIB_HEADER) != 0) and (!self.params.gzip)) {
                    var adler = self.params.adler32;
                    var i: usize = 0;
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

        setmem(u16, self.huff.litlen.count[0..MAX_HUFF_SYMBOLS_0], 0);
        setmem(u16, self.huff.dist.count[0..MAX_HUFF_SYMBOLS_1], 0);

        self.lz.code_position = 1;
        self.lz.flag_position = 0;
        self.lz.num_flags_left = 8;
        self.dict.code_buf_dict_pos += self.lz.total_bytes;
        self.lz.total_bytes = 0;
        self.params.block_index += 1;

        saved_buffer = output.save();

        self.params.saved_bit_buffer = saved_buffer.bit_buffer;
        self.params.saved_bits_in = saved_buffer.bits_in;

        return callback.flush_output(&saved_buffer, &self.params);
    }

    fn compress_normal(self: *Compressor, callback: *Callback) bool {
        if (debug) warn("compress_normal\n");
        var src_pos = self.params.src_pos;
        var in_buf = if (callback.in_buf) |in_buf| in_buf else return true;

        var lookahead_size = self.dict.lookahead_size;
        var lookahead_pos = self.dict.lookahead_pos;
        var saved_lit = self.params.saved_lit;
        var saved_match_dist = self.params.saved_match_dist;
        var saved_match_len = self.params.saved_match_len;

        while ((src_pos < in_buf.len)
               or ((self.params.flush != TDEFLFlush.None) and (lookahead_size != 0))) {
            const src_buf_left = in_buf.len - src_pos;
            const num_bytes_to_process =
                MIN(u32, @truncate(u32, src_buf_left), MAX_MATCH_LEN - lookahead_size);

            if ((lookahead_size + self.dict.size) >= (MIN_MATCH_LEN - 1) and (num_bytes_to_process > 0)) {
                var dictb = &self.dict.b;

                var dst_pos = LZ_DICT_POS(lookahead_pos + lookahead_size);
                var ins_pos =  LZ_DICT_POS(lookahead_pos + lookahead_size - 2);
                var hash = (u32(dictb.dict[LZ_DICT_POS(ins_pos)]) << LZ_HASH_SHIFT)
                    ^ (dictb.dict[LZ_DICT_POS(ins_pos + 1)]);

                lookahead_size += num_bytes_to_process;
                for (in_buf[src_pos..src_pos + num_bytes_to_process]) |c| {
                    dictb.dict[dst_pos] = c;
                    if (dst_pos < (MAX_MATCH_LEN - 1)) {
                        dictb.dict[LZ_DICT_SIZE + dst_pos] = c;
                    }

                    hash = ((u32(hash) << LZ_HASH_SHIFT) ^ u32(c)) & u32(LZ_HASH_SIZE - 1);
                    dictb.next[LZ_DICT_POS(ins_pos)] = dictb.hash[hash];

                    dictb.hash[hash] = @truncate(u16, ins_pos & 0xffff);
                    dst_pos = LZ_DICT_POS(dst_pos + 1);
                    ins_pos += 1;
                }
                src_pos += num_bytes_to_process;
            } else {
                var dictb = &self.dict.b;
                for (in_buf[src_pos..src_pos + num_bytes_to_process]) |c| {
                    const dst_pos = LZ_DICT_POS(lookahead_pos + lookahead_size);
                    dictb.dict[dst_pos] = c;
                    //warn("c={c}, dst_pos={}\n", c, dst_pos);
                    if (dst_pos < (MAX_MATCH_LEN - 1)) {
                        dictb.dict[LZ_DICT_SIZE + dst_pos] = c;
                        //warn("c={c}, dst_pos={}\n", c, dst_pos + LZ_DICT_SIZE);
                    }

                    lookahead_size += 1;
                    if ((lookahead_size + self.dict.size) >= MIN_MATCH_LEN) {
                        const ins_pos = lookahead_pos + lookahead_size - 3;
                        //warn("ins_pos={}\n", ins_pos);
                        const hash =
                            ((u32(dictb.dict[(ins_pos & LZ_DICT_SIZE_MASK)]) <<
                              (LZ_HASH_SHIFT * 2)) ^
                             ((u32(dictb.dict[LZ_DICT_POS(ins_pos + 1)]) << LZ_HASH_SHIFT) ^
                              u32(c))) & u32(LZ_HASH_SIZE - 1);

                        dictb.next[LZ_DICT_POS(ins_pos)] = dictb.hash[hash];
                        dictb.hash[hash] = @truncate(u16, ins_pos);
                    }
                }

                src_pos += num_bytes_to_process;
            }

            self.dict.size = MIN(u32, LZ_DICT_SIZE - lookahead_size, self.dict.size);
            if ((self.params.flush == TDEFLFlush.None) and ((lookahead_size) < MAX_MATCH_LEN)) {
                break;
            }

            var len_to_move: u32 = 1;
            var cur_match_dist: u32 = 0;
            var cur_match_len = if (saved_match_len != 0) saved_match_len else (MIN_MATCH_LEN - 1);
            const cur_pos = (lookahead_pos & LZ_DICT_SIZE_MASK);
            if (self.params.flags & (TDEFL_RLE_MATCHES | TDEFL_FORCE_ALL_RAW_BLOCKS) != 0) {
                if ((self.dict.size != 0) and ((self.params.flags & TDEFL_FORCE_ALL_RAW_BLOCKS) == 0)) {
                    const c = self.dict.b.dict[((cur_pos -% 1) & LZ_DICT_SIZE_MASK)];
                    var i: usize = cur_pos;
                    var count: u32 = 0;
                    while (i < (cur_pos + lookahead_size - 1)) : (i += 1) {
                        if (self.dict.b.dict[i] != c) {
                            break;
                        }
                        count += 1;
                    }
                    //warn("count={}\n", count);
                    cur_match_len = count;
                    if (cur_match_len < MIN_MATCH_LEN) {
                        cur_match_len = 0;
                    } else {
                        cur_match_dist = 1;
                    }
                }
            } else {
                const dist_len = self.dict.find_match(
                    lookahead_pos,
                    self.dict.size,
                    lookahead_size,
                    cur_match_dist,
                    cur_match_len,
                );
                //dist_len.dump();
                cur_match_dist = dist_len.distance;
                cur_match_len = dist_len.length;
            }

            const far_and_small = (cur_match_len == MIN_MATCH_LEN)
                and (cur_match_dist >= (8 * 1024));
            const filter_small = (((self.params.flags & TDEFL_FILTER_MATCHES) != 0)
                                  and (cur_match_len <= 5));
            if (far_and_small or filter_small or (cur_pos == cur_match_dist)) {
                cur_match_dist = 0;
                cur_match_len = 0;
            }

            //warn("cur_match_len={}, saved_match_len={}, saved_match_dist={}\n",
            //     cur_match_len, saved_match_len, saved_match_dist);
            if (saved_match_len != 0) {
                if (cur_match_len > saved_match_len) {
                    self.huff.record_literal(&self.lz, saved_lit);
                    if (cur_match_len >= 128) {
                        self.huff.record_match(&self.lz, cur_match_len, cur_match_dist);
                        saved_match_len = 0;
                        len_to_move = cur_match_len;
                    } else {
                        saved_lit = self.dict.b.dict[cur_pos];
                        saved_match_dist = cur_match_dist;
                        saved_match_len = cur_match_len;
                    }
                } else {
                    self.huff.record_match(&self.lz, saved_match_len, saved_match_dist);
                    len_to_move = saved_match_len - 1;
                    saved_match_len = 0;
                }
            } else if (cur_match_dist == 0) {
                self.huff.record_literal(&self.lz,
                                         self.dict.b.dict[MIN(usize, cur_pos, self.dict.b.dict.len - 1)]);
            } else if ((self.params.greedy_parsing) or (self.params.flags & TDEFL_RLE_MATCHES != 0) or
                       (cur_match_len >= 128))
            {
                // If we are using lazy matching, check for matches at the next byte if the current
                // match was shorter than 128 bytes.
                self.huff.record_match(&self.lz, cur_match_len, cur_match_dist);
                len_to_move = cur_match_len;
            } else {
                saved_lit = self.dict.b.dict[MIN(usize, cur_pos, self.dict.b.dict.len - 1)];
                saved_match_dist = cur_match_dist;
                saved_match_len = cur_match_len;
            }

            lookahead_pos += len_to_move;
            assert(lookahead_size >= len_to_move);
            lookahead_size -= len_to_move;
            self.dict.size = MIN(u32, self.dict.size + len_to_move, LZ_DICT_SIZE);

            const lz_buf_tight = self.lz.code_position > LZ_CODE_BUF_SIZE - 8;
            const raw = self.params.flags & TDEFL_FORCE_ALL_RAW_BLOCKS != 0;
            const fat = ((self.lz.code_position * 115) >> 7) >= self.lz.total_bytes;
            const fat_or_raw = (self.lz.total_bytes > 31 * 1024) and (fat or raw);

            if (lz_buf_tight or fat_or_raw) {
                self.params.src_pos = src_pos;
                // These values are used in flush_block, so we need to write them back here.
                self.dict.lookahead_size = lookahead_size;
                self.dict.lookahead_pos = lookahead_pos;

                const n = self.flush_block(callback, TDEFLFlush.None) catch 0;
                //.unwrap_or(
                //    TDEFLStatus.PutBufFailed as
                //        i32,
                if (n != 0) {
                    self.params.saved_lit = saved_lit;
                    self.params.saved_match_dist = saved_match_dist;
                    self.params.saved_match_len = saved_match_len;
                    return (n > 0);
                }
            }
        }

        self.params.src_pos = src_pos;
        self.dict.lookahead_size = lookahead_size;
        self.dict.lookahead_pos = lookahead_pos;
        self.params.saved_lit = saved_lit;
        self.params.saved_match_dist = saved_match_dist;
        self.params.saved_match_len = saved_match_len;

        return true;
    }
};


/// Compression callback function type.
pub const PutBufFuncPtrNotNull = fn([]const u8, usize, []u8) bool;
/// `Option` alias for compression callback function type.
pub const PutBufFuncPtr = ?PutBufFuncPtrNotNull;

pub const CallbackFunc = struct {
    pub put_buf_func: PutBufFuncPtr,
    pub put_buf_user: []u8,
};

const CallbackBuf = struct {
    const Self = @This();
    out_buf: []u8,

    fn flush_output(self: *const Self, saved_output: *SavedOutputBuffer, params: *Params) u32 {
        if (saved_output.*.local) {
            const n = MIN(usize, saved_output.*.pos, self.out_buf.len - params.out_buf_ofs);
            //(&mut self.out_buf[params.out_buf_ofs..params.out_buf_ofs + n])
            //     .copy_from_slice(&params.local_buf.b[..n]);
            // copy_from_slice(@typeOf(self.out_buf[0]),
            //                 self.out_buf[params.out_buf_ofs..params.out_buf_ofs + n],
            //                 @typeOf(params.local_buf.b[0]),
            //                 params.local_buf.b[0..n]);
            for (params.local_buf.b[0..n]) |*b, ii| {
               self.out_buf[params.out_buf_ofs + ii] = b.*;
            }
            // mem.copy(@typeOf(self.out_buf[0]),
            //          self.out_buf[params.out_buf_ofs..(params.out_buf_ofs + n)],
            //          params.local_buf.b[0..n]);

            assert(n <= maxValue(u32));
            const nn = @truncate(u32, n);
            params.out_buf_ofs += nn;
            if (saved_output.*.pos != nn) {
                params.flush_ofs = nn;
                params.flush_remaining = @truncate(u32, saved_output.*.pos - n);
            }
        } else {
            params.out_buf_ofs += saved_output.*.pos;
        }

        return params.flush_remaining;
    }
};

const CallbackOut = union(enum) {
    const Self = @This();
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
    const Self = @This();
    in_buf: ?[]u8,
    in_buf_size: ?usize,
    out_buf_size: ?usize,
    out: CallbackOut,

    fn format(
        self: *const Self,
        comptime fmt: []const u8,
        context: var,
        comptime Errors: type,
        output: fn (@typeOf(context), []const u8) Errors!void,
    ) Errors!void {
        // We hereby take over all printing...
        return deriveDebug(context, "{}", Errors, output, self.*, 0);
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

    fn flush_output(self: *Self, saved_output: *SavedOutputBuffer, params: *Params) !u32 {
        //warn("{}: flush_output()\n", self);
        if (saved_output.*.pos == 0) {
            return params.flush_remaining;
        }

        self.update_size(params.src_pos, null);
        switch (self.out) {
            CallbackOut.Func => |*cf| { return error.NotImplemented; },
            CallbackOut.Buf => |*cb| { return cb.flush_output(saved_output, params); },
            else => { return error.Bug; },
        }
    }

    fn flush_output_buffer(self: *Callback, p: *Params) CompressionResult {
        //if (debug) warn("{} flush_output_buffer remaining={}\n", self, p.flush_remaining);
        var res = CompressionResult.new(TDEFLStatus.Okay, p.src_pos, 0);
        switch (self.out) {
            CallbackOut.Buf => |ob| {
                const n = MIN(usize, ob.out_buf.len - p.out_buf_ofs, p.flush_remaining);
                if (n > 0) {
                    for (p.local_buf.b[p.flush_ofs..p.flush_ofs + n]) |*b, ii|{
                        ob.out_buf[p.out_buf_ofs + ii] = b.*;
                    }
                }
                const nn = @truncate(u32, n);
                p.flush_ofs += nn;
                p.flush_remaining -= nn;
                p.out_buf_ofs += nn;
                res.outpos = p.out_buf_ofs;
            },
            else => {},
        }

        if (p.finished and (p.flush_remaining == 0)) {
            res.status = TDEFLStatus.Done;
        }

        return res;
    }
};

fn compress_lz_codes(huff: *Huffman, output: *OutputBuffer, lz_code_buf: []u8) !bool {
    if (debug) warn("compress_lz_codes len={}\n", lz_code_buf.len);
    var flags: u32 = 1;
    var bb = BitBuffer {
        .bit_buffer = u64(output.bit_buffer),
        .bits_in = output.bits_in,
    };

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

            i += 3;

            assert(huff.litlen.code_sizes[LEN_SYM[match_len]] != 0);
            const lensym = LEN_SYM[match_len];
            const lenextra = LEN_EXTRA[match_len];
            bb.put_fast(u64(huff.litlen.codes[lensym]), huff.litlen.code_sizes[lensym]);
            bb.put_fast(u64(match_len) & u64(BITMASKS[lenextra]), lenextra);

            if (match_dist < 512) {
                sym = SMALL_DIST_SYM[match_dist];
                num_extra_bits = SMALL_DIST_EXTRA[match_dist];
            } else {
                sym = LARGE_DIST_SYM[(match_dist >> 8)];
                num_extra_bits = LARGE_DIST_EXTRA[(match_dist >> 8)];
            }

            assert(huff.dist.code_sizes[sym] != 0);
            bb.put_fast(u64(huff.dist.codes[sym]), huff.dist.code_sizes[sym]);
            bb.put_fast(
                u64(match_dist) & u64(BITMASKS[num_extra_bits]),
                @truncate(u6, num_extra_bits));
        } else {
            // The lz code was a literal
            var ii: usize = 0;
            while (ii < 3) : (ii += 1) {
                flags >>= 1;
                const lit = lz_code_buf[i];
                i += 1;

                assert(huff.litlen.code_sizes[lit] != 0);
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
        const n = MIN(@typeOf(bb.bits_in), bb.bits_in, 16);
        output.put_bits(@truncate(u32, bb.bit_buffer) & BITMASKS[n], n);
        bb.bit_buffer >>= @truncate(u6, n);
        bb.bits_in -= n;
    }

    // Output the end of block symbol.
    output.put_bits(huff.litlen.codes[256], huff.litlen.code_sizes[256]);

    return true;
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
    warn("cursor={}\n", &cursor);

    var c1 = Cursor([]u8) { .pos = 0, .inner = buf[0..], };
    warn("c1={}\n", &c1);
}

test "Compress.static" {
    var c: Compressor = undefined;
    c.initialize(create_comp_flags_from_zip_params(9, 15, 0), false);
    var input = "Deflate late\n";
    warn("Compressing '{}' {x08}, {}\n", input, adler32(1, input[0..]), input.len);
    var output = []u8 {0} ** 256;
    var r = c.compress(input[0..], output[0..], TDEFLFlush.Finish);
    warn("r={}\n", &r);
    if (r.status == TDEFLStatus.Done or r.status == TDEFLStatus.Okay) {
        // for pasting into Python zlib.decompress(<paste>)
        warn("\"");
        for (output[0..r.outpos]) |b, i| {
            warn("\\x{x02}", b);
        }
        warn("\"\n");
        if (true) {
            warn("decompressing should give '{}'\n", input);
            // const puff = @import("puff.zig").puff;
            // var out = []u8 {0} ** 32;
            // var outlen: usize = out.len;
            // var inlen: usize = r.outpos - 6;
            // // puff does not read the zlib header so we skip the first 2-two bytes
            // // which seems to work.
            // const p = try puff(out[0..], &outlen, output[2..(r.outpos - 4)], &inlen);
            // warn("p={}, outlen={}\n", p, outlen);
            // assert(input.len == outlen);
            // assert(mem.eql(u8, out[0..outlen], input));
        }
    }
}

test "Compress.fast.short" {
    var c: Compressor = undefined;
    c.initialize(create_comp_flags_from_zip_params(1, 15, 0), false);
    var input = "Deflate late\n";
    warn("Compressing '{}' {x08}, {}\n", input, adler32(1, input[0..]), input.len);
    var output = []u8 {0} ** 256;
    var r = c.compress(input[0..], output[0..], TDEFLFlush.Finish);
    //warn("r={}\n", &r);
    if (r.status == TDEFLStatus.Done or r.status == TDEFLStatus.Okay) {
        // for pasting into  Python zlib.decompress(<paste>), could puff it...
        warn("\"");
        for (output[0..r.outpos]) |b, i| {
            warn("\\x{x02}", b);
        }
        warn("\"\n");
        if (true) {
            warn("decompressing should give '{}'\n", input);
            // const puff = @import("puff.zig").puff;
            // var out = []u8 {0} ** 32;
            // var outlen: usize = out.len;
            // var inlen: usize = r.outpos - 6;
            // // puff does not read the zlib header so we skip the first 2-two bytes
            // // which seems to work.
            // const p = try puff(out[0..], &outlen, output[2..(r.outpos - 4)], &inlen);
            // warn("p={}, outlen={}\n", p, outlen);
            // assert(input.len == outlen);
            // assert(mem.eql(u8, out[0..outlen], input));
        }
    }
}

test "Compress.fast.long" {
    var c: Compressor = undefined;
    c.initialize(create_comp_flags_from_zip_params(1, 15, 0), false);
    var input = "Deflate late|Deflate late|Deflate late|Deflate late|Deflate late|Deflate late|\n";
    warn("Compressing '{}' {x08}, {}\n", input, adler32(1, input[0..]), input.len);
    var output = []u8 {0} ** 256;
    var r = c.compress(input[0..], output[0..], TDEFLFlush.Finish);
    warn("r={}\n", &r);
    if (r.status == TDEFLStatus.Done or r.status == TDEFLStatus.Okay) {
        // for pasting into Python zlib.decompress(<paste>), could puff it...
        warn("\"");
        for (output[0..r.outpos]) |b, i| {
            warn("\\x{x02}", b);
        }
        warn("\"\n");
        if (false) {
            // const puff = @import("puff.zig").puff;
            // var out = []u8 {0} ** 128;
            // var outlen: usize = out.len;
            // var inlen: usize = r.outpos - 6;
            // // puff does not read the zlib header so we skip the first 2-two bytes
            // // which seems to work.
            // const p = try puff(out[0..], &outlen, output[2..(r.outpos - 4)], &inlen);
            // warn("p={}, outlen={}\n", p, outlen);
            // assert(input.len == outlen);
            // assert(mem.eql(u8, out[0..outlen], input));
        }
    }
}

test "Compress.dynamic" {
    var c: Compressor = undefined;
    c.initialize(create_comp_flags_from_zip_params(9, 15, 0), false);
    var input = "Deflate late|Deflate late|Deflate late|Deflate late|Deflate late|Deflate late\n";
    if (debug) warn("Compressing '{}' {x08}, {}\n", input, adler32(1, input[0..]), input.len);
    var output = []u8 {0} ** 256;
    var r = c.compress(input[0..], output[0..], TDEFLFlush.Finish);
    warn("r={}\n", &r);
    /// for pasting into Python zlib.decompress(<paste>)
    warn("\"");
    for (output[0..r.outpos]) |b, i| {
        warn("\\x{x02}", b);
    }
    warn("\"\n");
        if (true) {
            // wow, working roundtrip...
            const mzinflate =  @import("mzinflate.zig");
            const Decompressor = mzinflate.Decompressor;
            const decompress = mzinflate.decompress;
            const TINFL_FLAG_PARSE_ZLIB_HEADER = mzinflate.TINFL_FLAG_PARSE_ZLIB_HEADER;
            const TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF = mzinflate.TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF;
            var d = Decompressor.new();
            var out = []u8 {0} ** (8 * 1024);
            var cur = Cursor([]u8){.pos= 0, .inner = out[0..]};
            var res = decompress(&d, output[0..r.outpos], &cur, TINFL_FLAG_PARSE_ZLIB_HEADER | TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF);
            warn("res={}\n", &res);
            assert(mem.eql(u8, out[0..res.outpos], input));
        }

}

test "Compress.File.Fast" {
    const os = std.os;
    const io = std.io;
    var raw_bytes: [16 * 1024]u8 = undefined;
    var allocator = &std.heap.FixedBufferAllocator.init(raw_bytes[0..]).allocator;

    const file_name = "adler32.zig";
    var file = try os.File.openRead(file_name);
    defer file.close();

    const file_size = try file.getEndPos();

    warn("File has {} bytes\n", file_size);
    var file_in_stream = file.inStream(); ///io.stream.init(file);
    var buf_stream = io.BufferedInStream(os.File.ReadError).init(&file_in_stream.stream);
    const st = &buf_stream.stream;
    const contents = try st.readAllAlloc(allocator, file_size + 4);
    warn("contents has {} bytes, adler32={x08}\n", contents.len, adler32(1, contents[0..]));
    defer allocator.free(contents);

    var c: Compressor = undefined;
    c.initialize(create_comp_flags_from_zip_params(1, 15, 0), false);

    var output = []u8 {0} ** (8 * 1024);
    var r = c.compress(contents[0..], output[0..], TDEFLFlush.Finish);
    warn("r={}\n", &r);
    if (r.status == TDEFLStatus.Done or r.status == TDEFLStatus.Okay) {
        warn("8) Guesstimated compression: {.02}%\n",
             (100.0 * (@intToFloat(f32, r.outpos)/@intToFloat(f32, file_size))));
        for (output[0..r.outpos]) |b, i| {
            warn("\\x{x02}", b);
        }
        warn("\n");
        if (true) {
            // wow, working roundtrip...
            const mzinflate =  @import("mzinflate.zig");
            const Decompressor = mzinflate.Decompressor;
            const decompress = mzinflate.decompress;
            const TINFL_FLAG_PARSE_ZLIB_HEADER = mzinflate.TINFL_FLAG_PARSE_ZLIB_HEADER;
            const TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF = mzinflate.TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF;
            var d = Decompressor.new();
            var out = []u8 {0} ** (8 * 1024);
            var cur = Cursor([]u8){.pos= 0, .inner = out[0..]};
            var res = decompress(&d, output[0..r.outpos], &cur, TINFL_FLAG_PARSE_ZLIB_HEADER | TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF);
            warn("res={}\n", &res);
            assert(mem.eql(u8, out[0..res.outpos], contents));
        }

    } else {
        warn("compression failed\n");
    }
}

test "Compress.File.Dynamic" {
    const os = std.os;
    const io = std.io;
    var raw_bytes: [16 * 1024]u8 = undefined;
    var allocator = &std.heap.FixedBufferAllocator.init(raw_bytes[0..]).allocator;
    const file_name = "adler32.zig";
    var file = try os.File.openRead(file_name);
    defer file.close();

    const file_size = try file.getEndPos();

    warn("File has {} bytes\n", file_size);
    var file_in_stream = file.inStream();
    var buf_stream = io.BufferedInStream(os.File.ReadError).init(&file_in_stream.stream);
    const st = &buf_stream.stream;
    const contents = try st.readAllAlloc(allocator, file_size + 4);
    warn("contents has {} bytes, adler32={x08}\n", contents.len, adler32(1, contents[0..]));
    defer allocator.free(contents);

    var c: Compressor = undefined;
    c.initialize(create_comp_flags_from_zip_params(9, 15, 0), false);

    var output = []u8 {0} ** (6 * 1024);
    var r = c.compress(contents[0..], output[0..], TDEFLFlush.Finish);
    warn("r={}\n", &r);
    if (r.status == TDEFLStatus.Done or r.status == TDEFLStatus.Okay) {
        warn("8) Guesstimated compression: {.02}%\n",
             (100.0 * (@intToFloat(f32, r.outpos)/@intToFloat(f32, file_size))));
        for (output[0..r.outpos]) |b, i| {
            warn("\\x{x02}", b);
        }
        warn("\n");
        if (true) {
            // wow, working roundtrip...
            const mzinflate =  @import("mzinflate.zig");
            const Decompressor = mzinflate.Decompressor;
            const decompress = mzinflate.decompress;
            const TINFL_FLAG_PARSE_ZLIB_HEADER = mzinflate.TINFL_FLAG_PARSE_ZLIB_HEADER;
            const TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF = mzinflate.TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF;
            var d = Decompressor.new();
            var out = []u8 {0} ** (8 * 1024);
            var cur = Cursor([]u8){.pos= 0, .inner = out[0..]};
            var res = decompress(&d, output[0..r.outpos], &cur, TINFL_FLAG_PARSE_ZLIB_HEADER | TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF);
            warn("res={}\n", &res);
            assert(mem.eql(u8, out[0..res.outpos], contents));
        }

    }
}


fn hexdump(buf: []const u8, newline: bool) void {
    for (buf) |b| {
        warn("{x02}", b);
    }
    if (newline) {
        warn("\n");
    }
}

pub fn main() !void {
    // fail unless Debug or ReleaseSmall. ReleaseFast and ReleaseSafe fails...
    // comptime assert(builtin.mode == builtin.Mode.Debug
    //                 or builtin.mode == builtin.Mode.ReleaseSmall);
    const os = std.os;
    const io = std.io;

    var raw_bytes: [8 * 1024]u8 = undefined;
    var allocator = &std.heap.FixedBufferAllocator.init(raw_bytes[0..]).allocator;
    const file_name = "lorem.txt";
    var file = try os.File.openRead(allocator, file_name);
    defer file.close();

    const file_size = try file.getEndPos();

    warn("File has {} bytes\n", file_size);
    var file_in_stream = io.stream.init(&file);
    var buf_stream = io.BufferedInStream(io.FileInStream.Error).init(&file_in_stream.stream);
    const st = &buf_stream.stream;
    const contents = try st.readAllAlloc(allocator, file_size + 16);
    warn("contents has {} bytes, adler32={x08}\n", contents.len, adler32(1, contents[0..]));
    defer allocator.free(contents);

    var c: Compressor = undefined;
    const gzip = true;
    c.initialize(create_comp_flags_from_zip_params(9, 15, 0), gzip);

    var output = []u8 {0} ** (4 * 1024);
    // compress in a number of blocks/chunks
    var r: CompressionResult = undefined;
    const blksize: usize = 8 * 1024;
    var remaining = file_size;
    var pos: usize = 0;
    var n: usize = 0;
    var cksum: u32 = 0;
    while (remaining > 0) {
        const nbytes = MIN(usize, remaining, blksize);
        remaining -= nbytes;
        r = c.compress(contents[pos..pos+nbytes], output[n..], if (remaining == 0) TDEFLFlush.Finish else TDEFLFlush.Sync);
        warn("r={}\n", &r);
        //r.dump();
        switch (r.status) {
            TDEFLStatus.BadParam, TDEFLStatus.PutBufFailed => break,
            else => {
                n += r.outpos;
                pos += r.inpos;
            },
        }
    }
    if (r.status == TDEFLStatus.Done or r.status == TDEFLStatus.Okay) {
        if (gzip) {
            const gz = @import("gzip.zig");
            cksum = c.params.adler32;
            var gziphdr = gz.GzipHeader.init();
            var crcbuf = []u8 {0} ** 4;

            gziphdr.set_flag(gz.FNAME | gz.FCOMMENT);
            {
                // just for fun
                const time = std.os.time;
                const seconds: u32 = @truncate(u32, time.milliTimestamp() / time.ms_per_s);
                gziphdr.set_time(seconds);
            }
            gziphdr.set_xfl(gz.XFL_MAX);
            gziphdr.set_os(gz.OS.Unix);
            {
                var ofile = try os.File.openWrite(allocator, "_test_.gz");
                defer ofile.close();

                var file_out_stream = io.FileOutStream.init(&ofile);
                var obuf_stream = io.BufferedOutStream(io.FileOutStream.Error).init(&file_out_stream.stream);
                const ost = &obuf_stream.stream;

                try ost.write(gziphdr.as_slice());
                if (gziphdr.flag_set(gz.FNAME)) {
                    try ost.write(file_name ++ "\x00");
                }
                if (gziphdr.flag_set(gz.FCOMMENT)) {
                    try ost.write("Generated by zig, see https://ziglang.org" ++ "\x00");
                }
                try ost.write(output[0..n]);
                // need some trailing stuff, crc, isize, reuse crcbuf
                crcbuf[0] = @truncate(u8, cksum);
                crcbuf[1] = @truncate(u8, cksum >> 8);
                crcbuf[2] = @truncate(u8, cksum >> 16);
                crcbuf[3] = @truncate(u8, cksum >> 24);
                try ost.write(crcbuf[0..]);
                crcbuf[0] = @truncate(u8, file_size);
                crcbuf[1] = @truncate(u8, file_size >> 8);
                crcbuf[2] = @truncate(u8, file_size >> 16);
                crcbuf[3] = @truncate(u8, file_size >> 24);
                try ost.write(crcbuf[0..]);

                // make sure to flush the file
                try obuf_stream.flush();
                // gzip -v -t _test_.gz should say '_test_.gz: OK'
                warn("{}\n", &gziphdr);
            }

        }
        //warn("\n====crc32={x08}\n", cksum);
        // write deflate blocks
        // write crc32 and isize (filesize % 2^32))
        warn("8) n={}, Guesstimated compression: {.02}%\n",
             n, (100.0 * (@intToFloat(f32, n)/@intToFloat(f32, file_size))));
        if (true) {
            // wow, working roundtrip...
            const mzinflate =  @import("mzinflate.zig");
            const Decompressor = mzinflate.Decompressor;
            const decompress = mzinflate.decompress;
            const TINFL_FLAG_PARSE_ZLIB_HEADER = mzinflate.TINFL_FLAG_PARSE_ZLIB_HEADER;
            const TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF = mzinflate.TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF;
            var d = Decompressor.new();
            var out = []u8 {0} ** (@sizeOf(@typeOf(raw_bytes))); // same size as raw_bytes
            var cur = Cursor([]u8){.pos= 0, .inner = out[0..]};
            var res = decompress(&d, output[0..n], &cur, TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF);
            warn("res={}\n", &res);
            assert(mem.eql(u8, out[0..n], contents));
        }
    }
}
