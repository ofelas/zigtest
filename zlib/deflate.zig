// -*- mode:zig; indent-tabs-mode:nil;  -*-
// See https://github.com/richgel999/miniz
//
const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;
const assert = std.debug.assert;
const adler32 = @import("adler32.zig").adler32;

// Purposely making these tables static for faster init and thread safety.
const s_tdefl_len_sym = [256]u16 {
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

const s_tdefl_len_extra = [256]u3 {
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

const s_tdefl_small_dist_sym = [512]u5 {
    0, 1, 2, 3, 4, 4, 5, 5, 6, 6, 6, 6, 7, 7, 7, 7,
    8, 8, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9, 9, 9,
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

const s_tdefl_small_dist_extra = [512]u3 {
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

const s_tdefl_large_dist_sym = [128]u5 {
    0, 0, 18, 19, 20, 20, 21, 21, 22, 22, 22, 22, 23, 23, 23, 23,
    24, 24, 24, 24, 24, 24, 24, 24, 25, 25, 25, 25, 25, 25, 25, 25,
    26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26,
    27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27,
    28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
    28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
    29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29,
    29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29
};

const s_tdefl_large_dist_extra = [128]u5 {
    0, 0, 8, 8, 9, 9, 9, 9, 10, 10, 10, 10, 10, 10, 10, 10,
    11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11,
    12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
    12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
    13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
    13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
    13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
    13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13
};

const TDEFL_WRITE_ZLIB_HEADER = 0x01000;
const TDEFL_COMPUTE_ADLER32 = 0x02000;
const TDEFL_GREEDY_PARSING_FLAG = 0x04000;
const TDEFL_NONDETERMINISTIC_PARSING_FLAG = 0x08000;
const TDEFL_RLE_MATCHES = 0x10000;
const TDEFL_FILTER_MATCHES = 0x20000;
const TDEFL_FORCE_ALL_STATIC_BLOCKS = 0x40000;
const TDEFL_FORCE_ALL_RAW_BLOCKS = 0x80000;

const TDEFL_MAX_HUFF_TABLES = 3;
const TDEFL_MAX_HUFF_SYMBOLS_0 = 288;
const TDEFL_MAX_HUFF_SYMBOLS_1 = 32;
const TDEFL_MAX_HUFF_SYMBOLS_2 = 19;
const TDEFL_LZ_DICT_SIZE = 32768; // power of 2
const TDEFL_LZ_DICT_SIZE_MASK = TDEFL_LZ_DICT_SIZE - 1;
const TDEFL_MIN_MATCH_LEN = 3;
const TDEFL_MAX_MATCH_LEN = 258;
const TDEFL_MAX_SUPPORTED_HUFF_CODESIZE = 32;

pub const TDEFL_NO_FLUSH = 0;
pub const TDEFL_SYNC_FLUSH = 2;
pub const TDEFL_FULL_FLUSH = 3;
pub const TDEFL_FINISH = 4;

pub const MZ_Flags = u32;

// is this the way to do ifdef style things?!?
// probably make it an argument to create the DeflateCompressor?!?
const small = false;
const TDEFL_LZ_CODE_BUF_MULTIPLIER = comptime if (small) 24 else 64;
const TDEFL_LZ_CODE_BUF_SIZE = TDEFL_LZ_CODE_BUF_MULTIPLIER * 1024;
const TDEFL_LZ_HASH_BITS = comptime if (small) 12 else 15;

const TDEFL_OUT_BUF_SIZE = (TDEFL_LZ_CODE_BUF_SIZE * 13) / 10;
const TDEFL_MAX_HUFF_SYMBOLS = 288;
const TDEFL_LEVEL1_HASH_SIZE_MASK = 4095;
const TDEFL_LZ_HASH_SHIFT = (TDEFL_LZ_HASH_BITS + 2) / 3;
const TDEFL_LZ_HASH_SIZE = 1 << TDEFL_LZ_HASH_BITS;

inline fn MZ_MIN(comptime T: type, a: T, b: T) T {
    if (T == bool) {
        return a or b;
    } else if (a <= b) {
        return a;
    } else {
        return b;
    }
}

pub const DeflateCompressor = struct {
    //tdefl_put_buf_func_ptr pPut_buf_func;
    //void *pPut_buf_user;
    flags: MZ_Flags,
    max_probes: [2]u32,
    greedy_parsing: bool,
    adler32: u32,
    lookahead_pos: usize,
    lookahead_size: usize,
    dict_size: usize,
    //mz_uint8 *lz_code_buf_pos, *lz_flags_pos, *output_buf_pos, *output_buf_end_pos;
    lz_code_buf_pos: u32,
    lz_flags_pos: u32,
    output_buf_pos: u32,
    output_buf_end_pos: u32,
    num_flags_left: u32,
    total_lz_bytes: usize,
    lz_code_buf_dict_pos: usize,
    bits_in: u5,
    bit_buffer: u32,
    saved_match_dist: usize,
    saved_match_len: usize,
    saved_lit: u32,
    output_flush_ofs: usize,
    output_flush_remaining: usize,
    finished: bool,
    block_index: u32,
    wants_to_finish: u32,
    //tdefl_status prev_return_status;
    prev_return_status: bool,
    inbuf: []const u8,
    outbuf: []u8,
    //size_t *pIn_buf_size, *pOut_buf_size;
    in_buf_size: usize,
    out_buf_size: usize,
    //tdefl_flush flush;
    flush: u32,
    //const mz_uint8 *src_pos;
    src_pos: usize,
    src_buf_left: usize,
    out_buf_ofs: usize,
    dict: [TDEFL_LZ_DICT_SIZE + TDEFL_MAX_MATCH_LEN - 1]u8,
    huff_count: [TDEFL_MAX_HUFF_TABLES][TDEFL_MAX_HUFF_SYMBOLS]u16,
    huff_codes: [TDEFL_MAX_HUFF_TABLES][TDEFL_MAX_HUFF_SYMBOLS]u16,
    huff_code_sizes: [TDEFL_MAX_HUFF_TABLES][TDEFL_MAX_HUFF_SYMBOLS]u5,
    lz_code_buf: [TDEFL_LZ_CODE_BUF_SIZE]u8,
    next: [TDEFL_LZ_DICT_SIZE]u16,
    hash: [TDEFL_LZ_HASH_SIZE]u16,
    output_buf: [TDEFL_OUT_BUF_SIZE]u8,

    inline fn put_bits(comp: *DeflateCompressor, bits: u32, len: u5) void {
        assert(bits <= ((u32(1) << len) - 1));
        // warn("putting bits={x04}, len={}, bits_in={}\n", bits, len, comp.bits_in);
        comp.bit_buffer |= (u32(bits) << u5(comp.bits_in));
        comp.bits_in += len;
        while (comp.bits_in >= 8) {
            if (comp.output_buf_pos < comp.output_buf_end_pos) {
                // warn("PUTTING@{} {x02}\n", comp.output_buf_pos, @intCast(u8, comp.bit_buffer & 0xff));
                comp.output_buf[comp.output_buf_pos] = @intCast(u8, comp.bit_buffer & 0xff);
                comp.output_buf_pos += 1;
            } // else error?
            comp.bit_buffer >>= 8;
            comp.bits_in -= 8;
        }
    }

    // Record a literal
    inline fn record_literal(comp: *DeflateCompressor, lit: u8) void {
        // warn("record_literal@{} total={}, lit={x02}\n", comp.lz_code_buf_pos, comp.total_lz_bytes, lit);
        comp.total_lz_bytes += 1;
        comp.lz_code_buf[comp.lz_code_buf_pos] = lit;
        comp.lz_code_buf_pos += 1;
        comp.lz_code_buf[comp.lz_flags_pos] = comp.lz_code_buf[comp.lz_flags_pos] >> 1;

        assert(comp.num_flags_left > 0);
        comp.num_flags_left -= 1;
        if (comp.num_flags_left == 0)
        {
            comp.num_flags_left = 8;
            comp.lz_code_buf_pos += 1;
            comp.lz_flags_pos = comp.lz_code_buf_pos;
        }
        comp.huff_count[0][lit] += 1;
    }

    /// Record a match
    inline fn record_match(comp: *DeflateCompressor, match_len: usize, pmatch_dist: usize) void {
        //warn("record_match len={}, distance={}\n", match_len, pmatch_dist);
        var match_dist = pmatch_dist;

        assert((match_len >= TDEFL_MIN_MATCH_LEN) and (match_dist >= 1) and (match_dist <= TDEFL_LZ_DICT_SIZE));
        comp.total_lz_bytes += match_len;
        comp.lz_code_buf[comp.lz_code_buf_pos] = @intCast(u8, (match_len - TDEFL_MIN_MATCH_LEN) & 0xff);
        match_dist -= 1;
        comp.lz_code_buf[comp.lz_code_buf_pos + 1] = @intCast(u8, match_dist & 0xff);
        comp.lz_code_buf[comp.lz_code_buf_pos + 2] = @intCast(u8, (match_dist >> 8) & 0xff);
        comp.lz_code_buf_pos += 3;
        comp.lz_code_buf[comp.lz_flags_pos] = (comp.lz_code_buf[comp.lz_flags_pos] >> 1) | 0x80;

        assert(comp.num_flags_left > 0);
        comp.num_flags_left -= 1;
        if (comp.num_flags_left == 0) {
            comp.num_flags_left = 8;
            comp.lz_code_buf_pos += 1;
            comp.lz_flags_pos = comp.lz_code_buf_pos;
        }
        //warn("match_dist={}, match_len={}\n", match_dist, match_len);
        const dist = if (match_dist < 512) s_tdefl_small_dist_sym[match_dist & 511]
                     else s_tdefl_large_dist_sym[(match_dist >> 8) & 127];
        comp.huff_count[1][dist] += 1;

        if (match_len >= TDEFL_MIN_MATCH_LEN) {
            comp.huff_count[0][s_tdefl_len_sym[match_len - TDEFL_MIN_MATCH_LEN]] += 1;
        }
    }


    fn start_static_block(comp: *DeflateCompressor) void {
        //DEBUG: warn("start_static_block\n");
        var i: usize = 0;
        //var p: usize = 0;
        while (i <= 143) : (i += 1) {
            comp.huff_code_sizes[0][i] = 8;
        }
        while (i <= 255) : (i += 1) {
            comp.huff_code_sizes[0][i] = 9;
        }
        while (i <= 279) : (i += 1) {
            comp.huff_code_sizes[0][i] = 7;
        }
        while (i <= 287) : (i += 1) {
            comp.huff_code_sizes[0][i] = 8;
        }

        i = 0;
        while (i < 32) : (i += 1) {
            comp.huff_code_sizes[1][i] = 5;
        }

        optimize_huffman_table(comp, 0, 288, 15, true);
        optimize_huffman_table(comp, 1, 32, 15, true);

        comp.put_bits(1, 2);
    }

    fn compress_block(comp: *DeflateCompressor, static_block: bool) bool {
        //warn("compress_block static={}\n", static_block);
        if (static_block) {
            comp.start_static_block();
        } else {
            start_dynamic_block(comp);
        }
        return compress_lz_codes(comp);
    }
};

fn tdefl_init(comp: *DeflateCompressor, flags: MZ_Flags) void {
    //comp.pPut_buf_func = pPut_buf_func;
    //comp.pPut_buf_user = pPut_buf_user;
    comp.flags = MZ_Flags(flags);
    comp.max_probes[0] = 1 + ((flags & 0xFFF) + 2) / 3;
    comp.greedy_parsing = (flags & TDEFL_GREEDY_PARSING_FLAG) != 0;
    comp.max_probes[1] = 1 + (((flags & 0xFFF) >> 2) + 2) / 3;
    //warn("max_probes {} {}\n", comp.max_probes[0], comp.max_probes[1]);
    if ((flags & TDEFL_NONDETERMINISTIC_PARSING_FLAG) != 0) {
        //MZ_CLEAR_OBJ(comp.hash);
        for (comp.hash) |*v| {
            v.* = 0;
        }
    }
    comp.lookahead_pos = 0;
    comp.lookahead_size = 0;
    comp.dict_size = 0;
    comp.total_lz_bytes = 0;
    comp.lz_code_buf_dict_pos = 0;
    comp.bits_in = 0;
    comp.output_flush_ofs = 0;
    comp.output_flush_remaining = 0;
    comp.finished = false;
    comp.block_index = 0;
    comp.bit_buffer = 0;
    comp.wants_to_finish = 0;
    // position into lz_code_buf
    //comp.lz_code_buf_pos = comp.lz_code_buf + 1;
    comp.lz_code_buf_pos = 1;
    //comp.lz_flags_pos = comp.lz_code_buf;
    comp.lz_flags_pos = 0;
    comp.num_flags_left = 8;
    // position into output_buf
    comp.output_buf_pos = 0;
    comp.output_buf_end_pos = 0;
    comp.prev_return_status = true;
    comp.saved_match_dist = 0;
    comp.saved_match_len = 0;
    comp.saved_lit = 0;
    comp.adler32 = 1;
    comp.inbuf = undefined;
    comp.outbuf = undefined;
    comp.in_buf_size = 0;
    comp.out_buf_size = 0;
    comp.flush = TDEFL_NO_FLUSH;
    comp.src_pos = 0;
    comp.src_buf_left = 0;
    comp.out_buf_ofs = 0;
    if ((flags & TDEFL_NONDETERMINISTIC_PARSING_FLAG) == 0) {
        //MZ_CLEAR_OBJ(comp.dict);
        for (comp.dict) |*v|{
            v.* = 0;
        }
    }
    //memset(&comp.huff_count[0][0], 0, sizeof(comp.huff_count[0][0]) * TDEFL_MAX_HUFF_SYMBOLS_0);
    //memset(&comp.huff_count[1][0], 0, sizeof(comp.huff_count[1][0]) * TDEFL_MAX_HUFF_SYMBOLS_1);
    {
        var i: u32 = 0;
        while (i < TDEFL_MAX_HUFF_SYMBOLS_0) : (i += 1) {
            comp.huff_count[0][i] = 0;
        }
        i = 0;
        while (i < TDEFL_MAX_HUFF_SYMBOLS_1) : (i += 1) {
            comp.huff_count[1][i] = 0;
        }
    }
}


// Radix sorts tdefl_syfreq[] array by 16-bit key key. Returns ptr to sorted values.
const tdefl_syfreq = struct {
    key: u16,
    syindex: u16,
};

fn tdefl_radix_sort_syms(nusyms: usize, pSyms0: []tdefl_syfreq, pSyms1: []tdefl_syfreq) []tdefl_syfreq {
    //mz_uint32 total_passes = 2, pass_shift, pass, i, hist[256 * 2];
    var total_passes: u32 = 2;
    var pass_shift: u4 = 0;
    var pass: u32 = 0;
    var i: u32 = 0;
    var hist = []u32 {0} ** (256 + 2);
    var pCur_syms = pSyms0;
    var pNew_syms = pSyms1;
    // MZ_CLEAR_OBJ(hist);
    assert(pSyms0.len >= nusyms);
    i = 0;
    while (i < nusyms) {
        const freq = pSyms0[i].key;
        hist[freq & 0xFF] += 1;
        hist[256 + ((freq >> 8) & 0xFF)] += 1;
        i += 1;
    }
    while ((total_passes > 1) and (nusyms == hist[(total_passes - 1) * 256])) {
        total_passes -= 1;
    }
    pass_shift = 0;
    pass = 0;
    while (pass < total_passes) {
        var pHist = hist[pass << 8..];
        var offsets: [256]u32 = undefined;
        var cur_ofs: u32 = 0;
        i = 0;
        while (i < 256) {
            offsets[i] = cur_ofs;
            cur_ofs += pHist[i];
            i += 1;
        }
        i = 0;
        while (i < nusyms) {
            const idx = (pCur_syms[i].key >> pass_shift) & 0xFF;
            pNew_syms[offsets[idx]] = pCur_syms[i];
            offsets[idx] += 1;
            i += 1;
        }
        // tdefl_syfreq *t = pCur_syms;
        // pCur_syms = pNew_syms;
        // pNew_syms = t;
        // -- swap --
        const t = pCur_syms;
        pCur_syms = pNew_syms;
        pNew_syms = t;

        pass_shift += 8;
        pass += 1;
    }
    return pCur_syms;
}

fn find_match(comp: *DeflateCompressor, lookahead_pos: usize,
              max_dist: usize, max_match_len: usize,
              pmatch_dist: *usize, pmatch_len: *usize) void {
    //     mz_uint dist, pos = lookahead_pos & TDEFL_LZ_DICT_SIZE_MASK, match_len = *pmatch_len, probe_pos = pos, next_probe_pos, probe_len;
    //warn("find_match: {},{},{},{},{}\n", lookahead_pos, max_dist, max_match_len, pmatch_dist.*, pmatch_len.*);
    var dist: u16 = 0;
    var next_probe_pos: u16 = 0;
    var pos = lookahead_pos & TDEFL_LZ_DICT_SIZE_MASK;
    var match_len = pmatch_len.*;
    var probe_pos = pos;
    var nuprobes_left = if (match_len >= 32) comp.max_probes[1] else comp.max_probes[0];
    //     const mz_uint8 *s = comp.dict + pos, *p, *q;
    var s = pos;
    var p:@typeOf(s) = 0;
    var q:@typeOf(s) = 0;
    var c0 = comp.dict[pos + match_len];
    var c1 = comp.dict[pos + match_len - 1];
    assert(max_match_len <= TDEFL_MAX_MATCH_LEN);
    if (max_match_len <= match_len) {
        return;
    }
    //     for (;;)
    while (true) {
        //         for (;;)
        while (true) {
            //warn("nuprobes_left = {}, {x02}, {x02}, {}\n", nuprobes_left, c0, c1, comp.next[probe_pos]);
            nuprobes_left -= 1;
            if (nuprobes_left == 0) {
                return;
            }
            // #define TDEFL_PROBE
            next_probe_pos = comp.next[probe_pos];
            if (next_probe_pos == 0) {
                return;
            } else {
                dist = @truncate(u16, lookahead_pos - next_probe_pos);
                if (dist > max_dist) {
                    return;
                }
            }
            probe_pos = next_probe_pos & TDEFL_LZ_DICT_SIZE_MASK;
            if ((comp.dict[probe_pos + match_len] == c0) and (comp.dict[probe_pos + match_len - 1] == c1)) {
                break;
            }
            // end TDEFL_PROBE
            //             TDEFL_PROBE;
            next_probe_pos = comp.next[probe_pos];
            if (next_probe_pos == 0) {
                return;
            } else {
                dist = @truncate(u16, lookahead_pos - next_probe_pos);
                if (dist > max_dist) {
                    return;
                }
            }
            probe_pos = next_probe_pos & TDEFL_LZ_DICT_SIZE_MASK;
            if ((comp.dict[probe_pos + match_len] == c0) and (comp.dict[probe_pos + match_len - 1] == c1)) {
                break;
            }
            //             TDEFL_PROBE;
            next_probe_pos = comp.next[probe_pos];
            if (next_probe_pos == 0) {
                return;
            } else {
                dist = @truncate(@typeOf(dist), lookahead_pos - next_probe_pos);
                if (dist > max_dist) {
                    return;
                }
            }
            probe_pos = next_probe_pos & TDEFL_LZ_DICT_SIZE_MASK;
            if ((comp.dict[probe_pos + match_len] == c0) and (comp.dict[probe_pos + match_len - 1] == c1)) {
                break;
            }
            //             TDEFL_PROBE;
        }
        if (dist == 0) {
            break;
        }
        p = s;
        // q = comp.dict + probe_pos;
        q = probe_pos;
        var probe_len: @typeOf(max_match_len) = 0;
        //  for (probe_len = 0; probe_len < max_match_len; probe_len++) {
        //      if (*p++ != *q++) {
        //          break;
        //      }
        //  }
        while (probe_len < max_match_len) : (probe_len += 1){
            if (comp.dict[p] != comp.dict[q]) {
                p += 1;
                q += 1;
                break;
            }
            p += 1;
            q += 1;
        }
        if (probe_len > match_len) {
            pmatch_dist.* = dist;
            pmatch_len.* = probe_len;
            match_len = probe_len;
            // if ((*pmatch_len = match_len = probe_len) == max_match_len)
            //     return;
            if (probe_len == match_len) {
                //warn("probe_len={}, match_len={}\n", probe_len, match_len);
                return;
            }
            c0 = comp.dict[pos + match_len];
            c1 = comp.dict[pos + match_len - 1];
        }
    }
}

const mz_bitmasks = []u16{ 0x0000, 0x0001, 0x0003, 0x0007, 0x000F, 0x001F, 0x003F, 0x007F, 0x00FF, 0x01FF, 0x03FF, 0x07FF, 0x0FFF, 0x1FFF, 0x3FFF, 0x7FFF, 0xFFFF };

fn optimize_huffman_table(comp: *DeflateCompressor, table_num: u8, table_len: usize,
                          code_size_limit: usize, static_table: bool) void {
    //warn("optimize_huffman_table\n");
    // int i, j, l, num_codes[1 + TDEFL_MAX_SUPPORTED_HUFF_CODESIZE];
    var num_codes = []u16 {0} **  (1 + TDEFL_MAX_SUPPORTED_HUFF_CODESIZE);
    var next_code  = []u16 {0} ** (1 + TDEFL_MAX_SUPPORTED_HUFF_CODESIZE);
    // MZ_CLEAR_OBJ(num_codes);
    var i: usize = 0;
    if (static_table)
    {
        //DEBUG: warn("static_table\n");
        i = 0;
        while (i < table_len) : (i += 1) {
            num_codes[comp.huff_code_sizes[table_num][i]] += 1;
        }
    } else {
        warn("!!! not static_table, unimplemented\n");
        // tdefl_sym_freq syms0[TDEFL_MAX_HUFF_SYMBOLS], syms1[TDEFL_MAX_HUFF_SYMBOLS], *pSyms;
        // int num_used_syms = 0;
        // const mz_uint16 *pSym_count = &comp.m_huff_count[table_num][0];
        // for (i = 0; i < table_len; i++)
        //     if (pSym_count[i])
        //     {
        //         syms0[num_used_syms].m_key = (mz_uint16)pSym_count[i];
        //         syms0[num_used_syms++].m_sym_index = (mz_uint16)i;
        //     }

        // pSyms = tdefl_radix_sort_syms(num_used_syms, syms0, syms1);
        // tdefl_calculate_minimum_redundancy(pSyms, num_used_syms);

        // for (i = 0; i < num_used_syms; i++)
        //     num_codes[pSyms[i].m_key]++;

        // tdefl_huffman_enforce_max_code_size(num_codes, num_used_syms, code_size_limit);

        // MZ_CLEAR_OBJ(comp.m_huff_code_sizes[table_num]);
        // MZ_CLEAR_OBJ(comp.m_huff_codes[table_num]);
        // for (i = 1, j = num_used_syms; i <= code_size_limit; i++)
        //     for (l = num_codes[i]; l > 0; l--)
        //         comp.m_huff_code_sizes[table_num][pSyms[--j].m_sym_index] = (mz_uint8)(i);
    }

    next_code[1] = 0;
    // for (j = 0, i = 2; i <= code_size_limit; i++)
    //     next_code[i] = j = ((j + num_codes[i - 1]) << 1);
    var j: usize = 0;
    i = 2;
    while (i <= code_size_limit ) : (i += 1) {
        j = ((j + num_codes[i - 1]) << 1);
        next_code[i] = @truncate(u16, j);
    }
    // for (i = 0; i < table_len; i++)
    // {
    //     mz_uint rev_code = 0, code, code_size;
    //     if ((code_size = comp.m_huff_code_sizes[table_num][i]) == 0)
    //         continue;
    //     code = next_code[code_size]++;
    //     for (l = code_size; l > 0; l--, code >>= 1)
    //         rev_code = (rev_code << 1) | (code & 1);
    //     comp.m_huff_codes[table_num][i] = (mz_uint16)rev_code;
    // }
    //DEBUG: warn("table_len={}\n", table_len);
    i = 0;
    while (i < table_len) : (i += 1) {
        const code_size = comp.huff_code_sizes[table_num][i];
        if (code_size == 0) {
            continue;
        }
        var code = next_code[code_size];
        next_code[code_size] += 1;
        var rev_code: u16 = 0;
        j = code_size;
        while (j > 0) : (j -= 1) {
            rev_code = (rev_code << 1) | (code & 1);
            code >>= 1;
        }
        comp.huff_codes[table_num][i] = rev_code;
    }
}

fn start_dynamic_block(comp: *DeflateCompressor) void {
    warn("NOT IMPLEMENTED: start_dynamic_block\n");
    // int num_lit_codes, num_dist_codes, num_bit_lengths;
    // mz_uint i, total_code_sizes_to_pack, num_packed_code_sizes, rle_z_count, rle_repeat_count, packed_code_sizes_index;
    // mz_uint8 code_sizes_to_pack[TDEFL_MAX_HUFF_SYMBOLS_0 + TDEFL_MAX_HUFF_SYMBOLS_1], packed_code_sizes[TDEFL_MAX_HUFF_SYMBOLS_0 + TDEFL_MAX_HUFF_SYMBOLS_1], prev_code_size = 0xFF;

    // d->m_huff_count[0][256] = 1;

    // tdefl_optimize_huffman_table(d, 0, TDEFL_MAX_HUFF_SYMBOLS_0, 15, MZ_FALSE);
    // tdefl_optimize_huffman_table(d, 1, TDEFL_MAX_HUFF_SYMBOLS_1, 15, MZ_FALSE);

    // for (num_lit_codes = 286; num_lit_codes > 257; num_lit_codes--)
    //     if (d->m_huff_code_sizes[0][num_lit_codes - 1])
    //         break;
    // for (num_dist_codes = 30; num_dist_codes > 1; num_dist_codes--)
    //     if (d->m_huff_code_sizes[1][num_dist_codes - 1])
    //         break;

    // memcpy(code_sizes_to_pack, &d->m_huff_code_sizes[0][0], num_lit_codes);
    // memcpy(code_sizes_to_pack + num_lit_codes, &d->m_huff_code_sizes[1][0], num_dist_codes);
    // total_code_sizes_to_pack = num_lit_codes + num_dist_codes;
    // num_packed_code_sizes = 0;
    // rle_z_count = 0;
    // rle_repeat_count = 0;

    // memset(&d->m_huff_count[2][0], 0, sizeof(d->m_huff_count[2][0]) * TDEFL_MAX_HUFF_SYMBOLS_2);
    // for (i = 0; i < total_code_sizes_to_pack; i++)
    // {
    //     mz_uint8 code_size = code_sizes_to_pack[i];
    //     if (!code_size)
    //     {
    //         TDEFL_RLE_PREV_CODE_SIZE();
    //         if (++rle_z_count == 138)
    //         {
    //             TDEFL_RLE_ZERO_CODE_SIZE();
    //         }
    //     }
    //     else
    //     {
    //         TDEFL_RLE_ZERO_CODE_SIZE();
    //         if (code_size != prev_code_size)
    //         {
    //             TDEFL_RLE_PREV_CODE_SIZE();
    //             d->m_huff_count[2][code_size] = (mz_uint16)(d->m_huff_count[2][code_size] + 1);
    //             packed_code_sizes[num_packed_code_sizes++] = code_size;
    //         }
    //         else if (++rle_repeat_count == 6)
    //         {
    //             TDEFL_RLE_PREV_CODE_SIZE();
    //         }
    //     }
    //     prev_code_size = code_size;
    // }
    // if (rle_repeat_count)
    // {
    //     TDEFL_RLE_PREV_CODE_SIZE();
    // }
    // else
    // {
    //     TDEFL_RLE_ZERO_CODE_SIZE();
    // }

    // tdefl_optimize_huffman_table(d, 2, TDEFL_MAX_HUFF_SYMBOLS_2, 7, MZ_FALSE);

    // TDEFL_PUT_BITS(2, 2);

    // TDEFL_PUT_BITS(num_lit_codes - 257, 5);
    // TDEFL_PUT_BITS(num_dist_codes - 1, 5);

    // for (num_bit_lengths = 18; num_bit_lengths >= 0; num_bit_lengths--)
    //     if (d->m_huff_code_sizes[2][s_tdefl_packed_code_size_syms_swizzle[num_bit_lengths]])
    //         break;
    // num_bit_lengths = MZ_MAX(4, (num_bit_lengths + 1));
    // TDEFL_PUT_BITS(num_bit_lengths - 4, 4);
    // for (i = 0; (int)i < num_bit_lengths; i++)
    //     TDEFL_PUT_BITS(d->m_huff_code_sizes[2][s_tdefl_packed_code_size_syms_swizzle[i]], 3);

    // for (packed_code_sizes_index = 0; packed_code_sizes_index < num_packed_code_sizes;)
    // {
    //     mz_uint code = packed_code_sizes[packed_code_sizes_index++];
    //     MZ_ASSERT(code < TDEFL_MAX_HUFF_SYMBOLS_2);
    //     TDEFL_PUT_BITS(d->m_huff_codes[2][code], d->m_huff_code_sizes[2][code]);
    //     if (code >= 16)
    //         TDEFL_PUT_BITS(packed_code_sizes[packed_code_sizes_index++], "\02\03\07"[code - 16]);
    // }
}


fn compress_lz_codes(comp: *DeflateCompressor) bool {
    //warn("compress_lz_codes\n");
    var flags: u32 = 1;
    var lz_code_pos: usize = 0;
    while (lz_code_pos < comp.lz_code_buf_pos) : (flags >>= 1) {
        if (flags == 1) {
            flags = @typeOf(flags)(comp.lz_code_buf[lz_code_pos]) | 0x100;
            lz_code_pos += 1;
        }
        //warn("flags={x08}\n", flags);
        if ((flags & 1) == 1) {
            var sym: u8 = 0;
            var num_extra_bits: u5 = 0;
            const match_len = comp.lz_code_buf[lz_code_pos];
            const match_dist = (comp.lz_code_buf[lz_code_pos + 1] | (u16(comp.lz_code_buf[lz_code_pos + 2]) << 8));
            lz_code_pos += 3;
            //warn("match len={}, dist={}\n", match_len, match_dist);
            assert(comp.huff_code_sizes[0][s_tdefl_len_sym[match_len]] != 0);
            comp.put_bits(comp.huff_codes[0][s_tdefl_len_sym[match_len]], comp.huff_code_sizes[0][s_tdefl_len_sym[match_len]]);
            comp.put_bits(match_len & mz_bitmasks[s_tdefl_len_extra[match_len]], s_tdefl_len_extra[match_len]);

            if (match_dist < 512) {
                sym = s_tdefl_small_dist_sym[match_dist];
                num_extra_bits = s_tdefl_small_dist_extra[match_dist];
            } else {
                sym = s_tdefl_large_dist_sym[match_dist >> 8];
                num_extra_bits = s_tdefl_large_dist_extra[match_dist >> 8];
            }
            assert(comp.huff_code_sizes[1][sym] != 0);
            comp.put_bits(comp.huff_codes[1][sym], comp.huff_code_sizes[1][sym]);
            comp.put_bits(match_dist & mz_bitmasks[num_extra_bits], num_extra_bits);
        } else {
            const lit = comp.lz_code_buf[lz_code_pos];
            lz_code_pos += 1;
            assert(comp.huff_code_sizes[0][lit] != 0);
            comp.put_bits(comp.huff_codes[0][lit], comp.huff_code_sizes[0][lit]);
        }
    }

    comp.put_bits(comp.huff_codes[0][256], comp.huff_code_sizes[0][256]);

    return (comp.output_buf_pos < comp.output_buf_end_pos);
}

fn flush_block(comp: *DeflateCompressor, flush: u32) i32 {
    //warn("flush_block {x8}, {}\n", flush, comp.total_lz_bytes);
    // mz_uint saved_bit_buf, saved_bits_in;
    // mz_uint8 *saved_output_buf_pos;
    // mz_bool comp_block_succeeded = MZ_FALSE;
    var comp_block_succeeded = false;
    // int n, use_raw_block = ((comp.flags & TDEFL_FORCE_ALL_RAW_BLOCKS) != 0) && (comp.lookahead_pos - comp.lz_code_buf_dict_pos) <= comp.dict_size;
    var use_raw_block = ((comp.flags & TDEFL_FORCE_ALL_RAW_BLOCKS) != 0)
        and ((comp.lookahead_pos - comp.lz_code_buf_dict_pos) <= comp.dict_size);
    // mz_uint8 *toutput_buf_start_pos = ((comp.pPut_buf_func == NULL) && ((*comp.pOut_buf_size - comp.out_buf_ofs) >= TDEFL_OUT_BUF_SIZE)) ? ((mz_uint8 *)comp.pOut_buf + comp.out_buf_ofs) : comp.output_buf;
    var toutput_buf_start_pos: u32 = @intCast(u32, comp.out_buf_ofs);
    comp.output_buf_pos = toutput_buf_start_pos;
    comp.output_buf_end_pos = comp.output_buf_pos + TDEFL_OUT_BUF_SIZE - 16;

    assert(comp.output_flush_remaining == 0);
    comp.output_flush_ofs = 0;
    comp.output_flush_remaining = 0;

    // *comp.lz_flags_pos = (mz_uint8)(*comp.lz_flags_pos >> comp.num_flags_left);
    comp.lz_flags_pos = comp.lz_flags_pos >> @intCast(u5, comp.num_flags_left);
    if (comp.num_flags_left == 8) {
        comp.lz_code_buf_pos -= 1;
    }

    if (((comp.flags & TDEFL_WRITE_ZLIB_HEADER) == TDEFL_WRITE_ZLIB_HEADER) and  (comp.block_index == 0)) {
        comp.put_bits(0x78, 8);
        comp.put_bits(0x01, 8);
    }

    comp.put_bits(if (flush == TDEFL_FINISH) u16(1) else u16(0), 1);

    var saved_output_buf_pos = comp.output_buf_pos;
    var saved_bit_buf = comp.bit_buffer;
    var saved_bits_in = comp.bits_in;

    if (use_raw_block) {
        comp_block_succeeded = comp.compress_block(((comp.flags & TDEFL_FORCE_ALL_STATIC_BLOCKS) != 0) or (comp.total_lz_bytes < 48));
        //warn("use_raw={}, comp_block_succeeded={}\n", use_raw_block, comp_block_succeeded);
}
    // If the block gets expanded, forget the current contents of the output buffer and send a raw block instead.
    if (((use_raw_block)
         or ((comp.total_lz_bytes > 0)
             and ((comp.output_buf_pos - saved_output_buf_pos + 1) >= comp.total_lz_bytes)))
        and ((comp.lookahead_pos - comp.lz_code_buf_dict_pos) <= comp.dict_size)) {
        warn("********************* must put bits\n");
        // mz_uint i;
        comp.output_buf_pos = saved_output_buf_pos;
        comp.bit_buffer = saved_bit_buf;
        comp.bits_in = saved_bits_in;
        comp.put_bits(0, 2);
        // if (comp.bits_in)
        // {
        //     put_bits(0, 8 - comp.bits_in);
        // }
        // for (i = 2; i; --i, comp.total_lz_bytes ^= 0xFFFF)
        // {
        //     put_bits(comp.total_lz_bytes & 0xFFFF, 16);
        // }
        // for (i = 0; i < comp.total_lz_bytes; ++i)
        // {
        //     put_bits(comp.dict[(comp.lz_code_buf_dict_pos + i) & TDEFL_LZ_DICT_SIZE_MASK], 8);
        // }
        // Check for the extremely unlikely (if not impossible) case of the compressed block not fitting into the output buffer when using dynamic codes.
    } else if (!comp_block_succeeded) {
        //warn("NOT comp_block_succeeded={}, {}, {}, {}\n",
        //     comp_block_succeeded, saved_output_buf_pos, saved_bit_buf, saved_bits_in);
        comp.output_buf_pos = saved_output_buf_pos;
        comp.bit_buffer = saved_bit_buf;
        comp.bits_in = saved_bits_in;
        const cbs = comp.compress_block(true);
        //warn("cbs={}\n", cbs);
    }

    if (flush != 0) {
        //warn("flush != 0, {x}\n", flush);
        if (flush == TDEFL_FINISH) {
            //warn("flush finish\n");
            if (comp.bits_in != 0) {
                comp.put_bits(0, 8 - comp.bits_in);
            }
            if ((comp.flags & TDEFL_WRITE_ZLIB_HEADER) == TDEFL_WRITE_ZLIB_HEADER) {
                //warn("must write adler32\n");
                // mz_uint i, a = comp.adler32;
                // for (i = 0; i < 4; i++)
                // {
                //     put_bits((a >> 24) & 0xFF, 8);
                //     a <<= 8;
                // }
                var i:usize = 0;
                var a = comp.adler32;
                while (i < 4) : (i += 1) {
                    comp.put_bits((a >> 24) & 0xff, 8);
                    a <<= 8;
                }
            }
        } else {
            //warn("flush else\n");
            // mz_uint i, z = 0;
            comp.put_bits(0, 3);
            if (comp.bits_in != 0) {
                comp.put_bits(0, 8 - comp.bits_in);
            }
            var i: u16 = 2;
            var z: u16 = 0;
            while (i > 0) {
                comp.put_bits(z & 0xFFFF, 16);
                i -= 1;
                z ^= 0xffff;
            }
        }
    }

    assert(comp.output_buf_pos < comp.output_buf_end_pos);

    // memset(&comp.huff_count[0][0], 0, sizeof(comp.huff_count[0][0]) * TDEFL_MAX_HUFF_SYMBOLS_0);
    // memset(&comp.huff_count[1][0], 0, sizeof(comp.huff_count[1][0]) * TDEFL_MAX_HUFF_SYMBOLS_1);
    var hi: usize = 0;
    while (hi < TDEFL_MAX_HUFF_SYMBOLS_0) : (hi += 1) {
        comp.huff_count[0][hi] = 0;
    }
    hi = 0;
    while (hi < TDEFL_MAX_HUFF_SYMBOLS_1) : (hi += 1) {
        comp.huff_count[1][hi] = 0;
    }

    // comp.lz_code_buf_pos = comp.lz_code_buf + 1;
    // comp.lz_flags_pos = comp.lz_code_buf;
    comp.lz_code_buf_pos = 1;
    comp.lz_flags_pos = 0;
    comp.num_flags_left = 8;
    comp.lz_code_buf_dict_pos += comp.total_lz_bytes;
    comp.total_lz_bytes = 0;
    comp.block_index += 1;
    var n = comp.output_buf_pos - toutput_buf_start_pos;
    //warn("======== n={}, toutput_buf_start_pos={}\n", n, toutput_buf_start_pos);

    // if ((n = (int)(comp.output_buf_pos - toutput_buf_start_pos)) != 0)
    if (n != 0) {
        // if (comp.pPut_buf_func)
        // {
        //     *comp.pIn_buf_size = comp.src_pos - (const mz_uint8 *)comp.pIn_buf;
        //     if (!(*comp.pPut_buf_func)(comp.output_buf, n, comp.pPut_buf_user))
        //         return (comp.prev_return_status = TDEFL_STATUS_PUT_BUF_FAILED);
        // }
        // else
        if (toutput_buf_start_pos == 0) {
            //     int bytes_to_copy = (int)MZ_MIN((size_t)n, (size_t)(*comp.pOut_buf_size - comp.out_buf_ofs));
            const bytes_to_copy = MZ_MIN(usize, n, (comp.out_buf_size - comp.out_buf_ofs));
            //warn("bytes_to_copy={}\n", bytes_to_copy);
            //     memcpy((mz_uint8 *)comp.pOut_buf + comp.out_buf_ofs, comp.output_buf, bytes_to_copy);
            var i : @typeOf(bytes_to_copy) = 0;
            while (i < bytes_to_copy) : (i += 1) {
                comp.outbuf[comp.out_buf_ofs + i] = comp.output_buf[i];
            }
            comp.out_buf_ofs += bytes_to_copy;
            n -= @intCast(u32, bytes_to_copy);
            if (n != 0) {
                comp.output_flush_ofs = bytes_to_copy;
                comp.output_flush_remaining = n;
            }
        } else {
            comp.out_buf_ofs += n;
        }
    }

    return @bitCast(i32,@truncate(u32, comp.output_flush_remaining));
}

fn compress_normal(comp: *DeflateCompressor) bool {
    var src_pos = comp.src_pos;
    var src_buf_left = comp.src_buf_left;
    //tdefl_flush flush = comp.flush;
    var flush = comp.flush;
    //warn("!!! compress_normal {} {}\n", src_pos, src_buf_left);
    while ((src_buf_left > 0) or ((flush != 0) and (comp.lookahead_size > 0)))
    {
        var len_to_move: usize = 0;
        var cur_match_dist: usize = 0;
        var cur_match_len: usize = 0;
        var cur_pos: usize = 0;
        // Update dictionary and hash chains. Keeps the lookahead size equal to TDEFL_MAX_MATCH_LEN.
        if ((comp.lookahead_size + comp.dict_size) >= (TDEFL_MIN_MATCH_LEN - 1))
        {
            //warn("case 1, {}, {}\n", comp.lookahead_size + comp.dict_size, usize(TDEFL_MIN_MATCH_LEN) - 1);
            // mz_uint dst_pos = (comp.lookahead_pos + comp.lookahead_size) & TDEFL_LZ_DICT_SIZE_MASK, ins_pos = comp.lookahead_pos + comp.lookahead_size - 2;
            var dst_pos = (comp.lookahead_pos + comp.lookahead_size) & TDEFL_LZ_DICT_SIZE_MASK;
            var ins_pos = comp.lookahead_pos + comp.lookahead_size - 2;
            //warn("dst_pos={}, ins_pos={}\n", dst_pos, ins_pos);
            // mz_uint hash = (comp.dict[ins_pos & TDEFL_LZ_DICT_SIZE_MASK] << TDEFL_LZ_HASH_SHIFT) ^ comp.dict[(ins_pos + 1) & TDEFL_LZ_DICT_SIZE_MASK];
            var hash = (u16(comp.dict[ins_pos & TDEFL_LZ_DICT_SIZE_MASK]) << TDEFL_LZ_HASH_SHIFT) ^ comp.dict[(ins_pos + 1) & TDEFL_LZ_DICT_SIZE_MASK];
            // mz_uint nubytes_to_process = (mz_uint)MZ_MIN(src_buf_left, TDEFL_MAX_MATCH_LEN - comp.lookahead_size);
            const nubytes_to_process = MZ_MIN(usize, src_buf_left, TDEFL_MAX_MATCH_LEN - comp.lookahead_size);
            // const mz_uint8 *pSrc_end = src_pos + nubytes_to_process;
            const pSrc_end = src_pos + nubytes_to_process;
            src_buf_left -= nubytes_to_process;
            comp.lookahead_size += nubytes_to_process;
            while (src_pos != pSrc_end) {
                const c = comp.inbuf[src_pos];
                src_pos += 1;
                comp.dict[dst_pos] = c;
                if (dst_pos < (TDEFL_MAX_MATCH_LEN - 1)) {
                    comp.dict[TDEFL_LZ_DICT_SIZE + dst_pos] = c;
                }
                hash = ((hash << TDEFL_LZ_HASH_SHIFT) ^ c) & (TDEFL_LZ_HASH_SIZE - 1);
                comp.next[ins_pos & TDEFL_LZ_DICT_SIZE_MASK] = comp.hash[hash];
                comp.hash[hash] = @truncate(@typeOf(comp.hash[0]), ins_pos);
                dst_pos = (dst_pos + 1) & TDEFL_LZ_DICT_SIZE_MASK;
                ins_pos += 1;
            }
        }
        else
        {
            //warn("case 2: src_buf_left={}, lookahead_size={}\n",src_buf_left, comp.lookahead_size);
            while ((src_buf_left > 0) and (comp.lookahead_size < TDEFL_MAX_MATCH_LEN))
            {
                const c = comp.inbuf[src_pos];
                src_pos += 1;
                var dst_pos = (comp.lookahead_pos + comp.lookahead_size) & TDEFL_LZ_DICT_SIZE_MASK;
                src_buf_left -= 1;
                comp.dict[dst_pos] = c;
                if (dst_pos < (TDEFL_MAX_MATCH_LEN - 1)) {
                    comp.dict[TDEFL_LZ_DICT_SIZE + dst_pos] = c;
                }
                comp.lookahead_size += 1;
                if ((comp.lookahead_size + comp.dict_size) >= TDEFL_MIN_MATCH_LEN) {
                    const ins_pos = comp.lookahead_pos + (comp.lookahead_size - 1) - 2;
                    var hash = (u32(comp.dict[ins_pos & TDEFL_LZ_DICT_SIZE_MASK]) << (TDEFL_LZ_HASH_SHIFT * 2));
                    hash ^= (u32(comp.dict[(ins_pos + 1) & TDEFL_LZ_DICT_SIZE_MASK]) << TDEFL_LZ_HASH_SHIFT) ^ c;
                    hash &= (TDEFL_LZ_HASH_SIZE - 1);
                    comp.next[ins_pos & TDEFL_LZ_DICT_SIZE_MASK] = comp.hash[hash];
                    comp.hash[hash] = @truncate(@typeOf(comp.hash[0]), ins_pos);
                }
                //warn("src_buf_left={}, lookahead_size={}\n",src_buf_left, comp.lookahead_size);
            }
        }
        comp.dict_size = MZ_MIN(usize, TDEFL_LZ_DICT_SIZE - comp.lookahead_size, comp.dict_size);
        //warn("dict_size={}\n", comp.dict_size);
        if ((flush == 0) and (comp.lookahead_size < TDEFL_MAX_MATCH_LEN)) {
            //warn("break flush={}, lookahead_size={}\n", flush, comp.lookahead_size);
            break;
        }

        //* Simple lazy/greedy parsing state machine. */
        //warn("Simple lazy/greedy parsing state machine {}\n", comp.saved_match_len);
        len_to_move = 1;
        cur_match_dist = 0;
        if (comp.saved_match_len > 0) {
            cur_match_len = comp.saved_match_len;
        } else {
            cur_match_len = (TDEFL_MIN_MATCH_LEN - 1);
        }
        //cur_match_len = if (comp.saved_match_len > 0) comp.saved_match_len else (TDEFL_MIN_MATCH_LEN - 1);
        cur_pos = comp.lookahead_pos & TDEFL_LZ_DICT_SIZE_MASK;
        if ((comp.flags & (TDEFL_RLE_MATCHES | TDEFL_FORCE_ALL_RAW_BLOCKS)) > 0)
        {
            if ((comp.dict_size > 0) and ((comp.flags & TDEFL_FORCE_ALL_RAW_BLOCKS) == 0))
            {
                const c = comp.dict[(cur_pos - 1) & TDEFL_LZ_DICT_SIZE_MASK];
                cur_match_len = 0;
                while (cur_match_len < comp.lookahead_size) : (cur_match_len += 1) {
                    if (comp.dict[cur_pos + cur_match_len] != c) {
                        break;
                    }
                }
                if (cur_match_len < TDEFL_MIN_MATCH_LEN) {
                    cur_match_len = 0;
                } else {
                    cur_match_dist = 1;
                }
            }
        } else {
            find_match(comp, comp.lookahead_pos, comp.dict_size, comp.lookahead_size, &cur_match_dist, &cur_match_len);
        }
        if (((cur_match_len == TDEFL_MIN_MATCH_LEN) and (cur_match_dist >= 8 * 1024)) or (cur_pos == cur_match_dist)
            or (((comp.flags & TDEFL_FILTER_MATCHES) > 0) and (cur_match_len <= 5)))
        {
            cur_match_dist = 0;
            cur_match_len = 0;
        }
        if (comp.saved_match_len > 0) {
            if (cur_match_len > comp.saved_match_len) {
                comp.record_literal(@truncate(u8, comp.saved_lit));
                if (cur_match_len >= 128) {
                    comp.record_match(cur_match_len, cur_match_dist);
                    comp.saved_match_len = 0;
                    len_to_move = cur_match_len;
                } else {
                    comp.saved_lit = comp.dict[cur_pos];
                    comp.saved_match_dist = cur_match_dist;
                    comp.saved_match_len = cur_match_len;
                }
            } else {
                comp.record_match(comp.saved_match_len, comp.saved_match_dist);
                len_to_move = comp.saved_match_len - 1;
                comp.saved_match_len = 0;
            }
        } else if (cur_match_dist == 0) {
            comp.record_literal(comp.dict[MZ_MIN(@typeOf(cur_pos), cur_pos, @sizeOf(@typeOf(comp.dict)) - 1)]);
        } else if ((comp.greedy_parsing) or ((comp.flags & TDEFL_RLE_MATCHES) != 0) or (cur_match_len >= 128)) {
            comp.record_match(cur_match_len, cur_match_dist);
            len_to_move = cur_match_len;
        } else {
            comp.saved_lit = comp.dict[MZ_MIN(@typeOf(cur_pos), cur_pos, @sizeOf(@typeOf(comp.dict)) - 1)];
            comp.saved_match_dist = cur_match_dist;
            comp.saved_match_len = cur_match_len;
        }
        //* Move the lookahead forward by len_to_move bytes. */
        comp.lookahead_pos += len_to_move;
        assert(comp.lookahead_size >= len_to_move);
        comp.lookahead_size -= len_to_move;
        comp.dict_size = MZ_MIN(@typeOf(comp.dict_size), comp.dict_size + len_to_move, TDEFL_LZ_DICT_SIZE);
        //* Check if it's time to flush the current LZ codes to the internal output buffer. */
        if ((comp.lz_code_buf_pos > (TDEFL_LZ_CODE_BUF_SIZE - 8)) or
            ((comp.total_lz_bytes > 31 * 1024) and ((((u32(comp.lz_code_buf_pos) * 115) >> 7) >= comp.total_lz_bytes) or (comp.flags & TDEFL_FORCE_ALL_RAW_BLOCKS) != 0)))
        {
            comp.src_pos = src_pos;
            comp.src_buf_left = src_buf_left;
            const n = flush_block(comp, 0);
            //warn("flush_block returned {}\n", n);
            if (n != 0) {
                //return (n < 0) ? MZ_FALSE : MZ_TRUE;
                if (n < 0) {
                    return false;
                } else {
                    return true;
                }
            }
        }
    }

    comp.src_pos = src_pos;
    comp.src_buf_left = src_buf_left;

    return true;
}

fn flush_output_buffer(comp: *DeflateCompressor) bool {
    //warn("flush_output_buffer: {} {} {} {}\n", comp.src_pos, comp.out_buf_size,
    //     comp.out_buf_ofs, comp.output_flush_remaining);
    if (comp.in_buf_size > 0) {
        //*comp.pIn_buf_size = comp.src_pos - (const mz_uint8 *)comp.pIn_buf;
        comp.in_buf_size = comp.src_pos;
    }
    if (comp.out_buf_size > 0) {
        const n = MZ_MIN(usize, comp.out_buf_ofs, comp.output_flush_remaining);
        //warn("{} {} {}\n",  comp.out_buf_size, comp.out_buf_ofs,comp.output_flush_remaining );
        //memcpy((mz_uint8 *)comp.pOut_buf + comp.out_buf_ofs, comp.output_buf + comp.output_flush_ofs, n);
        //warn("memcpy {} {} {}\n", comp.out_buf_ofs, comp.output_flush_ofs, n);
        var i: usize = 0;
        while (i < n) {
            comp.outbuf[i + comp.out_buf_ofs] = comp.output_buf[i + comp.output_flush_ofs];
            i += 1;
        }
        comp.output_flush_ofs += n;
        comp.output_flush_remaining -= n;
        comp.out_buf_ofs += n;

        comp.out_buf_size = comp.out_buf_ofs;
    } else {
        //warn("no outbuf size\n");
    }

    return (comp.finished and (comp.output_flush_remaining == 0)); // ? TDEFL_STATUS_DONE : TDEFL_STATUS_OKAY;
    //return true;
}

fn compress(comp: *DeflateCompressor, pIn_buf: []u8, pIn_buf_size: *usize,
            pOut_buf: []u8, pOut_buf_size: *usize, flush: u32) bool {
    comp.inbuf = pIn_buf;
    comp.in_buf_size = pIn_buf_size.*;
    comp.outbuf = pOut_buf;
    comp.out_buf_size = pOut_buf_size.*;
    //comp.src_pos = (const mz_uint8 *)(pIn_buf);
    comp.src_pos = 0;
    //comp.src_buf_left = pIn_buf_size ? *pIn_buf_size : 0;
    comp.src_buf_left = pIn_buf.len;
    comp.out_buf_ofs = 0;
    comp.flush = flush;

    // Haven't done anything yet
    pOut_buf_size.* = 0;
    pIn_buf_size.* = 0;

    // if (((comp.pPut_buf_func != NULL) == ((pOut_buf != NULL) || (pOut_buf_size != NULL))) || (comp.prev_return_status != TDEFL_STATUS_OKAY) ||
    //     (comp.wants_to_finish && (flush != TDEFL_FINISH)) || (pIn_buf_size && *pIn_buf_size && !pIn_buf) || (pOut_buf_size && *pOut_buf_size && !pOut_buf))
    // {
    //     if (pIn_buf_size) {
    //         *pIn_buf_size = 0;
    //     }
    //     if (pOut_buf_size) {
    //         *pOut_buf_size = 0;
    //     }
    //     //return (comp.prev_return_status = TDEFL_STATUS_BAD_PARAM);
    //     return false;
    // }
    //comp.wants_to_finish |= (flush == TDEFL_FINISH);
    comp.wants_to_finish |= @boolToInt(flush == TDEFL_FINISH);

    if ((comp.output_flush_remaining != 0) or (comp.finished)) {
        //return (comp.prev_return_status = flush_output_buffer(comp));
        return flush_output_buffer(comp);
    }

    // #if MINIZ_USE_UNALIGNED_LOADS_AND_STORES && MINIZ_LITTLE_ENDIAN
    //     if (((comp.flags & TDEFL_MAX_PROBES_MASK) == 1) &&
    //         ((comp.flags & TDEFL_GREEDY_PARSING_FLAG) != 0) &&
    //         ((comp.flags & (TDEFL_FILTER_MATCHES | TDEFL_FORCE_ALL_RAW_BLOCKS | TDEFL_RLE_MATCHES)) == 0))
    //     {
    //         if (!tdefl_compress_fast(d))
    //             return comp.prev_return_status;
    //     }
    //     else
    // #endif /* #if MINIZ_USE_UNALIGNED_LOADS_AND_STORES && MINIZ_LITTLE_ENDIAN */
    {
        const res = compress_normal(comp);
        //DEBUG: warn("compress_normal() returned {}\n", res);
        if (!res) {
            return comp.prev_return_status;
        }
    }

    if (((comp.flags & (TDEFL_WRITE_ZLIB_HEADER | TDEFL_COMPUTE_ADLER32)) != 0) and (pIn_buf.len > 0)) {
       comp.adler32 = adler32(comp.adler32, pIn_buf[0..]);
    }

    if ((flush != 0)
        and (comp.lookahead_size == 0)
        and (comp.src_buf_left == 0) and (comp.output_flush_remaining == 0)) {
        //DEBUG: warn("Time to flush\n");
        if (flush_block(comp, flush) < 0) {
            return comp.prev_return_status;
        }
        comp.finished = (flush == TDEFL_FINISH);
        if (flush == TDEFL_FULL_FLUSH)  {
            //MZ_CLEAR_OBJ(comp.hash);
            for (comp.hash) |*v| {
                v.* = 0;
            }
            //MZ_CLEAR_OBJ(comp.next);
            for (comp.next) |*v| {
                v.* = 0;
            }
            comp.dict_size = 0;
        }
    }
    pOut_buf_size.* = comp.out_buf_ofs;
    pIn_buf_size.* = comp.in_buf_size;
    comp.prev_return_status = flush_output_buffer(comp);
    //DEBUG: warn("done...\n");
    return comp.prev_return_status;
}

test "radix sort" {
    var symin: [258]tdefl_syfreq = undefined;
    var symout: [258]tdefl_syfreq = undefined;
    // probably not sensible input but we shall not crash...
    const r = tdefl_radix_sort_syms(256, symin[0..], symout[0..]);
    //warn("r.len={}\n", r.len);
    //for (r) |it, i| {
    //    warn("[{}] key={}, symindex={}\n", i, it.key, it.syindex);
    //}
}

test "compress" {
    warn("\nTesting deflate, zig 0.2.0+5f38d6e\n");
    var compressor: DeflateCompressor = undefined;
    tdefl_init(&compressor, TDEFL_WRITE_ZLIB_HEADER | 768);
    warn("sizeof compressor={}\n", usize(@sizeOf(@typeOf(compressor))));
    //var input = "The quick brown fox jumps over the lazy dog";
    var input = "Blah blah blah blah blah!";
    var expected = "\x78\x01\x73\xca\x49\xcc\x50\x48\xc2\x24\x14\x01\x6f\x19\x08\x75";
    //var input = []u8 {'a'} ** 100;
    //var input = []u8 {0} ** 100; // 789c6360a03d000000640001
    //var expected = "x\x9cKL\xa4=\x00\x00zG%\xe5";
    var inputlen = input.len;
    var output = []u8 {0} ** 1024;
    var outputlen = output.len;
    const result = compress(&compressor, input[0..], &inputlen, output[0..], &outputlen, TDEFL_FINISH);
    warn("result={}, inputlen={}, outputlen={}\n", result, inputlen, outputlen);
    //warn("3 expected {}, {}, {}\n", expected, compressor.src_pos, compressor.src_buf_left);
    //warn("4 {}, output_buf={}\n", compressor.outbuf[0..16], compressor.output_buf);
    // ===
    // In [100]: zlib.decompress('\x78\x01\x73\xca\x49\xcc\x50\x48\xc2\x24\x14\x01\x6f\x19\x08\x75')
    // Out[100]: 'Blah blah blah blah blah!'
    // ===
    assert(outputlen <= output.len);
    assert(mem.eql(u8, output[0..expected.len], expected[0..expected.len]));
    if (outputlen < 64) {
        for (output[0..outputlen]) |v, i| {
            warn("[{}] = {x2}, {x2}\n", i, v, output[i]);
        }
    }
}
