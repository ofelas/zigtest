// -*- mode:zig; indent-tabs-mode:nil;  -*-
const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;
const assert = std.debug.assert;
const builtin = @import("builtin");

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

//use std::io::{self, Cursor, Seek, SeekFrom, Write};

//use super::CompressionLevel;
//use super::deflate_flags::*;
//use super::super::*;
//use shared::{HUFFMAN_LENGTH_ORDER, MZ_ADLER32_INIT, update_adler32};
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
    None = 0,
    Sync = 2,
    Full = 3,
    Finish = 4,
};

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

// impl TDEFLFlush {
//     pub fn new(flush: c_int) -> Result<Self, MZError> {
//         match flush {
//             0 => Ok(TDEFLFlush::None),
//             2 => Ok(TDEFLFlush::Sync),
//             3 => Ok(TDEFLFlush::Full),
//             4 => Ok(TDEFLFlush::Finish),
//             _ => Err(MZError::Param),
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
const LZ_DICT_SIZE_MASK = 32767; //LZ_DICT_SIZE as u32 - 1;
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
    assert((@sizeOf(@typeOf(val)) + pos) <= slice.len);
    if (builtin.endian == builtin.Endian.Little) {
        slice[pos] = @truncate(u8, val & 0xff);
        slice[pos + 1] = @truncate(u8, val >> 8);
    } else {
        slice[pos] = @truncate(u8, val >> 8);
        slice[pos + 1] = @truncate(u8, val & 0xff);
    }
}

fn write_u16_le_uc(val: u16, slice: []u8, pos: usize) void {
    // ptr::write_unaligned(slice.as_mut_ptr().offset(pos as isize) as *mut u16, val);
    assert((@sizeOf(@typeOf(val)) + pos) <= slice.len);
    mem.writeInt(slice[pos..], val, builtin.Endian.Little);
}

