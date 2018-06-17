// -*- mode:zig; indent-tabs-mode:nil;  -*-

const warn = @import("std").debug.warn;
const assert = @import("std").debug.assert;

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

const s_tdefl_len_extra = [256]u5 {
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

const s_tdefl_small_dist_sym = [512]u8 {
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

const s_tdefl_small_dist_extra = [512]u5 {
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

const s_tdefl_large_dist_sym = [128]u8 {
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
const TDEFL_LZ_DICT_SIZE = 32768;
const TDEFL_LZ_DICT_SIZE_MASK = TDEFL_LZ_DICT_SIZE - 1;
const TDEFL_MIN_MATCH_LEN = 3;
const TDEFL_MAX_MATCH_LEN = 258;

const TDEFL_NO_FLUSH = 0;
const TDEFL_SYNC_FLUSH = 2;
const TDEFL_FULL_FLUSH = 3;
const TDEFL_FINISH = 4;

const MZ_Flags = u32;

// is this the way to do ifdef style things?!?
const small = false;

const TDEFL_LZ_CODE_BUF_SIZE = comptime blk: {
    var val = 0;
    if (small) {val = 24 * 1024;} else {val = 64 * 1024; }
    break :blk val;
};

const TDEFL_LZ_HASH_BITS = comptime blk: {
    var val = 0;
    if (small) { val = 12; } else { val = 15; }
    break :blk val;
};

const TDEFL_OUT_BUF_SIZE = (TDEFL_LZ_CODE_BUF_SIZE * 13) / 10;
const TDEFL_MAX_HUFF_SYMBOLS = 288;
const TDEFL_LEVEL1_HASH_SIZE_MASK = 4095;
const TDEFL_LZ_HASH_SHIFT = (TDEFL_LZ_HASH_BITS + 2) / 3;
const TDEFL_LZ_HASH_SIZE = 1 << TDEFL_LZ_HASH_BITS;

inline fn MZ_MIN(comptime T: type, a: T, b: T) T {
    if (T == bool) {
        return a or b;
    } else if (a < b) {
        return a;
    } else {
        return b;
    }
}

const DeflateCompressor = struct {
    //tdefl_put_buf_func_ptr pPut_buf_func;
    //void *pPut_buf_user;
    flags: MZ_Flags,
    max_probes: [2]u32,
    greedy_parsing: bool,
    adler32: u32,
    lookahead_pos: usize,
    lookahead_size: usize,
    dict_size: usize,
    //mz_uint8 *pLZ_code_buf, *pLZ_flags, *pOutput_buf, *pOutput_buf_end;
    pLZ_code_buf: u32,
    pLZ_flags: u32,
    pOutput_buf: u32,
    pOutput_buf_end: u32,
    nuflags_left: u32,
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
    //const mz_uint8 *pSrc;
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

    fn put_bits(comp: *DeflateCompressor, bits: u16, len: u5) void {
        //MZ_ASSERT(bits <= ((1U << len) - 1U));
        warn("putting bits={x}, len={}, bits_in={}\n", bits, len, comp.bits_in);
        comp.bit_buffer |= (u32(bits) << u5(comp.bits_in));
        comp.bits_in += len;
        while (comp.bits_in >= 8) {
            warn(".");
            if (comp.pOutput_buf < comp.pOutput_buf_end) {
                comp.output_buf[comp.pOutput_buf] = @truncate(u8, comp.bit_buffer);
            }
            comp.pOutput_buf += 1;
            comp.bit_buffer >>= 8;
            comp.bits_in -= 8;
        }
    }
};

fn tdefl_init(comp: *DeflateCompressor, flags: MZ_Flags) void {
    //comp.pPut_buf_func = pPut_buf_func;
    //comp.pPut_buf_user = pPut_buf_user;
    comp.flags = MZ_Flags(flags);
    comp.max_probes[0] = 1 + ((flags & 0xFFF) + 2) / 3;
    comp.greedy_parsing = (flags & TDEFL_GREEDY_PARSING_FLAG) != 0;
    comp.max_probes[1] = 1 + (((flags & 0xFFF) >> 2) + 2) / 3;
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
    //comp.pLZ_code_buf = comp.lz_code_buf + 1;
    comp.pLZ_code_buf = 1;
    //comp.pLZ_flags = comp.lz_code_buf;
    comp.pLZ_flags = 0;
    comp.nuflags_left = 8;
    // position into output_buf
    comp.pOutput_buf = 0;
    comp.pOutput_buf_end = 0;
    //comp.prev_return_status = TDEFL_STATUS_OKAY;
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
    if ((flags & TDEFL_NONDETERMINISTIC_PARSING_FLAG) != 0) {
        //MZ_CLEAR_OBJ(comp.dict);
        for (comp.dict) |*v|{
            v.* = 0;
        }
    }
    //memset(&comp.huff_count[0][0], 0, sizeof(comp.huff_count[0][0]) * TDEFL_MAX_HUFF_SYMBOLS_0);
    //memset(&comp.huff_count[1][0], 0, sizeof(comp.huff_count[1][0]) * TDEFL_MAX_HUFF_SYMBOLS_1);
    for (comp.huff_count) |*l1|{
        for (l1.*) |*l2| {
            l2.* = 0;
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
    //         tdefl_syfreq *t = pCur_syms;
    //         pCur_syms = pNew_syms;
    //         pNew_syms = t;

                                // swap
        var t = pCur_syms;
        pCur_syms = pNew_syms;
        pNew_syms = t;

        pass_shift += 8;
        pass += 1;
    }
    return pCur_syms;
}

// inline
fn record_literal(comp: *DeflateCompressor, lit: u8) void {
    warn("record_literal\n");
    comp.total_lz_bytes += 1;
    //*comp.pLZ_code_buf++ = lit;
    //*comp.pLZ_flags = (mz_uint8)(*comp.pLZ_flags >> 1);
    comp.nuflags_left -= 1;
    if (comp.nuflags_left == 0)
    {
        comp.nuflags_left = 8;
        comp.pLZ_code_buf += 1;
        comp.pLZ_flags = comp.pLZ_code_buf;
    }
    comp.huff_count[0][lit] += 1;
}

// inline
fn record_match(comp: *DeflateCompressor, match_len: usize, pmatch_dist: usize) void {
    warn("record_match\n");
    var s0: u32 = 0;
    var s1: u32 = 0;
    var match_dist = pmatch_dist;

    assert((match_len >= TDEFL_MIN_MATCH_LEN) and (match_dist >= 1) and (match_dist <= TDEFL_LZ_DICT_SIZE));

    comp.total_lz_bytes += match_len;

    //comp.pLZ_code_buf[0] = u8(match_len - TDEFL_MIN_MATCH_LEN);
    comp.lz_code_buf[comp.pLZ_code_buf] = @truncate(u8, match_len - TDEFL_MIN_MATCH_LEN);

    match_dist -= 1;
    //comp.pLZ_code_buf[1] = u8(match_dist & 0xFF);
    //comp.pLZ_code_buf[2] = u8(match_dist >> 8);
    comp.lz_code_buf[comp.pLZ_code_buf + 1] = @truncate(u8, match_dist);
    comp.lz_code_buf[comp.pLZ_code_buf + 2] = @truncate(u8,match_dist >> 8);
    comp.pLZ_code_buf += 3;

    //*comp.pLZ_flags = u8((*comp.pLZ_flags >> 1) | 0x80);
    comp.lz_code_buf[comp.pLZ_flags] = (comp.lz_code_buf[comp.pLZ_flags] >> 1) | 0x80;
    comp.nuflags_left -= 1;
    if (comp.nuflags_left == 0) {
        comp.nuflags_left = 8;
        comp.pLZ_code_buf += 1;
        comp.pLZ_flags = comp.pLZ_code_buf;
    }

    s0 = s_tdefl_small_dist_sym[match_dist & 511];
    s1 = s_tdefl_large_dist_sym[(match_dist >> 8) & 127];
    //comp.huff_count[1][(match_dist < 512) ? s0 : s1]++;
    var dist: u32 = s0;
    if (match_dist >= 512) {
        dist = s1;
    }
    comp.huff_count[1][dist] += 1;

    if (match_len >= TDEFL_MIN_MATCH_LEN) {
        comp.huff_count[0][s_tdefl_len_sym[match_len - TDEFL_MIN_MATCH_LEN]] += 1;
    }
}

fn find_match(comp: *DeflateCompressor, lookahead_pos: usize,
              max_dist: usize, max_match_len: usize,
              pmatch_dist: *usize, pmatch_len: *usize) void {
    //     mz_uint dist, pos = lookahead_pos & TDEFL_LZ_DICT_SIZE_MASK, match_len = *pmatch_len, probe_pos = pos, next_probe_pos, probe_len;
    warn("find_match\n");
    var dist: u16 = 0;
    var next_probe_pos: u16 = 0;
    var pos = lookahead_pos & TDEFL_LZ_DICT_SIZE_MASK;
    var match_len = pmatch_len.*;
    var probe_pos = pos;
    var nuprobes_left = if (match_len >= 32) comp.max_probes[1] else comp.max_probes[1];
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
        warn("nuprobes_left = {}\n", nuprobes_left);
        while (true) {
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
        while (probe_len < max_match_len) {
            if (comp.dict[p] != comp.dict[q]) {
                break;
            }
            p += 1;
            q += 1;
            probe_len += 1;
        }
        if (probe_len > match_len) {
            pmatch_dist.* = dist;
            pmatch_len.* = probe_len;
            match_len = probe_len;
            // if ((*pmatch_len = match_len = probe_len) == max_match_len)
            //     return;
            if (probe_len == match_len) {
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
    warn("optimize_huffman_table\n");
    // int i, j, l, num_codes[1 + TDEFL_MAX_SUPPORTED_HUFF_CODESIZE];
    // mz_uint next_code[TDEFL_MAX_SUPPORTED_HUFF_CODESIZE + 1];
    // MZ_CLEAR_OBJ(num_codes);
    // if (static_table)
    // {
    //     for (i = 0; i < table_len; i++)
    //         num_codes[d->m_huff_code_sizes[table_num][i]]++;
    // }
    // else
    // {
    //     tdefl_sym_freq syms0[TDEFL_MAX_HUFF_SYMBOLS], syms1[TDEFL_MAX_HUFF_SYMBOLS], *pSyms;
    //     int num_used_syms = 0;
    //     const mz_uint16 *pSym_count = &d->m_huff_count[table_num][0];
    //     for (i = 0; i < table_len; i++)
    //         if (pSym_count[i])
    //         {
    //             syms0[num_used_syms].m_key = (mz_uint16)pSym_count[i];
    //             syms0[num_used_syms++].m_sym_index = (mz_uint16)i;
    //         }

    //     pSyms = tdefl_radix_sort_syms(num_used_syms, syms0, syms1);
    //     tdefl_calculate_minimum_redundancy(pSyms, num_used_syms);

    //     for (i = 0; i < num_used_syms; i++)
    //         num_codes[pSyms[i].m_key]++;

    //     tdefl_huffman_enforce_max_code_size(num_codes, num_used_syms, code_size_limit);

    //     MZ_CLEAR_OBJ(d->m_huff_code_sizes[table_num]);
    //     MZ_CLEAR_OBJ(d->m_huff_codes[table_num]);
    //     for (i = 1, j = num_used_syms; i <= code_size_limit; i++)
    //         for (l = num_codes[i]; l > 0; l--)
    //             d->m_huff_code_sizes[table_num][pSyms[--j].m_sym_index] = (mz_uint8)(i);
    // }

    // next_code[1] = 0;
    // for (j = 0, i = 2; i <= code_size_limit; i++)
    //     next_code[i] = j = ((j + num_codes[i - 1]) << 1);

    // for (i = 0; i < table_len; i++)
    // {
    //     mz_uint rev_code = 0, code, code_size;
    //     if ((code_size = d->m_huff_code_sizes[table_num][i]) == 0)
    //         continue;
    //     code = next_code[code_size]++;
    //     for (l = code_size; l > 0; l--, code >>= 1)
    //         rev_code = (rev_code << 1) | (code & 1);
    //     d->m_huff_codes[table_num][i] = (mz_uint16)rev_code;
    // }
}

fn start_dynamic_block(comp: *DeflateCompressor) void {
    warn("start_dynamic_block\n");
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

fn start_static_block(comp: *DeflateCompressor) void {
    warn("start_static_block\n");
   // mz_uint8 *p = &d->huff_code_sizes[0][0];

    var i: usize = 0;
    var p: usize = 0;
    while (i <= 143) {
        //*p++ = 8;
        comp.huff_code_sizes[0][i] = 8;
        i += 1;
    }
    while (i <= 255) {
        //*p++ = 9;
        comp.huff_code_sizes[0][i] = 9;
        i += 1;
    }
    while (i <= 279) {
        //*p++ = 7;
        comp.huff_code_sizes[0][i] = 7;
        i += 1;
    }
    while (i <= 287) {
        //*p++ = 8;
        comp.huff_code_sizes[0][i] = 8;
        i += 1;
    }

    //memset(d->huff_code_sizes[1], 5, 32);

    optimize_huffman_table(comp, 0, 288, 15, true);
    optimize_huffman_table(comp, 1, 32, 15, true);

    comp.put_bits(1, 2);
}

fn compress_lz_codes(comp: *DeflateCompressor) bool {
    warn("compress_lz_codes\n");
    var flags: u32 = 1;
    var pLZ_codes: usize = 0;
    while (pLZ_codes < comp.pLZ_code_buf) {
        if (flags == 1) {
            flags = @truncate(u32, pLZ_codes) | 0x100;
            pLZ_codes += 1;
        }
        if ((flags & 1) == 1) {
            var sym: u8 = 0;
            var num_extra_bits: u5 = 0;
            var match_len = comp.lz_code_buf[pLZ_codes];
            var match_dist = (comp.lz_code_buf[pLZ_codes + 1] | (u16(comp.lz_code_buf[pLZ_codes + 2]) << 8));
            pLZ_codes += 3;

            //MZ_ASSERT(comp.huff_code_sizes[0][s_tdefl_len_sym[match_len]]);
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
            const lit = comp.lz_code_buf[pLZ_codes];
            pLZ_codes += 1;
            assert(comp.huff_code_sizes[0][lit] != 0);
            comp.put_bits(comp.huff_codes[0][lit], comp.huff_code_sizes[0][lit]);
        }
        flags >>= 1;
    }

    comp.put_bits(comp.huff_codes[0][256], comp.huff_code_sizes[0][256]);

    return (comp.pOutput_buf < comp.pOutput_buf_end);
}

fn compress_block(comp: *DeflateCompressor, static_block: bool) bool {
    warn("compress_block\n");
    if (static_block) {
        start_static_block(comp);
    } else {
        start_dynamic_block(comp);
    }
    return compress_lz_codes(comp);
}

fn flush_block(comp: *DeflateCompressor, flush: u32) i32 {
    warn("flush_block {x8}\n", flush);
    // mz_uint saved_bit_buf, saved_bits_in;
    // mz_uint8 *pSaved_output_buf;
    // mz_bool comp_block_succeeded = MZ_FALSE;
    var comp_block_succeeded = false;
    // int n, use_raw_block = ((comp.flags & TDEFL_FORCE_ALL_RAW_BLOCKS) != 0) && (comp.lookahead_pos - comp.lz_code_buf_dict_pos) <= comp.dict_size;
    var use_raw_block = ((comp.flags & TDEFL_FORCE_ALL_RAW_BLOCKS) != 0);
    // mz_uint8 *pOutput_buf_start = ((comp.pPut_buf_func == NULL) && ((*comp.pOut_buf_size - comp.out_buf_ofs) >= TDEFL_OUT_BUF_SIZE)) ? ((mz_uint8 *)comp.pOut_buf + comp.out_buf_ofs) : comp.output_buf;

    // comp.pOutput_buf = pOutput_buf_start;
    // comp.pOutput_buf_end = comp.pOutput_buf + TDEFL_OUT_BUF_SIZE - 16;

    // MZ_ASSERT(!comp.output_flush_remaining);
    comp.output_flush_ofs = 0;
    comp.output_flush_remaining = 0;

    // *comp.pLZ_flags = (mz_uint8)(*comp.pLZ_flags >> comp.nuflags_left);
    if (comp.nuflags_left == 8) {
        comp.pLZ_code_buf -= 1;
    }

    if (((comp.flags & TDEFL_WRITE_ZLIB_HEADER) != TDEFL_WRITE_ZLIB_HEADER) and  (comp.block_index == 0)) {
        comp.put_bits(0x78, 8);
        comp.put_bits(0x01, 8);
    }

    if (flush == TDEFL_FINISH) {
        comp.put_bits(1, 1);
    } else {
        comp.put_bits(0, 1);
    }

    var pSaved_output_buf = comp.pOutput_buf;
    var saved_bit_buf = comp.bit_buffer;
    var saved_bits_in = comp.bits_in;

    if (use_raw_block) {
        comp_block_succeeded = compress_block(comp, ((comp.flags & TDEFL_FORCE_ALL_STATIC_BLOCKS) != 0) or (comp.total_lz_bytes < 48));
        warn("use_raw={}, comp_block_succeeded={}\n", use_raw_block, comp_block_succeeded);
}
    // If the block gets expanded, forget the current contents of the output buffer and send a raw block instead.
    if (((use_raw_block) or ((comp.total_lz_bytes > 0)
                             and ((comp.pOutput_buf - pSaved_output_buf + 1) >= comp.total_lz_bytes)))
        and ((comp.lookahead_pos - comp.lz_code_buf_dict_pos) <= comp.dict_size))
    {
        warn("must put bits\n");
    //     mz_uint i;
    //     comp.pOutput_buf = pSaved_output_buf;
    //     comp.bit_buffer = saved_bit_buf, comp.bits_in = saved_bits_in;
    //     put_bits(0, 2);
    //     if (comp.bits_in)
    //     {
    //         put_bits(0, 8 - comp.bits_in);
    //     }
    //     for (i = 2; i; --i, comp.total_lz_bytes ^= 0xFFFF)
    //     {
    //         put_bits(comp.total_lz_bytes & 0xFFFF, 16);
    //     }
    //     for (i = 0; i < comp.total_lz_bytes; ++i)
    //     {
    //         put_bits(comp.dict[(comp.lz_code_buf_dict_pos + i) & TDEFL_LZ_DICT_SIZE_MASK], 8);
    //     }
    // }
    // Check for the extremely unlikely (if not impossible) case of the compressed block not fitting into the output buffer when using dynamic codes.
    } else if (!comp_block_succeeded) {
        warn("comp_block_succeeded={}\n", comp_block_succeeded);
        //     comp.pOutput_buf = pSaved_output_buf;
        //     comp.bit_buffer = saved_bit_buf, comp.bits_in = saved_bits_in;
        _ = compress_block(comp, true);
    }

    if (flush != 0) {
        warn("flush != 0, {x}\n", flush);
        if (flush == TDEFL_FINISH) {
            if (comp.bits_in != 0) {
                comp.put_bits(0, 8 - comp.bits_in);
            }
            if ((comp.flags & TDEFL_WRITE_ZLIB_HEADER) == TDEFL_WRITE_ZLIB_HEADER) {
                //             mz_uint i, a = comp.adler32;
                //             for (i = 0; i < 4; i++)
                //             {
                //                 put_bits((a >> 24) & 0xFF, 8);
                //                 a <<= 8;
                //             }
            }
        } else {
            warn("flush else\n");
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

    //assert(comp.pOutput_buf < comp.pOutput_buf_end);

    // memset(&comp.huff_count[0][0], 0, sizeof(comp.huff_count[0][0]) * TDEFL_MAX_HUFF_SYMBOLS_0);
    // memset(&comp.huff_count[1][0], 0, sizeof(comp.huff_count[1][0]) * TDEFL_MAX_HUFF_SYMBOLS_1);

    // comp.pLZ_code_buf = comp.lz_code_buf + 1;
    // comp.pLZ_flags = comp.lz_code_buf;
    comp.pLZ_code_buf = 1;
    comp.pLZ_flags = 0;
    comp.nuflags_left = 8;
    comp.lz_code_buf_dict_pos += comp.total_lz_bytes;
    comp.total_lz_bytes = 0;
    comp.block_index += 1;

    // if ((n = (int)(comp.pOutput_buf - pOutput_buf_start)) != 0)
    // {
    //     if (comp.pPut_buf_func)
    //     {
    //         *comp.pIn_buf_size = comp.pSrc - (const mz_uint8 *)comp.pIn_buf;
    //         if (!(*comp.pPut_buf_func)(comp.output_buf, n, comp.pPut_buf_user))
    //             return (comp.prev_return_status = TDEFL_STATUS_PUT_BUF_FAILED);
    //     }
    //     else if (pOutput_buf_start == comp.output_buf)
    //     {
    //         int bytes_to_copy = (int)MZ_MIN((size_t)n, (size_t)(*comp.pOut_buf_size - comp.out_buf_ofs));
    //         memcpy((mz_uint8 *)comp.pOut_buf + comp.out_buf_ofs, comp.output_buf, bytes_to_copy);
    //         comp.out_buf_ofs += bytes_to_copy;
    //         if ((n -= bytes_to_copy) != 0)
    //         {
    //             comp.output_flush_ofs = bytes_to_copy;
    //             comp.output_flush_remaining = n;
    //         }
    //     }
    //     else
    //     {
    //         comp.out_buf_ofs += n;
    //     }
    // }

    return @bitCast(i32,@truncate(u32, comp.output_flush_remaining));
}

fn compress_normal(comp: *DeflateCompressor) bool {
    var pSrc = comp.src_pos;
    var src_buf_left = comp.src_buf_left;
    //tdefl_flush flush = comp.flush;
    var flush: u32 = comp.flush;

    while ((src_buf_left > 0) or ((flush != 0) and (comp.lookahead_size > 0)))
    {
        var len_to_move: usize = 0;
        var cur_match_dist: usize = 0;
        var cur_match_len: usize = 0;
        var cur_pos: usize = 0;
        // Update dictionary and hash chains. Keeps the lookahead size equal to TDEFL_MAX_MATCH_LEN.
        if ((comp.lookahead_size + comp.dict_size) >= (TDEFL_MIN_MATCH_LEN - 1))
        {
            warn("case 1\n");
            // mz_uint dst_pos = (comp.lookahead_pos + comp.lookahead_size) & TDEFL_LZ_DICT_SIZE_MASK, ins_pos = comp.lookahead_pos + comp.lookahead_size - 2;
            var dst_pos = (comp.lookahead_pos + comp.lookahead_size) & TDEFL_LZ_DICT_SIZE_MASK;
            var ins_pos = comp.lookahead_pos + comp.lookahead_size - 2;
            // mz_uint hash = (comp.dict[ins_pos & TDEFL_LZ_DICT_SIZE_MASK] << TDEFL_LZ_HASH_SHIFT) ^ comp.dict[(ins_pos + 1) & TDEFL_LZ_DICT_SIZE_MASK];
            var hash = (u16(comp.dict[ins_pos & TDEFL_LZ_DICT_SIZE_MASK]) << TDEFL_LZ_HASH_SHIFT) ^ comp.dict[(ins_pos + 1) & TDEFL_LZ_DICT_SIZE_MASK];
            // mz_uint nubytes_to_process = (mz_uint)MZ_MIN(src_buf_left, TDEFL_MAX_MATCH_LEN - comp.lookahead_size);
            const nubytes_to_process = MZ_MIN(usize, src_buf_left, TDEFL_MAX_MATCH_LEN - comp.lookahead_size);
            // const mz_uint8 *pSrc_end = pSrc + nubytes_to_process;
            const pSrc_end = pSrc + nubytes_to_process;
            src_buf_left -= nubytes_to_process;
            comp.lookahead_size += nubytes_to_process;
            while (pSrc != pSrc_end) {
                const c = comp.inbuf[pSrc];
                pSrc += 1;
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
            warn("case 2: src_buf_left={}, lookahead_size={}\n",src_buf_left, comp.lookahead_size);
            while ((src_buf_left > 0) and (comp.lookahead_size < TDEFL_MAX_MATCH_LEN))
            {
                const c = comp.inbuf[pSrc];
                pSrc += 1;
                var dst_pos = (comp.lookahead_pos + comp.lookahead_size) & TDEFL_LZ_DICT_SIZE_MASK;
                src_buf_left -= 1;
                comp.dict[dst_pos] = c;
                if (dst_pos < (TDEFL_MAX_MATCH_LEN - 1)) {
                    comp.dict[TDEFL_LZ_DICT_SIZE + dst_pos] = c;
                }
                comp.lookahead_size += 1;
                if ((comp.lookahead_size + comp.dict_size) >= TDEFL_MIN_MATCH_LEN) {
                    const ins_pos = comp.lookahead_pos + (comp.lookahead_size - 1) - 2;
                    var hash = (u16(comp.dict[ins_pos & TDEFL_LZ_DICT_SIZE_MASK]) << (TDEFL_LZ_HASH_SHIFT * 2));
                    hash ^= (u16(comp.dict[(ins_pos + 1) & TDEFL_LZ_DICT_SIZE_MASK]) << TDEFL_LZ_HASH_SHIFT) ^ c;
                    hash &= (TDEFL_LZ_HASH_SIZE - 1);
                    comp.next[ins_pos & TDEFL_LZ_DICT_SIZE_MASK] = comp.hash[hash];
                    comp.hash[hash] = @truncate(@typeOf(comp.hash[0]), ins_pos);
                }
                warn("src_buf_left={}, lookahead_size={}\n",src_buf_left, comp.lookahead_size);
            }
        }
        comp.dict_size = MZ_MIN(usize, TDEFL_LZ_DICT_SIZE - comp.lookahead_size, comp.dict_size);
        if ((flush == 0) and (comp.lookahead_size < TDEFL_MAX_MATCH_LEN)) {
            warn("break flush={}, lookahead_size={}\n", flush, comp.lookahead_size);
            break;
        }

        //* Simple lazy/greedy parsing state machine. */
        len_to_move = 1;
        cur_match_dist = 0;
        if (comp.saved_match_len > 0) {
            cur_match_len = comp.saved_match_len;
        } else {
            cur_match_len = (TDEFL_MIN_MATCH_LEN - 1);
        }

        cur_pos = comp.lookahead_pos & TDEFL_LZ_DICT_SIZE_MASK;
        if ((comp.flags & (TDEFL_RLE_MATCHES | TDEFL_FORCE_ALL_RAW_BLOCKS)) > 0)
        {
            if ((comp.dict_size > 0) and ((comp.flags & TDEFL_FORCE_ALL_RAW_BLOCKS) == 0))
            {
                const c = comp.dict[(cur_pos - 1) & TDEFL_LZ_DICT_SIZE_MASK];
                cur_match_len = 0;
                while (cur_match_len < comp.lookahead_size)
                {
                    if (comp.dict[cur_pos + cur_match_len] != c) {
                        break;
                    }
                    cur_match_len += 1;
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
                record_literal(comp, @truncate(u8, comp.saved_lit));
                if (cur_match_len >= 128) {
                    record_match(comp, cur_match_len, cur_match_dist);
                    comp.saved_match_len = 0;
                    len_to_move = cur_match_len;
                } else {
                    comp.saved_lit = comp.dict[cur_pos];
                    comp.saved_match_dist = cur_match_dist;
                    comp.saved_match_len = cur_match_len;
                }
            } else {
                record_match(comp, comp.saved_match_len, comp.saved_match_dist);
                len_to_move = comp.saved_match_len - 1;
                comp.saved_match_len = 0;
            }
        } else if (cur_match_dist == 0) {
            record_literal(comp, comp.dict[MZ_MIN(@typeOf(cur_pos), cur_pos, @sizeOf(@typeOf(comp.dict)) - 1)]);
        } else if ((comp.greedy_parsing) or ((comp.flags & TDEFL_RLE_MATCHES) != 0) or (cur_match_len >= 128)) {
            record_match(comp, cur_match_len, cur_match_dist);
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
        if ((comp.pLZ_code_buf > (TDEFL_LZ_CODE_BUF_SIZE - 8)) or
            ((comp.total_lz_bytes > 31 * 1024) and ((((u32(comp.pLZ_code_buf) * 115) >> 7) >= comp.total_lz_bytes) or (comp.flags & TDEFL_FORCE_ALL_RAW_BLOCKS) != 0)))
        {
            comp.src_pos = pSrc;
            comp.src_buf_left = src_buf_left;
            const n = flush_block(comp, 0);
            warn("flush_block returned {}\n", n);
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

    comp.src_pos = pSrc;
    comp.src_buf_left = src_buf_left;

    return true;
}

fn flush_output_buffer(comp: *DeflateCompressor) bool {
    warn("flush_output_buffer\n");
    if (comp.in_buf_size > 0) {
        //*comp.pIn_buf_size = comp.src_pos - (const mz_uint8 *)comp.pIn_buf;
        comp.in_buf_size = comp.src_pos;
    }
    warn("{} {} {} {}\n", comp.src_pos, comp.out_buf_size, comp.out_buf_ofs, comp.output_flush_remaining);
    if (comp.out_buf_size > 0) {
        const n = MZ_MIN(usize, comp.out_buf_size - comp.out_buf_ofs, comp.output_flush_remaining);
        warn("{} {} {}\n",  comp.out_buf_size, comp.out_buf_ofs,comp.output_flush_remaining );
        //memcpy((mz_uint8 *)comp.pOut_buf + comp.out_buf_ofs, comp.output_buf + comp.output_flush_ofs, n);
        warn("memcpy {} {} {}\n", comp.out_buf_ofs, comp.output_flush_ofs, n);
        var i: usize = 0;
        while (i < n) {
            comp.outbuf[i + comp.out_buf_ofs] = comp.output_buf[i + comp.output_flush_ofs];
            i += 1;
        }
        comp.output_flush_ofs += n;
        comp.output_flush_remaining -= n;
        comp.out_buf_ofs += n;

        comp.out_buf_size = comp.out_buf_ofs;
    }

    //return (comp.finished && !comp.output_flush_remaining) ? TDEFL_STATUS_DONE : TDEFL_STATUS_OKAY;
    return true;
}

fn compress(comp: *DeflateCompressor, pIn_buf: []u8, pIn_buf_size: *usize,
            pOut_buf: []u8, pOut_buf_size: *usize, flush: u32) bool {
    comp.inbuf = pIn_buf;
    comp.in_buf_size = pIn_buf_size.*;
    comp.outbuf = pOut_buf;
    comp.out_buf_size = pOut_buf_size.*;
    //comp.pSrc = (const mz_uint8 *)(pIn_buf);
    comp.src_pos = 0;
    //comp.src_buf_left = pIn_buf_size ? *pIn_buf_size : 0;
    comp.src_buf_left = pIn_buf.len;
    comp.out_buf_ofs = 0;
    comp.flush = flush;

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
    if (flush == TDEFL_FINISH) {
        comp.wants_to_finish |= 1;
    }

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
        warn("compress_normal() returned {}\n", res);
        if (!res) {
            return comp.prev_return_status;
        }
    }

    if (((comp.flags & (TDEFL_WRITE_ZLIB_HEADER | TDEFL_COMPUTE_ADLER32)) != 0) and (pIn_buf.len > 0)) {
       // comp.adler32 = (mz_uint32)mz_adler32(comp.adler32, (const mz_uint8 *)pIn_buf, comp.pSrc - (const mz_uint8 *)pIn_buf);
    }

    if ((flush != 0) and (comp.lookahead_size == 0) and (comp.src_buf_left == 0) and (comp.output_flush_remaining == 0)) {
        warn("Time to flush\n");
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

    comp.prev_return_status = flush_output_buffer(comp);
    return comp.prev_return_status;
}


test "test me please" {
    warn("Testing deflate");
    var symin: [258]tdefl_syfreq = undefined;
    var symout: [258]tdefl_syfreq = undefined;
    var r = tdefl_radix_sort_syms(256, symin[0..], symout[0..]);
    warn("r.len={}\n", r.len);
    //for (r) |it, i| {
    //    warn("[{}] key={}, symindex={}\n", i, it.key, it.syindex);
    //}
    var compressor: DeflateCompressor = undefined;
    tdefl_init(&compressor, 0);
    warn("sizeof compressor={}\n", usize(@sizeOf(@typeOf(compressor))));
    var input = "The quick brown fox jumps over the lazy dog";
    //var input = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const expected = "x\x9c\x0b\xc9HU(,\xcdL\xceVH*\xca/\xcfSH\xcb\xafP\xc8*\xcd-(V\xc8/K-R(\x01J\xe7$VU*\xa4\xe4\xa7\x03\x00[\xdc\x0f\xda";
    var inputlen = input.len;
    var output = []u8 {0} ** 1024;
    var outputlen = output.len;
    var result = compress(&compressor, input[0..], &inputlen, output[0..], &outputlen, TDEFL_FINISH | TDEFL_WRITE_ZLIB_HEADER);
    warn("1 {} {}\n", result, compressor.inbuf);
    warn("2 {}, {}\n", inputlen, outputlen);
    warn("3 {}, {}, {} {}\n", expected, compressor.src_pos, compressor.src_buf_left, compressor.pOutput_buf);
    warn("4 {}\n", compressor.output_buf);
}