fn read_u16_le(slice: []u8, pos: usize) u16 {
    assert(pos + 1 < slice.len);
    assert(pos < slice.len);
    return mem.readInt(slice[pos..], u16, builtin.Endian.Little);
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
        warn("table_len={}, code_size_limit={}, static_table={}\n",
             table_len, code_size_limit, static_table);
        var num_codes = []u32 {0} ** (MAX_SUPPORTED_HUFF_CODESIZE + 1);
        var next_code = []u32 {0} ** (MAX_SUPPORTED_HUFF_CODESIZE + 1);

        if (static_table) {
            for (self.code_sizes[0..table_len]) |code_size| {
                num_codes[code_size] += 1;
            }
        } else {
            // let mut symbols0 = [SymFreq {
            //     key: 0,
            //     sym_index: 0,
            // }; MAX_HUFF_SYMBOLS];
            // let mut symbols1 = [SymFreq {
            //     key: 0,
            //     sym_index: 0,
            // }; MAX_HUFF_SYMBOLS];

            // let mut num_used_symbols = 0;
            // for i in 0..table_len {
            //     if self.count[table_num][i] != 0 {
            //         symbols0[num_used_symbols] = SymFreq {
            //             key: self.count[table_num][i],
            //             sym_index: i as u16,
            //         };
            //         num_used_symbols += 1;
            //     }
            // }

            // let symbols = Self::radix_sort_symbols(
            //     &mut symbols0[..num_used_symbols],
            //     &mut symbols1[..num_used_symbols],
            // );
            // Self::calculate_minimum_redundancy(symbols);

            // for symbol in symbols.iter() {
            //     num_codes[symbol.key as usize] += 1;
            // }

            // Self::enforce_max_code_size(&mut num_codes, num_used_symbols, code_size_limit);

            // memset(&mut self.code_sizes[table_num][..], 0);
            // memset(&mut self.codes[table_num][..], 0);

            // let mut last = num_used_symbols;
            // for i in 1..code_size_limit + 1 {
            //     let first = last - num_codes[i] as usize;
            //     for symbol in &symbols[first..last] {
            //         self.code_sizes[table_num][symbol.sym_index as usize] = i as u8;
            //     }
            //     last = first;
            // }
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
            const code_size = self.code_sizes[i];
            warn("i={}, code_size={}\n", i, code_size);
            if (code_size == 0) {
                continue;
            }
            var code = next_code[code_size];
            next_code[code_size] += 1;
            var rev_code: u32 = 0;

            j = 0;
            while (j < code_size) : (j += 1) {
                rev_code = (rev_code << 1) | (code & 1);
                code >>= 1;
            }

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
    tables: [MAX_HUFF_TABLES]HuffmanEntry,

    fn start_static_block(self: *Self, output: *OutputBuffer) void {
        setmem(u6, self.tables[LITLEN_TABLE].code_sizes[0..144], 8);
        setmem(u6, self.tables[LITLEN_TABLE].code_sizes[144..256], 9);
        setmem(u6, self.tables[LITLEN_TABLE].code_sizes[256..280], 7);
        setmem(u6, self.tables[LITLEN_TABLE].code_sizes[280..288], 8);

        setmem(u6, self.tables[DIST_TABLE].code_sizes[0..32], 5);

        self.tables[LITLEN_TABLE].optimize_table(288, 15, true);
        self.tables[DIST_TABLE].optimize_table(32, 15, true);

        output.put_bits(0b01, 2);
    }

    fn start_dynamic_block(self: *Self, output: *OutputBuffer) !void {
        // There will always be one, and only one end of block code.
        self.tables[0].count[256] = 1;

        self.tables[0].optimize_table(MAX_HUFF_SYMBOLS_0, 15, false);
        self.tables[1].optimize_table(MAX_HUFF_SYMBOLS_1, 15, false);

        const num_lit_codes = 286; // -
        //     &self.code_sizes[0][257..286]
        //         .iter()
        //         .rev()
        //         .take_while(|&x| *x == 0)
        //         .count();

        const num_dist_codes = 30; // -
        //     &self.code_sizes[1][1..30]
        //         .iter()
        //         .rev()
        //         .take_while(|&x| *x == 0)
        //         .count();

        var code_sizes_to_pack = []u8 {0} ** (MAX_HUFF_SYMBOLS_0 + MAX_HUFF_SYMBOLS_1);
        var packed_code_sizes = []u8 {0} ** (MAX_HUFF_SYMBOLS_0 + MAX_HUFF_SYMBOLS_1);

        const total_code_sizes_to_pack = num_lit_codes + num_dist_codes;

        // code_sizes_to_pack[..num_lit_codes].copy_from_slice(&self.code_sizes[0][..num_lit_codes]);

        // code_sizes_to_pack[num_lit_codes..total_code_sizes_to_pack]
        //     .copy_from_slice(&self.code_sizes[1][..num_dist_codes]);

        var rle = RLE {
             .z_count = 0,
             .repeat_count = 0,
             .p_code_size = 0xFF,
        };

        setmem(u16, self.tables[HUFF_CODES_TABLE].count[0..MAX_HUFF_SYMBOLS_2], 0);

        var packed_code_sizes_cursor = Cursor([]u8){.pos= 0, .inner = packed_code_sizes[0..]};
        // for &code_size in &code_sizes_to_pack[..total_code_sizes_to_pack] {
        //     if code_size == 0 {
        //         rle.prev_code_size(&mut packed_code_sizes_cursor, self)?;
        //         rle.z_count += 1;
        //         if rle.z_count == 138 {
        //             rle.zero_code_size(&mut packed_code_sizes_cursor, self)?;
        //         }
        //     } else {
        //         rle.zero_code_size(&mut packed_code_sizes_cursor, self)?;
        //         if code_size != rle.prev_code_size {
        //             rle.prev_code_size(&mut packed_code_sizes_cursor, self)?;
        //             self.count[HUFF_CODES_TABLE][code_size as usize] =
        //                 self.count[HUFF_CODES_TABLE][code_size as usize].wrapping_add(1);
        //             packed_code_sizes_cursor.write_all(&[code_size][..])?;
        //         } else {
        //             rle.repeat_count += 1;
        //             if rle.repeat_count == 6 {
        //                 rle.prev_code_size(&mut packed_code_sizes_cursor, self)?;
        //             }
        //         }
        //     }
        //     rle.prev_code_size = code_size;
        // }

        if (rle.repeat_count != 0) {
            try rle.prev_code_size(&packed_code_sizes_cursor, self);
        } else {
            try rle.zero_code_size(&packed_code_sizes_cursor, self);
        }

        self.tables[2].optimize_table(MAX_HUFF_SYMBOLS_2, 7, false);

        output.put_bits(2, 2);

        output.put_bits((num_lit_codes - 257), 5);
        output.put_bits((num_dist_codes - 1), 5);

        // let mut num_bit_lengths = 18 -
        //     HUFFMAN_LENGTH_ORDER
        //         .iter()
        //         .rev()
        //         .take_while(|&swizzle| {
        //             self.code_sizes[HUFF_CODES_TABLE][*swizzle as usize] == 0
        //         })
        //         .count();

        // num_bit_lengths = cmp::max(4, num_bit_lengths + 1);
        // output.put_bits(num_bit_lengths as u32 - 4, 4);
        // for &swizzle in &HUFFMAN_LENGTH_ORDER[..num_bit_lengths] {
        //     output.put_bits(
        //         self.code_sizes[HUFF_CODES_TABLE][swizzle as usize] as u32,
        //         3,
        //     );
        // }

        // let mut packed_code_size_index = 0 as usize;
        // let packed_code_sizes = packed_code_sizes_cursor.get_ref();
        // while packed_code_size_index < packed_code_sizes_cursor.position() as usize {
        //     let code = packed_code_sizes[packed_code_size_index] as usize;
        //     packed_code_size_index += 1;
        //     assert!(code < MAX_HUFF_SYMBOLS_2);
        //     output.put_bits(
        //         self.codes[HUFF_CODES_TABLE][code] as u32,
        //         self.code_sizes[HUFF_CODES_TABLE][code] as u32,
        //     );
        //     if code >= 16 {
        //         output.put_bits(
        //             packed_code_sizes[packed_code_size_index] as u32,
        //             [2, 3, 7][code - 16],
        //         );
        //         packed_code_size_index += 1;
        //     }
        // }

        // Ok(())
    }

};

fn DefaultHuffman () Huffman {
    var huff = Huffman {
        .tables = []HuffmanEntry {
            HuffmanEntry {
                .count = []u16 {0} ** MAX_HUFF_SYMBOLS,
                .codes = []u16 {0} ** MAX_HUFF_SYMBOLS,
                .code_sizes = []u6 {0} ** MAX_HUFF_SYMBOLS,
            },
            HuffmanEntry {
                .count = []u16 {0} ** MAX_HUFF_SYMBOLS,
                .codes = []u16 {0} ** MAX_HUFF_SYMBOLS,
                .code_sizes = []u6 {0} ** MAX_HUFF_SYMBOLS,
            },
            HuffmanEntry {
                .count = []u16 {0} ** MAX_HUFF_SYMBOLS,
                .codes = []u16 {0} ** MAX_HUFF_SYMBOLS,
                .code_sizes = []u6 {0} ** MAX_HUFF_SYMBOLS,
            },
        },
    };

    return huff;
}

/// Size of the buffer of LZ77 encoded data.
pub const LZ_CODE_BUF_SIZE = 64 * 1024;
/// Size of the output buffer.
pub const OUT_BUF_SIZE = (LZ_CODE_BUF_SIZE * 13) / 10;

pub const HashBuffers = struct {
    pub dict: [LZ_DICT_SIZE + MAX_MATCH_LEN - 1 + 1]u8,
    pub next: [LZ_DICT_SIZE]u16,
    pub hash: [LZ_DICT_SIZE]u16,
};

fn DefaultHashBuffers() HashBuffers {
    return HashBuffers {
        .dict = []u8 {0} ** (LZ_DICT_SIZE + MAX_MATCH_LEN - 1 + 1),
        .next = []u16 {0} ** LZ_DICT_SIZE,
        .hash = []u16 {0} ** LZ_DICT_SIZE,
    };
}

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
    distance: u32,
    length: u32,
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

    fn new(flags: u32) Self {
        return Dictionary {
            .max_probes = []u32 {1 + ((flags & 0xFFF) + 2) / 3, 1 + (((flags & 0xFFF) >> 2) + 2) / 3},
            .b = DefaultHashBuffers(),
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
        return mem.readInt(self.b.dict[pos..pos+@sizeOf(T)], T, builtin.Endian.Little);
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

        const pos = (lookahead_pos & LZ_DICT_SIZE_MASK);
        var probe_pos = pos;
        // Number of probes into the hash chains.
        var num_probes_left = self.max_probes[@boolToInt(match_len >= 32)];

        // If we already have a match of the full length don't bother searching for another one.
        if (max_match_len <= match_len) {
            return MatchResult{.distance = match_dist, .length = match_len};
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
                num_probes_left -= 1;
                if (num_probes_left == 0) {
                    // We have done as many probes in the hash chain as the current compression
                    // settings allow, so return the best match we found, if any.
                    return MatchResult{.distance = match_dist, .length = match_len};
                }

                // for _ in 0..3 {
                //     let next_probe_pos = self.b.next[probe_pos as usize] as u32;

                //     dist = ((lookahead_pos - next_probe_pos) & 0xFFFF) as u32;
                //     if next_probe_pos == 0 || dist > max_dist {
                //         // We reached the end of the hash chain, or the next value is further away
                //         // than the maximum allowed distance, so return the best match we found, if
                //         // any.
                //         return (match_dist, match_len);
                //     }

                //     // Mask the position value to get the position in the hash chain of the next
                //     // position to match against.
                //     probe_pos = next_probe_pos & LZ_DICT_SIZE_MASK;
                //     // # Unsafe
                //     // See the beginning of this function.
                //     // probe_pos and match_length are still both bounded.
                //     unsafe {
                //         // The first two bytes, last byte and the next byte matched, so
                //         // check the match further.
                //         if self.read_unaligned::<u16>((probe_pos + match_len - 1) as isize) == c01 {
                //             break :found;
                //         }
                //     }
                // }
            }

            if (dist == 0) {
                return MatchResult{.distance = match_dist, .length = match_len};
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
            var i: usize = 0;
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
                        match_len = MIN(max_match_len, probe_len);
                        if (match_len == max_match_len) {
                            return MatchResult{.distance = match_dist, .length = match_len};
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

            return MatchResult{.distance = dist, .length = MIN(usize, max_match_len, MAX_MATCH_LEN)};
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
                    warn("Seeking from current {}\n", dist);
                },
                SeekFrom.End => |dist| {
                    warn("Seeking from current {}\n", dist);
                },
                SeekFrom.Current => |dist| {
                    warn("Seeking from current {}\n", dist);
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
            if ((self.inner.len - self.pos) < @sizeOf(@typeOf(value))) {
                return error.NoSpaceLeft;
            }
            mem.writeInt(self.inner[self.pos..], value, endian);
        }

        fn write_all(self: *Self, buf: []u8) void {
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
        try self.inner.writeInt(value, builtin.Endian.Little);
    }

    fn put_bits(self: *Self, bits: u32, length: u32) void {
        // assert!(bits <= ((1u32 << len) - 1u32));
        self.bit_buffer |= bits << self.bits_in;
        // self.bits_in += len;
        // while self.bits_in >= 8 {
        //     let pos = self.inner.position();
        //     self.inner.get_mut()[pos as usize] = self.bit_buffer as u8;
        //     self.inner.set_position(pos + 1);
        //     self.bit_buffer >>= 8;
        //     self.bits_in -= 8;
        // }
    }

    fn save(self: *Self) SavedOutputBuffer {
        return SavedOutputBuffer {
            .pos = self.inner.position(),
            .bit_buffer = self.bit_buffer,
            .bits_in = self.bits_in,
            .local = self.local,
        };
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
            self.put_bits(0, length);
        }
    }

};

test "outputbuffer and bitbuffer" {
    var buf = []u8 {0} ** 1024;
    var ob: OutputBuffer = undefined;
    ob.inner = Cursor([]u8) {.pos = 0, .inner = buf[0..]};
    ob.local = false;
    ob.bit_buffer = 0;
    ob.bits_in = 0;

    warn("sizeof OutputBuffer={}\n", usize(@sizeOf(OutputBuffer)));
    warn("ob.len={}, ob.pos={}\n", ob.len(), ob.inner.position());

    var bb = BitBuffer {.bit_buffer = 0, .bits_in = 0};
    bb.put_fast(123456, 63);
    bb.warn();

    var r = bb.flush(&ob);
    bb.warn();
    warn("ob.len={}, ob.pos={}\n", ob.len(), ob.inner.position());
}

const SavedOutputBuffer = struct {
    pub pos: u64,
    pub bit_buffer: u32,
    pub bits_in: u5,
    pub local: bool,
};

const BitBuffer = struct {
    const Self = this;
    pub bit_buffer: u64,
    pub bits_in: u6,

    fn warn(self: *Self) void {
        warn("bit_buffer={x016}, bits_in={}\n", self.bit_buffer, self.bits_in);
    }

    fn put_fast(self: *Self, bits: u64, len: u6) void {
        // what if we want to write a complete u64?
        self.bit_buffer |= bits << self.bits_in;
        self.bits_in += len;
    }

    fn flush(self: *Self, output: *OutputBuffer) !void {
        var pos = output.inner.position();
        //var inner = &mut ((*output.inner.get_mut())[pos]) as *mut u8 as *mut u64;
        // # Unsafe
        // TODO: check unsafety
        //unsafe {
        //    ptr::write_unaligned(inner, self.bit_buffer.to_le());
        //}
        try output.write_u64_le(self.bit_buffer);
        try output.inner.seek(SeekFrom {.Current = self.bits_in >> 3 });
        self.bit_buffer >>= self.bits_in & ~@typeOf(self.bits_in)(7);
        self.bits_in &= 7;
    }
};


/// Status of RLE encoding of huffman code lengths.
pub const RLE = struct {
    const Self = this;
    pub z_count: u16,
    pub repeat_count: u16,
    pub p_code_size: u8,

    fn prev_code_size(self: *Self, packed_code_sizes: *Cursor([]u8), h: *Huffman ) !void {
        var counts = &h.tables[HUFF_CODES_TABLE].count;
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
                // FAKE
                var ary = []u8 {code, code, code};
                packed_code_sizes.write_all(ary[0..self.repeat_count]);
                if (self.repeat_count > 3) { return error.Fake; }
            } else {
                counts[16] = counts[16] +% 1;
                var ary = []u8 {16, @truncate(u8, (self.repeat_count - 3) & 0xff)};
                packed_code_sizes.write_all(ary[0..]);
                // )?;
                
            }
            self.repeat_count = 0;
        }
    }

    fn zero_code_size(self: *Self, packed_code_sizes: *Cursor([]u8), h: *Huffman) !void {
        var counts = &h.tables[HUFF_CODES_TABLE].count;
        if (self.z_count != 0) {
            if (self.z_count < 3) {
                counts[0] +%= self.z_count;
                // packed_code_sizes.write_all(
                //     &[0, 0, 0][..self.z_count as usize],
                // )?;
                // FAKE
                if (self.repeat_count > 3) { return error.Fake; }
            } else if (self.z_count <= 10) {
                counts[17] +%= 1;
                // packed_code_sizes.write_all(
                //     &[17, (self.z_count - 3) as u8][..],
                // )?;
            } else {
                counts[18] +%= 1;
                // packed_code_sizes.write_all(
                //     &[18, (self.z_count - 11) as u8][..],
                // )?;
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

    fn new(flags: u32) Self {
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

const LZ = struct {
    const Self = this;
    pub codes: [LZ_CODE_BUF_SIZE]u8,
    pub code_position: usize,
    pub flag_position: usize,

    pub total_bytes: u32,
    pub num_flags_left: u32,

    fn new() Self {
        return LZ {
            .codes = []u8 {0} ** LZ_CODE_BUF_SIZE,
            .code_position = 1,
            .flag_position = 0,
            .total_bytes = 0,
            .num_flags_left = 8,
        };
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

/// Main compression struct.
pub const Compressor = struct {
    const Self = this;
    lz: LZ,
    params: Params,
    huff: Huffman,
    dict: Dictionary,

    fn new(flags: u32) Self {
        return Compressor {
            .lz = LZ.new(),
            .params = Params.new(flags),
            // LATER
            /// Put HuffmanOxide on the heap with default trick to avoid
            /// excessive stack copies.
            .huff = DefaultHuffman(),
            .dict = Dictionary.new(flags),
        };
    }
};


const ReturnTuple = struct {
    const Self = this;
    status: TDEFLStatus,
    inpos: usize,
    outpos: usize,

    fn new(status: TDEFLStatus, inpos: usize, outpos: usize) Self {
        return ReturnTuple {.status = status, .inpos= inpos, .outpos = outpos};
    }
};

const Callback = struct {
    const Self = this;
    in_buf: []u8,
    in_buf_size: usize,
    out_buf_size: usize,
    out: []u8,

    fn new_callback_buf(in_buf: []u8, out_buf: []u8) Self {
        return Callback {
            .in_buf = in_buf,
            .in_buf_size = in_buf.len,
            .out_buf_size = out_buf.len,
            .out = out_buf,
        };
    }

    fn new_output_buffer(self: *Self, local_buf: []u8, out_buf_ofs: usize) OutputBuffer {
        var is_local = false;
        var buf_len: usize = OUT_BUF_SIZE - 16;
        // let chosen_buffer = match *self {
        //     CallbackOut::Buf(ref mut cb)
        //         if cb.out_buf.len() - out_buf_ofs >= OUT_BUF_SIZE => {
        //         is_local = false;
        //         &mut cb.out_buf[out_buf_ofs..out_buf_ofs + buf_len]
        //     }
        //     _ => {
        //         is_local = true;
        //         &mut local_buf[..buf_len]
        //     }
        // };

        // let cursor = Cursor::new(chosen_buffer);
        return OutputBuffer {
            .inner = Cursor([]u8) {.pos = 0, .inner = local_buf},
            .local = is_local,
            .bit_buffer = 0,
            .bits_in = 0,
        };
    }

    fn flush_output(self: *Self, saved_output: SavedOutputBuffer, params: *Params) !u32 {
        if (saved_output.pos == 0) {
            return params.flush_remaining;
        }

        // self.update_size(Some(params.src_pos), None);
        // match self.out {
        //     CallbackOut::Func(ref mut cf) => cf.flush_output(saved_output, params),
        //     CallbackOut::Buf(ref mut cb) => cb.flush_output(saved_output, params),
        // }
        // FAKE
        if (saved_output.pos == 0) { return error.Fake; }
        return 0;
    }
};

fn compress_lz_codes(huff: *Huffman, output: *OutputBuffer, lz_code_buf: []u8) !bool {
    var flags: u32 = 1;
    var bb = BitBuffer {
        .bit_buffer = output.bit_buffer,
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
            var num_extra_bits: u6 = 0;

            var match_len = usize(lz_code_buf[i]);

            var match_dist = usize(read_u16_le(lz_code_buf, i + 1));

            i += 3;

            assert(huff.tables[0].code_sizes[LEN_SYM[match_len]] != 0);
            bb.put_fast(
                huff.tables[0].codes[LEN_SYM[match_len]],
                huff.tables[0].code_sizes[LEN_SYM[match_len]],
            );
            bb.put_fast(
                u64(match_len) & BITMASKS[LEN_EXTRA[match_len]],
                LEN_EXTRA[match_len],
            );

            if (match_dist < 512) {
                sym = SMALL_DIST_SYM[match_dist];
                num_extra_bits = SMALL_DIST_EXTRA[match_dist];
            } else {
                sym = LARGE_DIST_SYM[(match_dist >> 8)];
                num_extra_bits = LARGE_DIST_EXTRA[(match_dist >> 8)];
            }

            assert(huff.tables[1].code_sizes[sym] != 0);
            bb.put_fast(huff.tables[1].codes[sym], huff.tables[1].code_sizes[sym]);
            bb.put_fast(
                u64(match_dist) & BITMASKS[num_extra_bits],
                num_extra_bits,
            );
        } else {
            // The lz code was a literal
            //for _ in 0..3 {
            var iter: usize = 0;
            while (iter < 4) : (iter += 1) {
                flags >>= 1;
                const lit = lz_code_buf[i];
                i += 1;

                assert(huff.tables[0].code_sizes[lit] != 0);
                bb.put_fast(
                    huff.tables[0].codes[lit],
                    huff.tables[0].code_sizes[lit],
                );

                if (((flags & 1) == 1) or (i >= lz_code_buf.len)) {
                    break;
                }
            }
        }

        try bb.flush(output);
    }

    output.bits_in = 0;
    output.bit_buffer = 0;
    while (bb.bits_in != 0) {
        const n = MIN(u6, bb.bits_in, 16);
        output.put_bits(@truncate(u32, bb.bit_buffer & BITMASKS[n]), n);
        bb.bit_buffer >>= n;
        bb.bits_in -= n;
    }

    // Output the end of block symbol.
    output.put_bits(huff.tables[0].codes[256], huff.tables[0].code_sizes[256]);

    return true;
}


fn compress_block(huff: *Huffman, output: *OutputBuffer, lz: *LZ,
                  static_block: bool) !bool {
    if (static_block) {
        huff.start_static_block(output);
    } else {
        try huff.start_dynamic_block(output);
    }

    return compress_lz_codes(huff, output, lz.codes[0..lz.code_position]);
}

fn flush_block(d: *Compressor, callback: *Callback, flush: TDEFLFlush) !u32 {
    var saved_buffer: SavedOutputBuffer = undefined;
    {
        var output = callback.new_output_buffer(
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
            comp_success = try compress_block(&d.huff, &output, &d.lz, use_static);
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
            _ = compress_block(&d.huff, &output, &d.lz, true);
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

        setmem(u16, d.huff.tables[0].count[0..MAX_HUFF_SYMBOLS_0], 0);
        setmem(u16, d.huff.tables[1].count[0..MAX_HUFF_SYMBOLS_1], 0);

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
    lz.total_bytes += 1;
    lz.write_code(lit);

    (lz.get_flag()).* >>= 1;
    lz.consume_flag();

    h.tables[0].count[lit] += 1;
}

fn record_match(h: *Huffman, lz: *LZ, pmatch_len: u32, pmatch_dist: u32) void {
    var match_len = pmatch_len;
    var match_dist = pmatch_dist;
    assert(match_len >= MIN_MATCH_LEN);
    assert(match_dist >= 1);
    assert(match_dist <= LZ_DICT_SIZE);

    lz.total_bytes += match_len;
    match_dist -= 1;
    match_len -= MIN_MATCH_LEN;
    lz.write_code(@truncate(u8, match_len & 0xff));
    lz.write_code(@truncate(u8, match_dist & 0xff));
    lz.write_code(@truncate(u8, match_dist >> 8));

    (lz.get_flag()).* >>= 1;
    (lz.get_flag()).* |= 0x80;
    lz.consume_flag();

    var symbol = if (match_dist < 512) SMALL_DIST_SYM[match_dist]
    else LARGE_DIST_SYM[((match_dist >> 8) & 127)];
    h.tables[1].count[symbol] += 1;
    h.tables[0].count[LEN_SYM[match_len]] += 1;
}

fn compress_normal(d: *Compressor, callback: *Callback) bool {
    var src_pos = d.params.src_pos;
    var in_buf = callback.in_buf;

    var lookahead_size = d.dict.lookahead_size;
    var lookahead_pos = d.dict.lookahead_pos;
    var saved_lit = d.params.saved_lit;
    var saved_match_dist = d.params.saved_match_dist;
    var saved_match_len = d.params.saved_match_len;

    while ((src_pos < in_buf.len) or ((d.params.flush != TDEFLFlush.None) and (lookahead_size != 0))) {
        const src_buf_left = in_buf.len - src_pos;
        const num_bytes_to_process =
            MIN(u32, @truncate(u32, src_buf_left), MAX_MATCH_LEN - lookahead_size);

        if ((lookahead_size + d.dict.size) >= (MIN_MATCH_LEN - 1) and (num_bytes_to_process > 0)) {
            var dictb = d.dict.b;

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
            var dictb = d.dict.b;
            for (in_buf[src_pos..src_pos + num_bytes_to_process]) |c| {
                const dst_pos = (lookahead_pos + lookahead_size) & LZ_DICT_SIZE_MASK;
                dictb.dict[dst_pos] = c;
                if (dst_pos < (MAX_MATCH_LEN - 1)) {
                     dictb.dict[LZ_DICT_SIZE + dst_pos] = c;
                }

                lookahead_size += 1;
                if ((lookahead_size + d.dict.size) >= MIN_MATCH_LEN) {
                    const ins_pos = lookahead_pos + lookahead_size - 3;
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
            cur_match_dist = dist_len.distance;
            cur_match_len = dist_len.length;
        }

        const far_and_small = (cur_match_len == MIN_MATCH_LEN) and (cur_match_dist >= (8 * 1024));
        const filter_small = (((d.params.flags & TDEFL_FILTER_MATCHES) != 0) and (cur_match_len <= 5));
        if (far_and_small or filter_small or (cur_pos == cur_match_dist)) {
            cur_match_dist = 0;
            cur_match_len = 0;
        }

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

    return true;
}


/// Main compression function. Puts output into buffer.
///
/// # Returns
/// Returns a tuple containing the current status of the compressor, the current position
/// in the input buffer and the current position in the output buffer.
pub fn compress(d: *Compressor, in_buf: []u8, out_buf: []u8,
                flush: TDEFLFlush) ReturnTuple {
    var callback = Callback.new_callback_buf(in_buf, out_buf);
    return compress_inner(d, &callback, flush);
}

fn flush_output_buffer(cb: *Callback, p: *Params) ReturnTuple {
    var res = ReturnTuple.new(TDEFLStatus.Okay, p.src_pos, 0);
    //if let CallbackOut::Buf(ref mut cb) = c.out {
    const n = MIN(usize, cb.out.len - p.out_buf_ofs, p.flush_remaining);
    // if n != 0 {
    //     (&mut cb.out_buf[p.out_buf_ofs..p.out_buf_ofs + n])
    //         .copy_from_slice(&p.local_buf.b[p.flush_ofs as usize..p.flush_ofs as usize + n]);
    // }
    const nn = @truncate(u32, n & @maxValue(u32));
    p.flush_ofs += nn;
    p.flush_remaining -= nn;
    p.out_buf_ofs += nn;
    res.outpos = p.out_buf_ofs;
    //}

    if (p.finished and (p.flush_remaining == 0)) {
        res.status = TDEFLStatus.Done;
    }

    return res;
}

fn compress_inner(d: *Compressor, callback: *Callback,
                  pflush: TDEFLFlush) ReturnTuple {
    var res: ReturnTuple = undefined;
    var flush = pflush;
    d.params.out_buf_ofs = 0;
    d.params.src_pos = 0;

    var prev_ok = d.params.prev_return_status == TDEFLStatus.Okay;
    var flush_finish_once = (d.params.flush != TDEFLFlush.Finish) or (flush == TDEFLFlush.Finish);

    d.params.flush = flush;
    if (!prev_ok or !flush_finish_once) {
        d.params.prev_return_status = TDEFLStatus.BadParam;
        return ReturnTuple.new(d.params.prev_return_status, 0, 0);
    }

    if ((d.params.flush_remaining != 0) or d.params.finished) {
        res = flush_output_buffer(callback, &d.params);
        d.params.prev_return_status = res.status;
        return res;
    }

    const one_probe = (d.params.flags & MAX_PROBES_MASK) == 1;
    const greedy = (d.params.flags & TDEFL_GREEDY_PARSING_FLAG) != 0;
    const filter_or_rle_or_raw = (d.params.flags &
        (TDEFL_FILTER_MATCHES | TDEFL_FORCE_ALL_RAW_BLOCKS | TDEFL_RLE_MATCHES)) !=
        0;

    // const compress_success = if (one_probe and greedy and !filter_or_rle_or_raw)
    //     compress_fast(d, callback) else compress_normal(d, callback);

    const compress_success = compress_normal(d, callback);
    if (!compress_success) {
        return ReturnTuple.new(d.params.prev_return_status, d.params.src_pos, d.params.out_buf_ofs);
    }

    //if let Some(in_buf) = callback.in_buf {
        if ((d.params.flags & (TDEFL_WRITE_ZLIB_HEADER | TDEFL_COMPUTE_ADLER32)) != 0) {
            //d.params.adler32 = update_adler32(d.params.adler32, &in_buf[..d.params.src_pos]);
        }
    //}

    const flush_none = (d.params.flush == TDEFLFlush.None);
    const in_left = 0; //callback.in_buf.map_or(0, |buf| buf.len()) - d.params.src_pos;
    const remaining = (in_left != 0) or (d.params.flush_remaining != 0);
    if (!flush_none and (d.dict.lookahead_size == 0) and !remaining) {
        flush = d.params.flush;
        var x = flush_block(d, callback, flush);
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
        //         d.params.finished = d.params.flush == TDEFLFlush::Finish;
        //         if d.params.flush == TDEFLFlush::Full {
        //             memset(&mut d.dict.b.hash[..], 0);
        //             memset(&mut d.dict.b.next[..], 0);
        //             d.dict.size = 0;
        //         }
        //     }
        // }
    }

    res = flush_output_buffer(callback, &d.params);
    d.params.prev_return_status = res.status;

    return res;
}


test "Compressor" {
    var c = Compressor.new(0);
    var input = "Deflate late";
    var output = []u8 {0} ** 1024;
    var r = compress(&c, input[0..], output[0..], TDEFLFlush.Finish);
    warn("done..\n");
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

// test "Default Huffman" {
//     var h = DefaultHuffman();
//     warn("sizeof HuffmanEntry={}\n", usize(@sizeOf(HuffmanEntry)));
//     warn("sizeof Huffman={}\n", usize(@sizeOf(Huffman)));
//     h.start_static_block();
// }

