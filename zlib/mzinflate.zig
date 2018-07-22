// -*- mode:zig; indent-tabs-mode:nil;  -*-
const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;
const assert = std.debug.assert;
const assertError = std.debug.assertError;
const assertOrPanic = std.debug.assertOrPanic;
const builtin = @import("builtin");

const adler32 = @import("adler32.zig").adler32;
const mzutil = @import("mzutil.zig");
const Cursor = mzutil.Cursor;
const OutputBuffer = @import("mzoutputbuffer.zig").OutputBuffer;
const MIN = mzutil.MIN;
const MAX = mzutil.MAX;
const setmem = mzutil.setmem;

const TINFL_STATUS_FAILED_CANNOT_MAKE_PROGRESS: i32 = -4;
const TINFL_STATUS_BAD_PARAM: i32 = -3;
const TINFL_STATUS_ADLER32_MISMATCH: i32 = -2;
const TINFL_STATUS_FAILED: i32 = -1;
const TINFL_STATUS_DONE: i32 = 0;
const TINFL_STATUS_NEEDS_MORE_INPUT: i32 = 1;
const TINFL_STATUS_HAS_MORE_OUTPUT: i32 = 2;

/// Return status codes.
//#[repr(i8)]
//#[derive(Debug, Copy, Clone, PartialEq, Eq, Hash)]
pub const TINFLStatus = extern enum {
    /// More input data was expected, but the caller indicated that there was more data, so the
    /// input stream is likely truncated.
    FailedCannotMakeProgress = TINFL_STATUS_FAILED_CANNOT_MAKE_PROGRESS,
    /// One or more of the input parameters were invalid.
    BadParam = TINFL_STATUS_BAD_PARAM,
    /// The decompression went fine, but the adler32 checksum did not match the one
    /// provided in the header.
    Adler32Mismatch = TINFL_STATUS_ADLER32_MISMATCH,
    /// Failed to decompress due to invalid data.
    Failed = TINFL_STATUS_FAILED,
    /// Finished decomression without issues.
    Done = TINFL_STATUS_DONE,
    /// The decompressor needs more input data to continue decompressing.
    NeedsMoreInput = TINFL_STATUS_NEEDS_MORE_INPUT,
    /// There is still pending data that didn't fit in the output buffer.
    HasMoreOutput = TINFL_STATUS_HAS_MORE_OUTPUT,
};

// License MIT
// From https://github.com/Frommi/miniz_oxide
//! Streaming decompression functionality.

//use super::*;
//use shared::{HUFFMAN_LENGTH_ORDER, update_adler32};

//use std::{cmp, ptr, slice};

//use self::output_buffer::OutputBuffer;

// Merge constants from mzdeflate
pub const TINFL_LZ_DICT_SIZE: usize = 32768;

/// The number of huffman tables used.
const MAX_HUFF_TABLES: usize = 3;
/// The length of the first (literal/length) huffman table.
const MAX_HUFF_SYMBOLS_0: usize = 288;
/// The length of the second (distance) huffman table.
const MAX_HUFF_SYMBOLS_1: usize = 32;
/// The length of the last (huffman code length) huffman table.
const _MAX_HUFF_SYMBOLS_2: usize = 19;
/// The maximum length of a code that can be looked up in the fast lookup table.
const FAST_LOOKUP_BITS: u5 = 10;
/// The size of the fast lookup table.
const FAST_LOOKUP_SIZE: u32 = 1 << FAST_LOOKUP_BITS;
const MAX_HUFF_TREE_SIZE: usize = MAX_HUFF_SYMBOLS_0 * 2;
const LITLEN_TABLE: usize = 0;
const DIST_TABLE: usize = 1;
const HUFFLEN_TABLE: usize = 2;

//#[cfg(target_pointer_width = "64")]
const is_64bit = @sizeOf(usize) == @sizeOf(u64);
const BitBuffer = if (is_64bit) u64 else u32;

//#[cfg(not(target_pointer_width = "64"))]
//type BitBuffer = u32;

const HUFFMAN_LENGTH_ORDER: [19]u8 = []const u8 {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};

/// Should we try to parse a zlib header?
pub const TINFL_FLAG_PARSE_ZLIB_HEADER: u32 = 1;
/// There is more input that hasn't been given to the decompressor yet.
pub const TINFL_FLAG_HAS_MORE_INPUT: u32 = 2;
/// The output buffer should not wrap around.
pub const TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF: u32 = 4;
/// Should we calculate the adler32 checksum of the output data?
pub const TINFL_FLAG_COMPUTE_ADLER32: u32 = 8;

//use self::inflate_flags::*;
const MIN_TABLE_SIZES : [3]u16 = []const u16 {257, 1, 4};

pub const LookupResult = struct {
    const Self = this;
    symbol: i32,
    code_length: u32,

    fn new(s: i32, l: u32) LookupResult {
        return LookupResult {.symbol = s, .code_length = l};
    }

    fn dump(self: *const Self) void {
        warn("{}: symbol={}, code_length={}\n", self, self.symbol, self.code_length);
    }
};

/// A struct containing huffman code lengths and the huffman code tree used by the decompressor.
//#[repr(C)]
pub const HuffmanTable = extern struct {
    const Self = this;
    /// Length of the code at each index.
    pub code_size: [MAX_HUFF_SYMBOLS_0]u8,
    /// Fast lookup table for shorter huffman codes.
    ///
    /// See `HuffmanTable::fast_lookup`.
    pub look_up: [FAST_LOOKUP_SIZE]i16,
    /// Full huffman tree.
    ///
    /// Positive values are edge nodes/symbols, negative values are
    /// parent nodes/references to other nodes.
    pub tree: [MAX_HUFF_TREE_SIZE]i16,

    fn new() HuffmanTable {
        return HuffmanTable {
            .code_size = []u8 {0} ** MAX_HUFF_SYMBOLS_0,
            .look_up = []i16 {0} ** FAST_LOOKUP_SIZE,
            .tree = []i16 {0} ** MAX_HUFF_TREE_SIZE,
        };
    }

    /// Look for a symbol in the fast lookup table.
    /// The symbol is stored in the lower 9 bits, the length in the next 6.
    /// If the returned value is negative, the code wasn't found in the
    /// fast lookup table and the full tree has to be traversed to find the code.
    // #[inline]
    fn fast_lookup(self: *Self, bit_buf: BitBuffer) i16 {
        const r = self.look_up[(bit_buf & (FAST_LOOKUP_SIZE - 1))];
        warn("{}:fast_lookup({x016}), r={x04}\n", self, bit_buf, r);
        return r;
    }

    /// Get the symbol and the code length from the huffman tree.
    // #[inline]
    fn tree_lookup(self: *Self, fast_symbol: i32, bit_buf: BitBuffer, pcode_len: u32) LookupResult {
        var code_len = pcode_len;
        var symbol = fast_symbol;
        // We step through the tree until we encounter a positive value, which indicates a
        // symbol.
        while (true) {
            // symbol here indicates the position of the left (0) node, if the next bit is 1
            // we add 1 to the lookup position to get the right node.
            const usymbol = @bitCast(u32, ~symbol);
            symbol = (self.tree[(usymbol + ((bit_buf >> @truncate(u6, code_len)) & 1))]);
            code_len += 1;
            if (symbol >= 0) {
                break;
            }
        }
        return LookupResult{.symbol = symbol, .code_length = code_len};
    }

    /// Look up a symbol and code length from the bits in the provided bit buffer.
    ///
    /// Returns Some(symbol, length) on success,
    /// None if the length is 0.
    ///
    /// It's possible we could avoid checking for 0 if we can guarantee a sane table.
    /// TODO: Check if a smaller type for code_len helps performance.
    // #[inline]
    fn lookup(self: *Self, bit_buf: BitBuffer) ?LookupResult {
        const symbol = self.fast_lookup(bit_buf);
        if (symbol >= 0) {
            if ((symbol >> 9) != 0) {
                return LookupResult.new(symbol, @bitCast(u16, symbol >> 9));
            } else {
                // Zero-length code.
                return null;
            }
        } else {
            // We didn't get a symbol from the fast lookup table, so check the tree instead.
             return self.tree_lookup(symbol, bit_buf, FAST_LOOKUP_BITS);
        }
    }
};

/// Main decompression struct.
///
/// This is repr(C) to be usable in the C API.
//#[repr(C)]
//#[allow(bad_style)]
pub const Decompressor = extern struct {
    const Self = this;
    /// Current state of the decompressor.
    state: State,
    /// Number of bits in the bit buffer.
    num_bits: u32,
    /// Zlib CMF
    z_header0: u32,
    /// Zlib FLG
    z_header1: u32,
    /// Adler32 checksum from the zlib header.
    z_adler32: u32,
    /// 1 if the current block is the last block, 0 otherwise.
    finish: u32,
    /// The type of the current block.
    block_type: u32,
    /// 1 if the adler32 value should be checked.
    check_adler32: u32,
    /// Last match distance.
    dist: u32,
    /// Variable used for match length, symbols, and a number of other things.
    counter: u32,
    /// Number of extra bits for the last length or distance code.
    num_extra: u32,
    /// Number of entries in each huffman table.
    table_sizes: [MAX_HUFF_TABLES]u32,
    /// Buffer of input data.
    bit_buf: BitBuffer,
    /// Position in the output buffer.
    dist_from_out_buf_start: usize,
    /// Huffman tables.
    tables: [MAX_HUFF_TABLES]HuffmanTable,
    /// Raw block header.
    raw_header: [4]u8,
    /// Huffman length codes.
    len_codes: [MAX_HUFF_SYMBOLS_0 + MAX_HUFF_SYMBOLS_1 + 137]u8,

    fn dump(self: *const Self) void {
        warn("{}: num_bits={}, block_type={}, state={}/{}\n", self, self.*.num_bits,
             self.*.block_type, @enumToInt(self.*.state), self.*.state.is_failure());
    }

    /// Create a new tinfl_decompressor with all fields set to 0.
    pub fn new() Decompressor {
        return Decompressor.default();
    }

    /// Create a new tinfl_decompressor with all fields set to 0.
    pub fn default() Decompressor {
        return Decompressor {
            .state = State.Start,
            .num_bits = 0,
            .z_header0 = 0,
            .z_header1 = 0,
            .z_adler32 = 0,
            .finish = 0,
            .block_type = 0,
            .check_adler32 = 0,
            .dist = 0,
            .counter = 0,
            .num_extra = 0,
            .table_sizes = []u32 {0} ** MAX_HUFF_TABLES,
            .bit_buf = 0,
            .dist_from_out_buf_start = 0,
            // TODO:(oyvindln) Check that copies here are optimized out in release mode.
            .tables = []HuffmanTable {HuffmanTable.new(), HuffmanTable.new(), HuffmanTable.new()},
            .raw_header = []u8 {0} ** 4,
            .len_codes = []u8 {0} ** (MAX_HUFF_SYMBOLS_0 + MAX_HUFF_SYMBOLS_1 + 137),
        };
    }

    /// Set the current state to `Start`.
    //#[inline]
    pub fn init(self: *Self) void {
        self.state = State.Start;
    }

    /// Create a new decompressor with only the state field initialized.
    ///
    /// This is how it's created in miniz. Unsafe due to uninitialized values.
    //#[inline]
    pub fn with_init_state_only() Decompressor {
        var decomp: Decompressor = undefined;
        decomp.state = State.Start;
        return decomp;
    }

    /// Returns the adler32 checksum of the currently decompressed data.
    //#[inline]
    pub fn adler32(self: *const Self) ?u32 {
        if ((self.state != State.Start) and (!self.state.is_failure()) and (self.z_header0 != 0)) {
            return self.check_adler32;
        } else {
            return null;
        }
    }
};

//#[derive(Copy, Clone, PartialEq, Eq, Debug)]
//#[repr(C)]
pub const State = extern enum {
    const Self = this;
    Start = 0,
    ReadZlibCmf,
    ReadZlibFlg,
    ReadBlockHeader,
    BlockTypeNoCompression,
    RawHeader,
    RawMemcpy1,
    RawMemcpy2,
    ReadTableSizes,
    ReadHufflenTableCodeSize,
    ReadLitlenDistTablesCodeSize, // 10
    ReadExtraBitsCodeSize,
    DecodeLitlen,
    WriteSymbol,
    ReadExtraBitsLitlen,
    DecodeDistance,
    ReadExtraBitsDistance,
    RawReadFirstByte,
    RawStoreFirstByte,
    WriteLenBytesToEnd,
    BlockDone, // 20
    HuffDecodeOuterLoop1,
    HuffDecodeOuterLoop2,
    ReadAdler32,

    DoneForever, // 24

    // Failure states.
    BlockTypeUnexpected,
    BadCodeSizeSum,
    BadTotalSymbols,
    BadZlibHeader,
    DistanceOutOfBounds,
    BadRawLength, // 30
    BadCodeSizeDistPrevLookup,
    InvalidLitlen,
    InvalidDist,
    InvalidCodeLen,

    fn is_failure(self: *const Self) bool {
        return switch (self.*) {
            State.BlockTypeUnexpected => true,
            State.BadCodeSizeSum => true,
            State.BadTotalSymbols => true,
            State.BadZlibHeader => true,
            State.DistanceOutOfBounds => true,
            State.BadRawLength => true,
            State.BadCodeSizeDistPrevLookup => true,
            State.InvalidLitlen => true,
            State.InvalidDist => true,
            else => false,
        };
    }

    //#[inline]
    fn begin(self: * Self, new_state: State) void {
        self.* = new_state;
    }

    fn begin2(self: *const Self, new_state: State) void {
        self.* = new_state;
    }
};

fn begin(state: *State, new_state: State) void {
    state.* = new_state;
}

//use self::State::*;

// Not sure why miniz uses 32-bit values for these, maybe alignment/cache again?
// # Optimization
// We add a extra value at the end and make the tables 32 elements long
// so we can use a mask to avoid bounds checks.
// The invalid values are set to something high enough to avoid underflowing
// the match length.
/// Base length for each length code.
///
/// The base is used together with the value of the extra bits to decode the actual
/// length/distance values in a match.
//#[cfg_attr(rustfmt, rustfmt_skip)]
const LENGTH_BASE: [32]u16 = []const u16 {
    3,  4,  5,  6,  7,  8,  9,  10,  11,  13,  15,  17,  19,  23,  27,  31,
    35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258, 512, 512, 512
};

/// Number of extra bits for each length code.
//#[cfg_attr(rustfmt, rustfmt_skip)]
const LENGTH_EXTRA: [32]u8 = []const u8 {
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
    3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0, 0, 0, 0
};

/// Base length for each distance code.
//#[cfg_attr(rustfmt, rustfmt_skip)]
const DIST_BASE: [32]u16 = []const u16 {
    1,    2,    3,    4,    5,    7,      9,      13,     17,     25,    33,
    49,   65,   97,   129,  193,  257,    385,    513,    769,    1025,  1537,
    2049, 3073, 4097, 6145, 8193, 12289,  16385,  24577,  32768,  32768
};

/// Number of extra bits for each distance code.
//#[cfg_attr(rustfmt, rustfmt_skip)]
const DIST_EXTRA: [32]u8 = []const u8 {
    0, 0, 0, 0, 1, 1, 2,  2,  3,  3,  4,  4,  5,  5,  6,  6,
    7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 13, 13
};

/// The mask used when indexing the base/extra arrays.
const BASE_EXTRA_MASK: usize = 32 - 1;

// fn memset<T: Copy>(slice: &mut [T], val: T) {
//     for x in slice {
//         *x = val
//     }
// }

/// Read an le u16 value from the slice iterator.
///
/// # Panics
/// Panics if there are less than two bytes left.
//#[inline]
fn read_u16_le(iter: *IterBuf) u16 {
    var ret: u16 = 0;
    // let ret = {
    //     let two_bytes = &iter.as_ref()[0..2];
    //     // # Unsafe
    //     //
    //     // The slice was just bounds checked to be 2 bytes long.
    //     unsafe { ptr::read_unaligned(two_bytes.as_ptr() as *const u16) }
    // };
    //iter.nth(1);
    //u16::from_le(ret)
    ret =  mem.readInt(iter.buf[iter.pos..iter.pos+@sizeOf(u16)], u16, builtin.Endian.Little);
    iter.pos += @sizeOf(u16);
    warn("read_u16_le = {x04}\n", ret);
    return ret;
}

/// Read an le u32 value from the slice iterator.
///
/// # Panics
/// Panics if there are less than four bytes left.
//#[inline(always)]
//#[cfg(target_pointer_width = "64")]
fn read_u32_le(iter: *IterBuf) u32 {
    var ret: u32 = 0;
    // let ret = {
    //     let four_bytes = &iter.as_ref()[..4];
    //     // # Unsafe
    //     //
    //     // The slice was just bounds checked to be 4 bytes long.
    //     unsafe { ptr::read_unaligned(four_bytes.as_ptr() as *const u32) }
    // };
    // iter.nth(3);
    // u32::from_le(ret)

    ret =  mem.readInt(iter.buf[iter.pos..iter.pos+@sizeOf(u32)], u32, builtin.Endian.Little);
    iter.pos += @sizeOf(u32);
    warn("read_u32_le = {x08}\n", ret);
    return ret;
}

/// Ensure that there is data in the bit buffer.
///
/// On 64-bit platform, we use a 64-bit value so this will
/// result in there being at least 32 bits in the bit buffer.
/// This function assumes that there is at least 4 bytes left in the input buffer.
//#[inline(always)]
//#[cfg(target_pointer_width = "64")]
fn fill_bit_buffer(l: *LocalVars, in_iter: *IterBuf) void {
    // Read four bytes into the buffer at once.
    if (l.num_bits < 30) {
        l.bit_buf |= (u64(read_u32_le(in_iter))) << l.shift();
        l.num_bits += 32;
    }
}

/// Same as previous, but for non-64-bit platforms.
/// Ensures at least 16 bits are present, requires at least 2 bytes in the in buffer.
// #[inline(always)]
// #[cfg(not(target_pointer_width = "64"))]
// fn fill_bit_buffer(l: &mut LocalVars, in_iter: &mut slice::Iter<u8>) {
//     // If the buffer is 32-bit wide, read 2 bytes instead.
//     if l.num_bits < 15 {
//         l.bit_buf |= (read_u16_le(in_iter) as BitBuffer) << l.num_bits;
//         l.num_bits += 16;
//     }
// }

//#[inline]
fn _transfer_unaligned_u64(buf: []u8, from: isize, to: isize) void {
    // unsafe {
    //     let mut data = ptr::read_unaligned((*buf).as_ptr().offset(from) as *const u32);
    //     ptr::write_unaligned((*buf).as_mut_ptr().offset(to) as *mut u32, data);

    //     data = ptr::read_unaligned((*buf).as_ptr().offset(from + 4) as *const u32);
    //     ptr::write_unaligned((*buf).as_mut_ptr().offset(to + 4) as *mut u32, data);
    // };
}

/// Check that the zlib header is correct and that there is enough space in the buffer
/// for the window size specified in the header.
///
/// See https://tools.ietf.org/html/rfc1950
//#[inline]
fn validate_zlib_header(cmf: u32, flg: u32, flags: u32, mask: usize) Action {
    var failed =
    // cmf + flg should be divisible by 31.
        (((cmf * 256) + flg) % 31 != 0) or
    // If this flag is set, a dictionary was used for this zlib compressed data.
    // This is currently not supported by miniz or miniz-oxide
        ((flg & 0b00100000) != 0) or
    // Compression method. Only 8(DEFLATE) is defined by the standard.
        ((cmf & 15) != 8);

    const window_size = u32(1) << @truncate(u5, (cmf >> 4) + 8);
    var badwrap = false;
    if ((flags & TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF) == 0) {
        // Bail if the buffer is wrapping and the window size is larger than the buffer.
        warn("mask={}, window_size={}\n", (mask + 1), window_size);
        badwrap = (mask + 1) < window_size;
    }

    // Zlib doesn't allow window sizes above 32 * 1024.
    const badwindow = window_size > 32768;

    if (failed or badwindow or badwrap) {
        warn("validate_zlib_header failed={}, badwindow={}, badwrap={}\n",
             failed, badwindow, badwrap);
        return Action{.Jump = State.BadZlibHeader};
    } else {
        return Action{.Jump = State.ReadBlockHeader};
    }
}


const Action = union(enum) {
    None,
    Jump: State,
    End: TINFLStatus,
};

const ActionOrSymbol = union(enum) {
    const Self = this;
    AOSAction: Action,
    AOSSymbol: i32,

    fn dump(self: *const Self) void {
        switch (self.*) {
            ActionOrSymbol.AOSAction => |a| {
                warn("{}: action=", self); // , @enumToInt(a));
                switch (a) {
                    Action.None => |j| {
                        warn("None\n");
                    },
                    Action.Jump => |j| {
                        warn("Jump to {}\n", @enumToInt(j));
                    },
                    Action.End => |e| {
                        warn("End status {}\n", @enumToInt(e));
                    },
                    else => unreachable,
                }
            },
            ActionOrSymbol.AOSSymbol => |s| {
                warn("{}: symbol={}\n", self, s);
            },
        }
    }
    // can't have an argument with the same name as the function
    fn action(act: Action) ActionOrSymbol {
        return ActionOrSymbol {.AOSAction = act};
    }

    fn symbol(sym: i32) ActionOrSymbol {
        return ActionOrSymbol {.AOSSymbol = sym};
    }

};

/// Try to decode the next huffman code, and puts it in the counter field of the decompressor
/// if successful.
///
/// # Returns
/// The specified action returned from `f` on success,
/// `Action::End` if there are not enough data left to decode a symbol.
//    F: ,
fn decode_huffman_code(
    r: *Decompressor,
    l: *LocalVars,
    table: usize,
    flags: u32,
    in_iter: *IterBuf,
    //f: fn(*Decompressor, *LocalVars, i32) Action,
) ActionOrSymbol //Action
// where
//     F: FnOnce(&mut Decompressor, &mut LocalVars, i32) -> Action,
{
    // As the huffman codes can be up to 15 bits long we need at least 15 bits
    // ready in the bit buffer to start decoding the next huffman code.
    r.dump();
    l.dump();
    if (l.num_bits < 15) {
        // First, make sure there is enough data in the bit buffer to decode a huffman code.
        if (in_iter.len() < 2) {
            // If there is less than 2 bytes left in the input buffer, we try to look up
            // the huffman code with what's available, and return if that doesn't succeed.
            // Original explanation in miniz:
            // /* TINFL_HUFF_BITBUF_FILL() is only used rarely, when the number of bytes
            //  * remaining in the input buffer falls below 2. */
            // /* It reads just enough bytes from the input stream that are needed to decode
            //  * the next Huffman code (and absolutely no more). It works by trying to fully
            //  * decode a */
            // /* Huffman code by using whatever bits are currently present in the bit buffer.
            //  * If this fails, it reads another byte, and tries again until it succeeds or
            //  * until the */
            // /* bit buffer contains >=15 bits (deflate's max. Huffman code size). */
            while (true) {
                var temp: i32 = r.tables[table].fast_lookup(l.bit_buf);
                warn("temp={}\n", temp);

                if (temp >= 0) {
                    const code_len = @bitCast(u32, temp >> 9);
                    if ((code_len != 0) and (l.num_bits >= code_len)) {
                        break;
                    }
                } else if (l.num_bits > FAST_LOOKUP_BITS) {
                    var code_len: u32 = FAST_LOOKUP_BITS;
                    while (true) {
                        const utemp = @bitCast(u32, ~temp);
                        temp = r.tables[table].tree[(utemp + ((l.bit_buf >> @truncate(u6, code_len)) & 1))];
                        code_len += 1;
                        if ((temp >= 0) or (l.num_bits < (code_len + 1))) {
                            break;
                        }
                    }
                    if (temp >= 0) {
                        break;
                    }
                }

                // TODO: miniz jumps straight to here after getting here again after failing to read
                // a byte.
                // Doing that lets miniz avoid re-doing the lookup that that was done in the
                // previous call.
                var byte: u8 = 0;
                if (get_byte(in_iter, flags)) |b| {
                    byte = b;
                } else {
                    return ActionOrSymbol.action(Action{.End = TINFLStatus.Failed});
                }
                // if let a @ Action::End(_) =
                //     read_byte(in_iter, flags, |b| {
                //         byte = b;
                //         Action::None
                //     })
                // {
                //     return a;
                // };

                // Do this outside closure for now to avoid borrowing r.
                l.bit_buf |= BitBuffer(byte) << @truncate(u6, l.num_bits);
                l.num_bits += 8;

                if (l.num_bits >= 15) {
                    break;
                }
            }
        } else {
            // There is enough data in the input buffer, so read the next two bytes
            // and add them to the bit buffer.
            // Unwrapping here is fine since we just checked that there are at least two
            // bytes left.
            l.bit_buf |= BitBuffer(read_u16_le(in_iter)) << l.shift();
            l.num_bits += 16;
        }
    }

    // We now have at least 15 bits in the input buffer.
    var symbol: i32 = r.tables[table].fast_lookup(l.bit_buf);
    var code_len: i32 = 0;
    // If the symbol was found in the fast lookup table.
    if (symbol >= 0) {
        // Get the length value from the top bits.
        // As we shift down the sign bit, converting to an unsigned value
        // shouldn't overflow.
        code_len = (symbol >> 9);
        // Mask out the length value.
        symbol &= 511;
    } else {
        const res = r.tables[table].tree_lookup(symbol, l.bit_buf, FAST_LOOKUP_BITS);
        symbol = res.symbol;
        code_len = @bitCast(i32, res.code_length);
    }

    warn("code_len={}\n", code_len);
    if (code_len == 0) {
        return ActionOrSymbol.action(Action{.Jump = State.InvalidCodeLen});
    }

    l.bit_buf >>= @truncate(u6, @bitCast(u32, code_len));
    l.num_bits -= @bitCast(u32, code_len);
    //return f(r, l, symbol);
    return ActionOrSymbol.symbol(symbol);
}

const IterBuf = struct {
    const Self = this;
    buf: []u8,
    pos: usize,

    fn dump(self: *const Self) void {
        warn("{}: len={}, pos={}, byte={x02}\n", self, self.buf.len, self.*.pos, self.*.buf[self.*.pos]);
    }

    fn next(self: *Self) ?u8 {
        if (self.*.pos < self.buf.len) {
            self.*.pos += 1;
            return self.*.buf[self.*.pos - 1];
        } else {
            return null;
        }
    }

    fn len(self: *const Self) usize {
        return self.buf.len - self.*.pos;
    }
};

//#[inline]
fn read_byte(in_iter: []u8, flags: u32, f: fn(u8) Action) Action
// where
//     F: FnOnce(u8) -> Action,
{
    switch (in_iter.next()) {
        null => end_of_input(flags),
        else  => |byte| f(byte),
    }
}

// Actionless variants for now...
fn get_byte(in_iter: *IterBuf, flags: u32) ?u8{
    in_iter.*.dump();
    const b = in_iter.*.next();
    warn("get_byte(flags={x08}) -> {x02}\n", flags, b);
    return b;
}

// TODO: `l: &mut LocalVars` may be slow similar to decompress_fast (even with inline(always))
//#[inline]
fn read_bits(
    l: *LocalVars,
    amount: u32,
    in_iter: []u8,
    flags: u32,
    f: fn(*LocalVars, BitBuffer) Action,
) Action
// where
//     F: FnOnce(&mut LocalVars, BitBuffer) -> Action,
{
    const shift = @truncate(u5, amount);
    while (l.num_bits < shift) {
        // switch read_byte(in_iter, flags, |byte| {
        //     l.bit_buf |= (byte as BitBuffer) << l.num_bits;
            l.num_bits += 8;
        //     Action::None
        // }) {
        //     Action::None => (),
        //     action => return action,
        // }
    }

    const bits = l.bit_buf & ((@typeOf(l.bit_buf)(1) << shift) - 1);
    l.bit_buf >>= shift;
    l.num_bits -= amount;
    return f(l, bits);
}

fn get_bits(l: *LocalVars, amount: u32, in_iter: *IterBuf, flags: u32) ?BitBuffer {
    const shift = @truncate(u5, amount);
    warn("1 get_bits({}, {}) {x}, {}\n", amount, shift, l.bit_buf, l.num_bits);
    while (l.num_bits < shift) {
        if (in_iter.next()) |byte| {
            warn("1.1 get_bits byte = {x02}\n", byte);
            l.bit_buf |= BitBuffer(byte) << l.shift();
            l.num_bits += 8;
        } else {
            return null;
        }
    }
    warn("2 get_bits({}, {}) {x}, {}\n", amount, shift, l.bit_buf, l.num_bits);

    const bits = l.bit_buf & ((@typeOf(l.bit_buf)(1) << shift) - 1);
    l.bit_buf >>= shift;
    l.num_bits -= amount;
    warn("3 get_bits({}, {}) -> bits={x}, {x}, {}\n", amount, shift, bits, l.bit_buf, l.num_bits);
    return bits;
}

//#[inline]
fn pad_to_bytes(l: *LocalVars, in_iter: *[]u8, flags: u32, f: fn(*LocalVars) Action) Action
// where
//     F: FnOnce(&mut LocalVars) -> Action,
{
    const num_bits = l.num_bits & 7;
    return read_bits(l, num_bits, in_iter, flags, f(l));
}

//#[inline]
fn end_of_input(flags: u32) Action {
    return Action{.End = if ((flags & TINFL_FLAG_HAS_MORE_INPUT) != 0) 
        TINFLStatus.NeedsMoreInput
    else 
        TINFLStatus.FailedCannotMakeProgress
    };
}

//#[inline]
inline fn undo_bytes(l: *LocalVars, max: u32) u32 {
    const res = MIN(u32, l.num_bits >> 3, max);
    l.num_bits -= res << 3;
    return res;
}

fn start_static_table(r: *Decompressor) void {
    r.table_sizes[LITLEN_TABLE] = 288;
    r.table_sizes[DIST_TABLE] = 32;
    setmem(u8, r.tables[LITLEN_TABLE].code_size[0..144], 8);
    setmem(u8, r.tables[LITLEN_TABLE].code_size[144..256], 9);
    setmem(u8, r.tables[LITLEN_TABLE].code_size[256..280], 7);
    setmem(u8, r.tables[LITLEN_TABLE].code_size[280..288], 8);
    setmem(u8, r.tables[DIST_TABLE].code_size[0..32], 5);
}

// For my Rust based Emacs mode...
inline fn shl(v: var, s: var) @typeOf(v) {
    return v << s;
}
inline fn shr(v: var, s: var) @typeOf(v) {
    return v >> s;
}

fn init_tree(r: *Decompressor, l: *LocalVars) Action {
    warn("init_tree()\n");
    while (true) {
        var table = &r.tables[r.block_type];
        const table_size = r.table_sizes[r.block_type];
        warn("block_type={}, table_size={}\n", r.block_type, table_size);
        var total_symbols = []u32 {0} ** 16;
        var next_code = []u32 {0} ** 17;
        setmem(i16, table.look_up[0..], 0);
        setmem(i16, table.tree[0..], 0);

        for (table.code_size[0..table_size]) |code_size| {
            total_symbols[code_size] += 1;
        }

        var used_symbols: u32 = 0;
        var total: u32 = 0;
        // for i in 1..16 {
        var i: usize = 1;
        while (i < 16) : (i += 1) {
            used_symbols += total_symbols[i];
            total += total_symbols[i];
            total <<= 1;
            next_code[i + 1] = total;
        }
        warn("used_symbols={}, total={}\n", used_symbols, total);

        if ((total != 65536) and (used_symbols > 1)) {
            return Action{.Jump = State.BadTotalSymbols};
        }

        var tree_next: i16 = -1;
        // for symbol_index in 0..table_size
        var symbol_index: u16 = 0;
        while (symbol_index < table_size) : (symbol_index += 1) {
            var rev_code: u32 = 0;
            const code_size = table.code_size[symbol_index];
            if (code_size == 0) {
                continue;
            }

            var cur_code = next_code[code_size];
            next_code[code_size] += 1;

            // for _ in 0..code_size
            var ii: u32 = 0;
            while (ii < code_size) : (ii += 1) {
                rev_code = shl(rev_code, 1) | (cur_code & 1);
                cur_code >>= 1;
            }

            if (code_size <= FAST_LOOKUP_BITS) {
                const k = (i16(code_size) << 9) | @bitCast(i16, symbol_index);
                while (rev_code < FAST_LOOKUP_SIZE) {
                    table.look_up[rev_code] = k;
                    rev_code += u32(1) << @truncate(u5, code_size);
                }
                continue;
            }

            var tree_cur = table.look_up[(rev_code & (FAST_LOOKUP_SIZE - 1))];
            if (tree_cur == 0) {
                table.look_up[(rev_code & (FAST_LOOKUP_SIZE - 1))] = tree_next;
                tree_cur = tree_next;
                tree_next -= 2;
            }

            rev_code >>= FAST_LOOKUP_BITS - 1;
            //         for _ in FAST_LOOKUP_BITS + 1..code_size {
            ii = FAST_LOOKUP_BITS + 1;
            while (ii < code_size) : (ii += 1) {
                rev_code >>= 1;
                // rev_code is u32, & 1 and we have 1 bit, we get a lot of juggling to do...
                tree_cur -= @bitCast(i16, @truncate(u16, rev_code & 1));
                if (table.tree[@bitCast(u16, -tree_cur - 1)] == 0) {
                    table.tree[@bitCast(u16, -tree_cur - 1)] = tree_next;
                    tree_cur = tree_next;
                    tree_next -= 2;
                } else {
                    tree_cur = table.tree[@bitCast(u16, -tree_cur - 1)];
                }
            }

            rev_code >>= 1;
            tree_cur -= @bitCast(i16, @truncate(u16, (rev_code & 1)));
            table.tree[@bitCast(u16, -tree_cur - 1)] = @bitCast(i16, symbol_index);
        }

        if (r.block_type == 2) {
            l.counter = 0;
            return Action{.Jump = State.ReadLitlenDistTablesCodeSize};
        }

        if (r.block_type == 0) {
            break;
        }
        r.block_type -= 1;
    }

    l.counter = 0;
    r.dump();
    l.dump();
    return Action{.Jump = State.DecodeLitlen};
}

//#[derive(Copy, Clone)]
const LocalVars = struct {
    const Self = this;
    pub bit_buf: BitBuffer,
    pub num_bits: u32,
    pub dist: u32,
    pub counter: u32,
    pub num_extra: u32,
    pub dist_from_out_buf_start: usize,

    fn dump(self: *const Self) void {
        warn("{}: bit_buf={x}, num_bits={}, dist={}, counter={}, num_extra={}, dist_from_out_buf_start={}\n",
             self, self.bit_buf, self.num_bits, self.dist, self.counter,
             self.num_extra, self.dist_from_out_buf_start);
    }

    inline fn shift(self: *const Self) u6 {
        return @truncate(u6, self.*.num_bits);
    }
};

//#[inline]
fn transfer(
    out_slice: []u8,
    psource_pos: usize,
    pout_pos: usize,
    match_len: usize,
    out_buf_size_mask: usize,
) void {
    var source_pos = psource_pos;
    var out_pos = pout_pos;
    assert((out_pos + match_len) <= out_slice.len);

    //for _ in 0..match_len >> 2 {
    var i: usize = 0;
    while(i < match_len >> 2) : (i += 1) {
        out_slice[out_pos] = out_slice[source_pos & out_buf_size_mask];
        out_slice[out_pos + 1] = out_slice[(source_pos + 1) & out_buf_size_mask];
        out_slice[out_pos + 2] = out_slice[(source_pos + 2) & out_buf_size_mask];
        out_slice[out_pos + 3] = out_slice[(source_pos + 3) & out_buf_size_mask];
        source_pos += 4;
        out_pos += 4;
    }

    switch (match_len & 3) {
        0 => {},
        1 => out_slice[out_pos] = out_slice[source_pos & out_buf_size_mask],
        2 => {
            out_slice[out_pos] = out_slice[source_pos & out_buf_size_mask];
            out_slice[out_pos + 1] = out_slice[(source_pos + 1) & out_buf_size_mask];
        },
        3 =>  {
            out_slice[out_pos] = out_slice[source_pos & out_buf_size_mask];
            out_slice[out_pos + 1] = out_slice[(source_pos + 1) & out_buf_size_mask];
            out_slice[out_pos + 2] = out_slice[(source_pos + 2) & out_buf_size_mask];
        },
        else => unreachable,
    }
}

/// Presumes that there is at least match_len bytes in output left.
//#[inline]
fn apply_match(
    out_slice: []u8,
    out_pos: usize,
    dist: usize,
    match_len: usize,
    out_buf_size_mask: usize,
) void {
    assert(out_pos + match_len <= out_slice.len);
    warn("appy_match({}, {}, {}, {})", out_pos, dist, match_len, out_buf_size_mask);

    const source_pos = (out_pos -% dist) & out_buf_size_mask;

    if (match_len == 3) {
        // Fast path for match len 3.
        out_slice[out_pos] = out_slice[source_pos];
        out_slice[out_pos + 1] = out_slice[(source_pos + 1) & out_buf_size_mask];
        out_slice[out_pos + 2] = out_slice[(source_pos + 2) & out_buf_size_mask];
        return;
    }

    if (builtin.arch != builtin.Arch.i386 and builtin.arch != builtin.Arch.x86_64) {
        // We are not on x86 so copy manually.
        transfer(out_slice, source_pos, out_pos, match_len, out_buf_size_mask);
        return;
    }

    if ((source_pos >= out_pos) and ((source_pos - out_pos) < match_len)) {
        transfer(out_slice, source_pos, out_pos, match_len, out_buf_size_mask);
    } else if ((match_len <= dist) and ((source_pos + match_len) < out_slice.len)) {
        // Destination and source segments does not intersect and source does not wrap.
        if (source_pos < out_pos) {
            const from_slice = out_slice[0..out_pos];
            const to_slice = out_slice[out_pos..];
            //to_slice[0..match_len].copy_from_slice(&from_slice[source_pos..source_pos + match_len]);
            for (from_slice[source_pos..source_pos + match_len]) |v, i| {
                to_slice[i] = v;
            }
        } else {
            //const (to_slice, from_slice) = out_slice.split_at_mut(source_pos);
            //to_slice[out_pos..out_pos + match_len].copy_from_slice(&from_slice[0..match_len]);
            const from_slice = out_slice[0..source_pos];
            const to_slice = out_slice[source_pos..];
            for (from_slice[0..match_len]) |v, i| {
                to_slice[i] = v;
            }
        }
    } else {
        transfer(out_slice, source_pos, out_pos, match_len, out_buf_size_mask);
    }
}

const FastResult = struct {
    status: TINFLStatus,
    state: State,
};


/// Fast inner decompression loop which is run  while there is at least
/// 259 bytes left in the output buffer, and at least 6 bytes left in the input buffer
/// (The maximum one match would need + 1).
///
/// This was inspired by a similar optimization in zlib, which uses this info to do
/// faster unchecked copies of multiple bytes at a time.
/// Currently we don't do this here, but this function does avoid having to jump through the
/// big match loop on each state change(as rust does not have fallthrough or gotos at the moment),
/// and already improves decompression speed a fair bit.
fn decompress_fast(
    r: *Decompressor,
    in_iter: *IterBuf, // mut
    out_buf: *OutputBuffer,
    flags: u32,
    local_vars: *LocalVars,
    out_buf_size_mask: usize,
) FastResult {
    // Make a local copy of the most used variables, to avoid having to update and read from values
    // in a random memory location and to encourage more register use.
    var l = local_vars.*;
    var state: State = undefined;

    const status: TINFLStatus = out: while (true) {
        state = State.DecodeLitlen;
        litlen: while (true) {
            // This function assumes that there is at least 259 bytes left in the output buffer,
            // and that there is at least 14 bytes left in the input buffer. 14 input bytes:
            // 15 (prev lit) + 15 (length) + 5 (length extra) + 15 (dist)
            // + 29 + 32 (left in bit buf, including last 13 dist extra) = 111 bits < 14 bytes
            // We need the one extra byte as we may write one length and one full match
            // before checking again.
            if ((out_buf.bytes_left() < 259) or (in_iter.len() < 14)) {
                state = State.DecodeLitlen;
                break :out TINFLStatus.Done;
            }

            fill_bit_buffer(&l, in_iter);

            if (r.tables[LITLEN_TABLE].lookup(l.bit_buf)) |r1| {
                const usymbol = @bitCast(u32, r1.symbol);
                const code_len = r1.code_length;
                l.counter = usymbol;
                l.bit_buf >>= @truncate(u6, code_len);
                l.num_bits -= code_len;

                if ((l.counter & 256) != 0) {
                    // The symbol is not a literal.
                    break;
                } else {
                    // If we have a 32-bit buffer we need to read another two bytes now
                    // to have enough bits to keep going.
                    //cfg!(not(target_pointer_width = "64"))
                    if (!is_64bit) {
                        fill_bit_buffer(l, in_iter);
                    }

                    if (r.tables[LITLEN_TABLE].lookup(l.bit_buf)) |r2| {
                        const usymbol2 = @bitCast(u32, r2.symbol);
                        const code_len2 = r2.code_length;
                        l.bit_buf >>= @truncate(u6, code_len2);
                        l.num_bits -= code_len2;
                        // The previous symbol was a literal, so write it directly and check
                        // the next one.
                        out_buf.write_byte(@truncate(u8, l.counter));
                        if ((usymbol2 & 256) != 0) {
                            l.counter = usymbol2;
                            // The symbol is a length value.
                            break;
                        } else {
                            // The symbol is a literal, so write it directly and continue.
                            out_buf.write_byte(@truncate(u8, usymbol2));
                        }
                    } else {
                        //state.begin(State.InvalidCodeLen);
                        state = State.InvalidCodeLen;
                        break :out TINFLStatus.Failed;
                    }
                }
            } else {
                //state.begin(State.InvalidCodeLen);
                state = State.InvalidCodeLen;
                break :out TINFLStatus.Failed;
            }
        }

        // Mask the top bits since they may contain length info.
        l.counter &= 511;
        if (l.counter == 256) {
            // We hit the end of block symbol.
            //state.begin(State.BlockDone);
            state = State.BlockDone;
            break :out TINFLStatus.Done;
        } else if (l.counter > 285) {
            // Invalid code.
            // We already verified earlier that the code is > 256.
            //state.begin(State.InvalidLitlen);
            state = State.InvalidLitlen;
            break :out TINFLStatus.Failed;
        } else {
            // The symbol was a length code.
            // # Optimization
            // Mask the value to avoid bounds checks
            // We could use get_unchecked later if can statically verify that
            // this will never go out of bounds.
            l.num_extra = LENGTH_EXTRA[(l.counter - 257) & BASE_EXTRA_MASK];
            l.counter = LENGTH_BASE[(l.counter - 257) & BASE_EXTRA_MASK];
            // Length and distance codes have a number of extra bits depending on
            // the base, which together with the base gives us the exact value.

            fill_bit_buffer(&l, in_iter);
            if (l.num_extra != 0) {
                const extra_bits = l.bit_buf & ((BitBuffer(1) << @truncate(u6, l.num_extra)) - 1);
                l.bit_buf >>= @truncate(u6, l.num_extra);
                l.num_bits -= l.num_extra;
                l.counter += @truncate(u32, extra_bits);
            }

            // We found a length code, so a distance code should follow.
            if (!is_64bit) {
                fill_bit_buffer(&l, in_iter);
            }

            if (r.tables[DIST_TABLE].lookup(l.bit_buf)) |res|{
                var symbol = @bitCast(u32, res.symbol) & 511;
                const code_len = res.code_length;
                //symbol &= 511;
                l.bit_buf >>= @truncate(u6, code_len);
                l.num_bits -= code_len;
                if (symbol > 29) {
                    //state.begin(State.InvalidDist);
                    state = State.InvalidDist;
                    break :out TINFLStatus.Failed;
                }

                l.num_extra = DIST_EXTRA[symbol];
                l.dist = DIST_BASE[symbol];
            } else {
                //state.begin(State.InvalidCodeLen);
                state = State.InvalidCodeLen;
                break :out TINFLStatus.Failed;
            }

            if (l.num_extra != 0) {
                fill_bit_buffer(&l, in_iter);
                const extra_bits = l.bit_buf & ((BitBuffer(1) << @truncate(u6, l.num_extra)) - 1);
                l.bit_buf >>= @truncate(u6, l.num_extra);
                l.num_bits -= l.num_extra;
                l.dist += @truncate(u32, extra_bits);
            }

            l.dist_from_out_buf_start = out_buf.position();
            if ((l.dist > l.dist_from_out_buf_start) and
                (flags & TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF != 0))
            {
                // We encountered a distance that refers a position before
                // the start of the decoded data, so we can't continue.
                //state.begin(State.DistanceOutOfBounds);
                state = State.DistanceOutOfBounds;
                break TINFLStatus.Failed;
            }

            apply_match(
                out_buf.get_mut(),
                l.dist_from_out_buf_start,
                l.dist,
                l.counter,
                out_buf_size_mask,
            );

            out_buf.set_position(l.dist_from_out_buf_start + l.counter);
        }
    } else TINFLStatus.Failed;

    local_vars.* = l;
    return FastResult{.status = status, .state = state};
}

pub const DecompressResult = struct {
    const Self = this;
    status: TINFLStatus,
    inpos: usize,
    outpos: usize,

    fn dump(self: *const Self) void {
        warn("{}: status={}, inpos={}, outpos={}", self, @enumToInt(self.status), self.inpos, self.outpos);
    }

    fn new(status: TINFLStatus, inpos: usize, outpos: usize) DecompressResult {
        return DecompressResult{.status = status, .inpos = inpos, .outpos = outpos};
    }
};

/// Main decompression function. Keeps decompressing data from `in_buf` until the in_buf is emtpy,
/// out_cur is full, the end of the deflate stream is hit, or there is an error in the deflate
/// stream.
///
/// # Arguments
///
/// `in_buf` is a reference to the compressed data that is to be decompressed. The decompressor will
/// start at the first byte of this buffer.
///
/// `out_cur` is a mutable cursor into the buffer that will store the decompressed data, and that
/// stores previously decompressed data if any.
/// * The position of the output cursor indicates where in the output buffer slice writing should
/// start.
/// * The decompression function normally needs access to 32KiB of the previously decompressed data
///(or to the beginning of the decompressed data if less than 32KiB has been decompressed.)
///     - If this data is not available, decompression may fail.
///     - Some deflate compressors allow specifying a window size which limits match distances to
/// less than this, or alternatively an RLE mode where matches will only refer to the previous byte
/// and thus allows a smaller output buffer. The window size can be specified in the zlib
/// header structure, however, the header data should not be relied on to be correct.
///
/// `flags`
/// Flags to indicate settings and status to the decompression function.
/// * The `TINFL_FLAG_HAS_MORE_INPUT` has to be specified if more compressed data is to be provided
/// in a subsequent call to this function.
/// * See the the [`inflate_flags`](inflate_flags/index.html) module for details on other flags.
///
/// # Returns
/// returns a tuple containing the status of the compressor, the number of input bytes read, and the
/// number of bytes output to `out_cur`.
/// Updates the position of `out_cur` to point to the next free spot in the output buffer.
///
/// This function shouldn't panic pending any bugs.
pub fn decompress(
    r: *Decompressor,
    in_buf: []u8,
    out_cur:  *Cursor([]u8),
    flags: u32,
) DecompressResult {
    const res = decompress_inner(r, in_buf, out_cur, flags);
    const new_pos = out_cur.position() + res.outpos;
    out_cur.set_position(new_pos);
    return res;
}

// A helper macro for generating the state machine.
//
// As Rust doesn't have fallthrough on matches, we have to return to the match statement
// and jump for each state change. (Which would ideally be optimized away, but often isn't.)
// macro_rules! generate_state {
//     ($state: ident, $state_machine: tt, $f: expr) => {
//         loop {
//             match $f {
//                 Action::None => continue,
//                 Action::Jump(new_state) => {
//                     $state = new_state;
//                     continue $state_machine;
//                 },
//                 Action::End(result) => break $state_machine result,
//             }
//         }
//     };
// }
/// This may never work, 8)
fn generate_state(state: var, state_machine: var, f: var) var {
    while (true) {
        switch(f) {
            Action.None => continue,
            Action.Jump => |new_state| {
                state = new_state;
                continue :state_machine;
            },
            Action.End => |result| break :state_machine result,
        }
    }
}

//#[inline]
fn decompress_inner(
    r: *Decompressor,
    in_buf: []u8,
    out_cur: *Cursor([]u8),
    flags: u32,
) DecompressResult {
    const out_buf_start_pos = out_cur.position();
    const out_buf_size_mask: usize = if ((flags & TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF) != 0) 
        @maxValue(usize)
    else 
        // In the case of zero len, any attempt to write would produce HasMoreOutput,
        // so to gracefully process the case of there really being no output,
        // set the mask to all zeros.
        out_cur.get_ref().len - 1; //.saturating_sub(1);
    

    // Ensure the output buffer's size is a power of 2, unless the output buffer
    // is large enough to hold the entire output file (in which case it doesn't
    // matter).
    // Also make sure that the output buffer position is not past the end of the output buffer.
    if ((((out_buf_size_mask +% 1) & out_buf_size_mask) != 0)  or
        (out_cur.position() > out_cur.get_ref().len)) {
        return DecompressResult.new(TINFLStatus.BadParam, 0, 0);
    }

    var in_iter = IterBuf{.buf = in_buf, .pos = 0}; //.iter();
    var state = r.state;
    var out_buf = OutputBuffer.from_slice_and_pos(out_cur.get_mut(), out_buf_start_pos);

    // TODO: Borrow instead of Copy
    var l = LocalVars {
        .bit_buf = r.bit_buf,
        .num_bits = r.num_bits,
        .dist = r.dist,
        .counter = r.counter,
        .num_extra = r.num_extra,
        .dist_from_out_buf_start = r.dist_from_out_buf_start,
    };

    var status = state_machine: while(true) {
        warn("state = {}\n", @enumToInt(state));
        switch (state) {
            State.Start => { // 0
                const action = while (true) {
                    l.bit_buf = 0;
                    l.num_bits = 0;
                    l.dist = 0;
                    l.counter = 0;
                    l.num_extra = 0;
                    r.z_header0 = 0;
                    r.z_header1 = 0;
                    r.z_adler32 = 1;
                    r.check_adler32 = 1;
                    if ((flags & TINFL_FLAG_PARSE_ZLIB_HEADER) != 0) {
                        break Action{.Jump = State.ReadZlibCmf};
                    } else {
                        break Action{.Jump = State.ReadBlockHeader};
                    }
                } else Action.None;
                switch (action) {
                    Action.None => continue,
                    Action.Jump => |new_state| {
                        state = new_state;
                        continue :state_machine;
                    },
                    Action.End => |result| break :state_machine result,
                }
            },

            State.ReadZlibCmf => { // 1
                const action = while (true) {
                    if (get_byte(&in_iter, flags)) |cmf| {
                        r.z_header0 = u32(cmf);
                        break Action{.Jump = State.ReadZlibFlg};
                    } else {
                        break end_of_input(flags);
                    }
                } else Action.None;
                switch (action) {
                    Action.None => continue,
                    Action.Jump => |new_state| {
                        state = new_state;
                        continue :state_machine;
                    },
                    Action.End => |result| break :state_machine result,
                }
            },

            State.ReadZlibFlg => { // 2
                const action = while (true) {
                    if (get_byte(&in_iter, flags)) |cmf| {
                        r.z_header1 = u32(cmf);
                        break validate_zlib_header(r.z_header0, r.z_header1, flags, out_buf_size_mask);
                    } else {
                        break end_of_input(flags);
                    }
                } else Action.None;
                switch (action) {
                    Action.None => continue,
                    Action.Jump => |new_state| {
                        state = new_state;
                        continue :state_machine;
                    },
                    Action.End => |result| break :state_machine result,
                }
            },

            // Read the block header and jump to the relevant section depending on the block type.
            State.ReadBlockHeader => { // 3
                if (get_bits(&l, 3, &in_iter, flags)) |bits| {
                    r.finish = @truncate(@typeOf(r.finish), (bits & 1));
                    r.block_type = @truncate(@typeOf(r.block_type), bits >> 1) & 3;
                    const action = while (true) {
                        switch (r.block_type) {
                            0 => break Action{.Jump = State.BlockTypeNoCompression},
                            1 => {
                                start_static_table(r);
                                break init_tree(r, &l);
                            },
                            2 => {l.counter = 0;
                                  break Action{.Jump = State.ReadTableSizes};
                            },
                            else => unreachable,
                        }
                    } else Action{.None = {}};
                    switch (action) {
                        Action.None => continue,
                        Action.Jump => |new_state| {
                            state = new_state;
                            continue :state_machine;
                        },
                        Action.End => |result| break :state_machine result,
                    }
                } else {
                    break :state_machine TINFLStatus.Failed;
                }
            },

            // // Raw/Stored/uncompressed block.
            // BlockTypeNoCompression => generate_state!(state, :state_machine, {
            //     pad_to_bytes(&mut l, &mut in_iter, flags, |l| {
            //         l.counter = 0;
            //         Action::Jump(RawHeader)
            //     })
            // }),
            State.BlockTypeNoCompression => unreachable,
            // // Check that the raw block header is correct.
            // RawHeader => generate_state!(state, :state_machine, {
            //     if l.counter < 4 {
            //         // Read block length and block length check.
            //         if l.num_bits != 0 {
            //             read_bits(&mut l, 8, &mut in_iter, flags, |l, bits| {
            //                 r.raw_header[l.counter as usize] = bits as u8;
            //                 l.counter += 1;
            //                 Action::None
            //             })
            //         } else {
            //             read_byte(&mut in_iter, flags, |byte| {
            //                 r.raw_header[l.counter as usize] = byte;
            //                 l.counter += 1;
            //                 Action::None
            //             })
            //         }
            //     } else {
            //         // Check if the length value of a raw block is correct.
            //         // The 2 first (2-byte) words in a raw header are the length and the
            //         // ones complement of the length.
            //         let length = r.raw_header[0] as u16 | ((r.raw_header[1] as u16) << 8);
            //         let check = r.raw_header[2] as u16 | ((r.raw_header[3] as u16) << 8);
            //         let valid = length == !check;
            //         l.counter = length.into();

            //         if !valid {
            //             Action::Jump(BadRawLength)
            //         } else if l.counter == 0 {
            //             // Empty raw block. Sometimes used for syncronization.
            //             Action::Jump(BlockDone)
            //         } else if l.num_bits != 0 {
            //             // There is some data in the bit buffer, so we need to write that first.
            //             Action::Jump(RawReadFirstByte)
            //         } else {
            //             // The bit buffer is empty, so memcpy the rest of the uncompressed data from
            //             // the block.
            //             Action::Jump(RawMemcpy1)
            //         }
            //     }
            // }),
            State.RawHeader => unreachable,
            // // Read the byte from the bit buffer.
            // RawReadFirstByte => generate_state!(state, :state_machine, {
            //     read_bits(&mut l, 8, &mut in_iter, flags, |l, bits| {
            //         l.dist = bits as u32;
            //         Action::Jump(RawStoreFirstByte)
            //     })
            // }),

            // // Write the byte we just read to the output buffer.
            // RawStoreFirstByte => generate_state!(state, :state_machine, {
            //     if out_buf.bytes_left() == 0 {
            //         Action::End(TINFLStatus::HasMoreOutput)
            //     } else {
            //         out_buf.write_byte(l.dist as u8);
            //         l.counter -= 1;
            //         if l.counter == 0 or l.num_bits == 0 {
            //             Action::Jump(RawMemcpy1)
            //         } else {
            //             // There is still some data left in the bit buffer that needs to be output.
            //             // TODO: Changed this to jump to `RawReadfirstbyte` rather than
            //             // `RawStoreFirstByte` as that seemed to be the correct path, but this
            //             // needs testing.
            //             Action::Jump(RawReadFirstByte)
            //         }
            //     }
            // }),
            State.RawStoreFirstByte => unreachable,

            // RawMemcpy1 => generate_state!(state, :state_machine, {
            //     if l.counter == 0 {
            //         Action::Jump(BlockDone)
            //     } else if out_buf.bytes_left() == 0 {
            //         Action::End(TINFLStatus::HasMoreOutput)
            //     } else {
            //         Action::Jump(RawMemcpy2)
            //     }
            // }),
            State.RawMemcpy1 => unreachable,

            // RawMemcpy2 => generate_state!(state, :state_machine, {
            //     if in_iter.len() > 0 {
            //         // Copy as many raw bytes as possible from the input to the output using memcpy.
            //         // Raw block lengths are limited to 64 * 1024, so casting through usize and u32
            //         // is not an issue.
            //         let space_left = out_buf.bytes_left();
            //         let bytes_to_copy = cmp::min(cmp::min(
            //             space_left,
            //             in_iter.len()),
            //             l.counter as usize
            //         );

            //         out_buf.write_slice(&in_iter.as_slice()[..bytes_to_copy]);

            //         (&mut in_iter).nth(bytes_to_copy - 1);
            //         l.counter -= bytes_to_copy as u32;
            //         Action::Jump(RawMemcpy1)
            //     } else {
            //         end_of_input(flags)
            //     }
            // }),
            State.RawMemcpy2 => unreachable,

            // Read how many huffman codes/symbols are used for each table.
            State.ReadTableSizes => {
                const action = while (true) {
                    if (l.counter < 3) {
                        const num_bits = ([]u32 {5, 5, 4})[l.counter];
                        if (get_bits(&l, num_bits, &in_iter, flags)) |bits| {
                            r.table_sizes[l.counter] = @truncate(u32, bits) + MIN_TABLE_SIZES[l.counter];
                            l.counter += 1;
                            break Action{.None = {}};
                        } else {
                            break :state_machine TINFLStatus.Failed;
                        }
                    } else {
                        setmem(u8, r.tables[HUFFLEN_TABLE].code_size[0..], 0);
                        l.counter = 0;
                        break Action{.Jump = State.ReadHufflenTableCodeSize};
                    }
                } else Action {.None = {}};
                switch (action) {
                    Action.None => continue,
                    Action.Jump => |new_state| {
                        state = new_state;
                        continue :state_machine;
                    },
                    Action.End => |result| break :state_machine result,
                }
            },

            // Read the 3-bit lengths of the huffman codes describing the huffman code lengths used
            // to decode the lengths of the main tables.
            State.ReadHufflenTableCodeSize => {
                const action = while (true) {
                    if (l.counter < r.table_sizes[HUFFLEN_TABLE]) {
                        if (get_bits(&l, 3, &in_iter, flags)) |bits| {
                            // These lengths are not stored in a normal ascending order, but rather one
                            // specified by the deflate specification intended to put the most used
                            // values at the front as trailing zero lengths do not have to be stored.
                            r.tables[HUFFLEN_TABLE]
                                .code_size[HUFFMAN_LENGTH_ORDER[l.counter]]
                                = @truncate(u8, bits);
                            l.counter += 1;
                            break Action{.None = {}};
                        } else {
                            break :state_machine TINFLStatus.Failed;
                        }
                    } else {
                        r.table_sizes[HUFFLEN_TABLE] = 19;
                        break init_tree(r, &l);
                    }
                } else Action {.None = {}};
                switch (action) {
                    Action.None => continue,
                    Action.Jump => |new_state| {
                        state = new_state;
                        continue :state_machine;
                    },
                    Action.End => |result| break :state_machine result,
                }
            },

            State.ReadLitlenDistTablesCodeSize => {
                const action = while (true) {
                    if (l.counter < (r.table_sizes[LITLEN_TABLE] + r.table_sizes[DIST_TABLE])) {
                        const aos = decode_huffman_code(r, &l, HUFFLEN_TABLE, flags, &in_iter);
                        switch (aos) {
                            ActionOrSymbol.AOSAction => |a| break a,
                            ActionOrSymbol.AOSSymbol => |s| {
                                l.dist = @bitCast(u32, s);
                                if (l.dist < 16) {
                                    r.len_codes[l.counter] = @truncate(u8, l.dist);
                                    l.counter += 1;
                                    break Action{.None = {}};
                                } else if ((l.dist == 16) and (l.counter == 0)) {
                                    break Action{.Jump = State.BadCodeSizeDistPrevLookup};
                                } else {
                                    l.num_extra = ([]u32{2, 3, 7})[l.dist - 16];
                                    break Action{.Jump = State.ReadExtraBitsCodeSize};
                                }
                            },
                            else => unreachable,
                        }
                    } else if (l.counter != (r.table_sizes[LITLEN_TABLE] + r.table_sizes[DIST_TABLE])) {
                        break Action{.Jump = State.BadCodeSizeSum};
                    } else {
                        //           r.tables[LITLEN_TABLE].code_size[..r.table_sizes[LITLEN_TABLE] as usize]
                        //             .copy_from_slice(&r.len_codes[..r.table_sizes[LITLEN_TABLE] as usize]);
                        for (r.len_codes[0..r.table_sizes[LITLEN_TABLE]]) |v, ii| {
                            r.tables[LITLEN_TABLE].code_size[ii] = v;
                        }

                        const dist_table_start = r.table_sizes[LITLEN_TABLE];
                        const dist_table_end = (r.table_sizes[LITLEN_TABLE] + r.table_sizes[DIST_TABLE]);
                        //         r.tables[DIST_TABLE].code_size[..r.table_sizes[DIST_TABLE] as usize]
                        //             .copy_from_slice(&r.len_codes[dist_table_start..dist_table_end]);
                        for (r.len_codes[dist_table_start..dist_table_end]) |v, ii| {
                            r.tables[DIST_TABLE].code_size[ii] = v;
                        }
                        r.block_type -= 1;
                        break init_tree(r, &l);
                    }
                } else Action {.None = {}};
                switch (action) {
                    Action.None => continue,
                    Action.Jump => |new_state| {
                        state = new_state;
                        continue :state_machine;
                    },
                    Action.End => |result| break :state_machine result,
                }
            },

            State.ReadExtraBitsCodeSize => {
                const action = while (true) {
                    const num_extra = l.num_extra;
                    if (get_bits(&l, num_extra, &in_iter, flags)) |bits| {
                        var extra_bits = @truncate(u32, bits);
                        // Mask to avoid a bounds check.
                        extra_bits += ([]u32{3, 3, 11})[(l.dist - 16) & 3];
                        const val = if (l.dist == 16) r.len_codes[l.counter - 1] else 0;
                        setmem(@typeOf(r.len_codes[0]), r.len_codes[l.counter..l.counter + extra_bits], val);
                        l.counter += extra_bits;
                        break Action{.Jump = State.ReadLitlenDistTablesCodeSize};
                    } else {
                        break :state_machine TINFLStatus.Failed;
                    }
                } else Action {.None = {}};
                switch (action) {
                    Action.None => continue,
                    Action.Jump => |new_state| {
                        state = new_state;
                        continue :state_machine;
                    },
                    Action.End => |result| break :state_machine result,
                }
            },
            State.DecodeLitlen => { // 12
                // DecodeLitlen => generate_state!(state, :state_machine, {
                warn("in={}, out={}\n", in_iter.len(), out_buf.bytes_left());
                const action = while (true) {
                    if ((in_iter.len() < 4) or (out_buf.bytes_left() < 2)) {
                        warn("case 1\n");
                        // See if we can decode a literal with the data we have left.
                        // Jumps to next state (WriteSymbol) if successful.
                        const symbol = decode_huffman_code(r, &l, LITLEN_TABLE, flags, &in_iter);
                        symbol.dump();
                        switch (symbol) {
                            ActionOrSymbol.AOSAction => |a| break a,
                            ActionOrSymbol.AOSSymbol => |s| {
                                l.counter = @bitCast(u32, s);
                                break Action{.Jump = State.WriteSymbol};
                            },
                            else => unreachable,
                        }
                    } else if (out_buf.bytes_left() >= 259 and in_iter.len() >= 14) {
                        // There is enough space, use the fast inner decompression
                        // function.
                        warn("case 2\n");
                        const res = decompress_fast(
                            r,
                            &in_iter,
                            &out_buf,
                            flags,
                            &l,
                            out_buf_size_mask,
                        );

                        state = res.state;
                        if (res.status == TINFLStatus.Done) {
                            break Action{.Jump = res.state};
                        } else {
                            break Action{.End = res.status};
                        }
                    } else {
                        warn("case 3\n");
                        fill_bit_buffer(&l, &in_iter);

                        if (r.tables[LITLEN_TABLE].lookup(l.bit_buf)) |res| {
                            res.dump();
                            l.counter = @bitCast(u32, res.symbol);
                            l.bit_buf >>= @truncate(u6, res.code_length);
                            l.num_bits -= res.code_length;

                            if ((l.counter & 256) != 0) {
                                // The symbol is not a literal.
                                break Action{.Jump = State.HuffDecodeOuterLoop1};
                            } else {
                                // If we have a 32-bit buffer we need to read another two bytes now
                                // to have enough bits to keep going.
                                if (!is_64bit) {
                                    fill_bit_buffer(&l, &in_iter);
                                }

                                if (r.tables[LITLEN_TABLE].lookup(l.bit_buf)) |res1| {
                                    res1.dump();
                                    const symbol = @bitCast(u32, res1.symbol);
                                    l.bit_buf >>= @truncate(u6, res1.code_length);
                                    l.num_bits -= res1.code_length;
                                    // The previous symbol was a literal, so write it directly and check
                                    // the next one.
                                    out_buf.write_byte(@truncate(u8, l.counter));
                                    if ((symbol & 256) != 0) {
                                        l.counter = symbol;
                                        // The symbol is a length value.
                                        break Action{.Jump = State.HuffDecodeOuterLoop1};
                                    } else {
                                        // The symbol is a literal, so write it directly and continue.
                                        out_buf.write_byte(@truncate(u8, symbol));
                                        break Action{.None = {}};
                                    }
                                } else {
                                    break Action{.Jump = State.InvalidCodeLen};
                                }
                            }
                        } else {
                            break Action{.Jump = State.InvalidCodeLen};
                        }
                    }
                } else Action{.None = {}};
                switch (action) {
                    Action.None => continue,
                    Action.Jump => |new_state| {
                        state = new_state;
                        continue :state_machine;
                    },
                    Action.End => |result| break :state_machine result,
                }
            },

            State.WriteSymbol => { // 13
                const action = while (true) {
                    if (l.counter >= 256) {
                        break Action{.Jump = State.HuffDecodeOuterLoop1};
                    } else if (out_buf.bytes_left() > 0) {
                        out_buf.write_byte(@truncate(u8, l.counter));
                        break Action{.Jump = State.DecodeLitlen};
                    } else {
                        break Action{.End = TINFLStatus.HasMoreOutput};
                    }
                } else Action.None;
                switch (action) {
                    Action.None => continue,
                    Action.Jump => |new_state| {
                        state = new_state;
                        continue :state_machine;
                    },
                    Action.End => |result| break :state_machine result,
                }
            },

            State.HuffDecodeOuterLoop1 => {
                const action = while (true) {
                    l.counter &= 511;
                    if (l.counter == 256) {
                        // We hit the end of block symbol.
                        break Action{.Jump = State.BlockDone};
                    } else if (l.counter > 285) {
                        // Invalid code.
                        // We already verified earlier that the code is > 256.
                        break Action{.Jump = State.InvalidLitlen};
                    } else {
                        // # Optimization
                        // Mask the value to avoid bounds checks
                        // We could use get_unchecked later if can statically verify that
                        // this will never go out of bounds.
                        l.num_extra = LENGTH_EXTRA[(l.counter - 257) & BASE_EXTRA_MASK];
                        l.counter = LENGTH_BASE[(l.counter - 257) & BASE_EXTRA_MASK];
                        // Length and distance codes have a number of extra bits depending on
                        // the base, which together with the base gives us the exact value.
                        if (l.num_extra != 0) {
                            break Action{.Jump = State.ReadExtraBitsLitlen};
                        } else {
                            break Action{.Jump = State.DecodeDistance};
                        }
                    }
                } else Action.None;
                switch (action) {
                    Action.None => continue,
                    Action.Jump => |new_state| {
                        state = new_state;
                        continue :state_machine;
                    },
                    Action.End => |result| break :state_machine result,
                }
            },

            State.ReadExtraBitsLitlen => {
                const action = while (true) {
                    const num_extra = l.num_extra;
                    if (get_bits(&l, num_extra, &in_iter, flags)) |bits| {
                        l.counter += @truncate(u32, bits);
                        break Action{.Jump = State.DecodeDistance};
                    } else {
                        break :state_machine TINFLStatus.Failed;
                    }
                } else Action.None;
                switch (action) {
                    Action.None => continue,
                    Action.Jump => |new_state| {
                        state = new_state;
                        continue :state_machine;
                    },
                    Action.End => |result| break :state_machine result,
                }
            },

            State.DecodeDistance => {
                const action = while (true) {
                    // Try to read a huffman code from the input buffer and look up what
                    // length code the decoded symbol refers to.
                    const sym = decode_huffman_code(r, &l, DIST_TABLE, flags, &in_iter);
                    switch (sym) {
                        ActionOrSymbol.AOSAction => |a| break a,
                        ActionOrSymbol.AOSSymbol => |symbol| {
                            if (symbol > 29) {
                                // Invalid distance code.
                                break Action{.Jump = State.InvalidDist};
                            }
                            // # Optimization
                            // Mask the value to avoid bounds checks
                            // We could use get_unchecked later if can statically verify that
                            // this will never go out of bounds.
                            const usymbol = @bitCast(u32, symbol);
                            l.num_extra = DIST_EXTRA[usymbol & BASE_EXTRA_MASK];
                            l.dist = DIST_BASE[usymbol & BASE_EXTRA_MASK];
                            if (l.num_extra != 0) {
                                // ReadEXTRA_BITS_DISTACNE
                                break Action{.Jump = State.ReadExtraBitsDistance};
                            } else {
                                break Action{.Jump = State.HuffDecodeOuterLoop2};
                            }
                        },
                        else => unreachable,
                    }
                } else Action{.None = {}};
                switch (action) {
                    Action.None => continue,
                    Action.Jump => |new_state| {
                        state = new_state;
                        continue :state_machine;
                    },
                    Action.End => |result| break :state_machine result,
                }
            },

            State.ReadExtraBitsDistance => {
                l.dump();
                const action = while (true) {
                    const num_extra = l.num_extra;
                    if (get_bits(&l, num_extra, &in_iter, flags)) |bits| {
                        l.dist += @truncate(u32, bits);
                        break Action{.Jump = State.HuffDecodeOuterLoop2};
                    } else {
                        break :state_machine TINFLStatus.Failed;
                    }
                } else Action{.None = {}};
                switch (action) {
                    Action.None => continue,
                    Action.Jump => |new_state| {
                        state = new_state;
                        continue :state_machine;
                    },
                    Action.End => |result| break :state_machine result,
                }
            },

            State.HuffDecodeOuterLoop2 => { // 22
                const action = while (true) {
                    l.dist_from_out_buf_start = out_buf.position();
                    if ((l.dist > l.dist_from_out_buf_start) and
                        ((flags & TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF) != 0))
                    {
                        // We encountered a distance that refers a position before
                        // the start of the decoded data, so we can't continue.
                        break Action{.Jump = State.DistanceOutOfBounds};
                    } else {
                        var out_pos = out_buf.position();
                        var source_pos = (l.dist_from_out_buf_start -% l.dist) & out_buf_size_mask;
                        //.wrapping_sub(l.dist as usize) & out_buf_size_mask;

                        const out_len = out_buf.get_ref().len;
                        const match_end_pos = out_buf.position() + l.counter;

                        if ((match_end_pos > out_len) or
                        // miniz doesn't do this check here. Not sure how it makes sure
                        // that this case doesn't happen.
                            ((source_pos >= out_pos) and ((source_pos - out_pos) < l.counter)))
                        {
                            // Not enough space for all of the data in the output buffer,
                            // so copy what we have space for.
                            if (l.counter == 0) {
                                break Action{.Jump = State.DecodeLitlen};
                            } else {
                                break Action{.Jump = State.WriteLenBytesToEnd};
                            }
                        } else {
                            apply_match(
                                out_buf.get_mut(),
                                out_pos,
                                l.dist,
                                l.counter,
                                out_buf_size_mask
                            );
                            out_buf.set_position(out_pos + l.counter);
                            break Action{.Jump = State.DecodeLitlen};
                        }
                    }
                } else Action {.None = {}};
                switch (action) {
                    Action.None => continue,
                    Action.Jump => |new_state| {
                        state = new_state;
                        continue :state_machine;
                    },
                    Action.End => |result| break :state_machine result,
                }
            },

            // WriteLenBytesToEnd => generate_state!(state, :state_machine, {
            //     if out_buf.bytes_left() > 0 {
            //         let source_pos = l.dist_from_out_buf_start
            //             .wrapping_sub(l.dist as usize) & out_buf_size_mask;
            //         let out_pos = out_buf.position();

            //         let len = cmp::min(out_buf.bytes_left(), l.counter as usize);
            //         transfer(out_buf.get_mut(), source_pos, out_pos, len, out_buf_size_mask);

            //         l.dist_from_out_buf_start += len;
            //         out_buf.set_position(out_pos + len);
            //         l.counter -= len as u32;
            //         if l.counter == 0 {
            //             Action::Jump(DecodeLitlen)
            //         } else {
            //             Action::None
            //         }
            //     } else {
            //         Action::End(TINFLStatus::HasMoreOutput)
            //     }
            // }),
            State.WriteLenBytesToEnd => unreachable,
            State.BlockDone => { // 20
                const action = while (true) {
                    // End once we've read the last block.
                    if (r.finish != 0) {
                        if (get_bits(&l, l.num_bits & 7, &in_iter, flags)) |bits| {
                            const in_consumed = in_buf.len - in_iter.len();
                            const undo = undo_bytes(&l, @truncate(u32, in_consumed));
                            in_iter = IterBuf{.buf = in_buf[in_consumed - undo..], .pos = 0};
                            in_iter.dump();
                            l.bit_buf &= ((BitBuffer(1) << l.shift()) - 1);
                            //assert(l.num_bits == 0);
                            //in_buf[in_consumed - undo..].iter();
                        } else {
                            break Action {.None = {}};
                        }
                        if (flags & TINFL_FLAG_PARSE_ZLIB_HEADER != 0) {
                            l.counter = 0;
                            break Action{.Jump = State.ReadAdler32};
                        } else {
                            break Action{.Jump = State.DoneForever};
                        }
                    } else {
                        break Action{.Jump = State.ReadBlockHeader};
                    }
                } else Action {.None = {}};
                switch (action) {
                    Action.None => continue,
                    Action.Jump => |new_state| {
                        state = new_state;
                        continue :state_machine;
                    },
                    Action.End => |result| break :state_machine result,
                }
            },
            State.ReadAdler32 => {
                const action = while (true) {
                    l.dump();
                    if (l.counter < 4) {
                        if (l.num_bits != 0) {
                             if (get_bits(&l, 8, &in_iter, flags)) |bits| {
                                 r.z_adler32 <<= 8;
                                 r.z_adler32 |= @truncate(u8, bits);
                                 l.counter += 1;
                                 break Action{.None = {}};
                             }
                            break :state_machine TINFLStatus.Failed;
                        } else {
                            if (get_byte(&in_iter, flags)) |byte| {
                                r.z_adler32 <<= 8;
                                r.z_adler32 |= byte;
                                l.counter += 1;
                                break  Action{.None = {}};
                            }
                            break end_of_input(flags);
                        }
                    }
                    break Action{.Jump = State.DoneForever};
                } else Action.None;
                switch (action) {
                    Action.None => continue,
                    Action.Jump => |new_state| {
                        state = new_state;
                        continue :state_machine;
                    },
                    Action.End => |result| break :state_machine result,
                }
            },
            // We are done.
            State.DoneForever => break :state_machine TINFLStatus.Done,

            // Anything else indicates failure.
            // BadZlibHeader | BadRawLength | BlockTypeUnexpected | DistanceOutOfBounds |
            // BadTotalSymbols | BadCodeSizeDistPrevLookup | BadCodeSizeSum | InvalidLitlen |
            // InvalidDist | InvalidCodeLen
            else => break :state_machine TINFLStatus.Failed,
        }
    } else TINFLStatus.Failed;

    const in_undo = if ((status != TINFLStatus.NeedsMoreInput) and
        (status != TINFLStatus.FailedCannotMakeProgress))
        undo_bytes(&l, @truncate(u32, in_buf.len - in_iter.len()))
    else
        0;

    r.state = state;
    r.bit_buf = l.bit_buf;
    r.num_bits = l.num_bits;
    r.dist = l.dist;
    r.counter = l.counter;
    r.num_extra = l.num_extra;
    r.dist_from_out_buf_start = l.dist_from_out_buf_start;

    r.bit_buf &= ((BitBuffer(1) << @truncate(u5, r.num_bits)) - 1);

    // If this is a zlib stream, and update the adler32 checksum with the decompressed bytes if
    // requested.
    const need_adler = (flags & (TINFL_FLAG_PARSE_ZLIB_HEADER | TINFL_FLAG_COMPUTE_ADLER32) != 0);
    if (need_adler and (@enumToInt(status) >= 0)) {
        const out_buf_pos = out_buf.position();
        warn("Checking adler32, {} to {}\n", out_buf_start_pos, out_buf_pos);
        r.check_adler32 = adler32(
            r.check_adler32,
            out_buf.get_ref()[out_buf_start_pos..out_buf_pos],
        );
        warn("adler32={x08}, {x08}\n", r.check_adler32, r.z_adler32);

        // Once we are done, check if the checksum matches with the one provided in the zlib header.
        if ((status == TINFLStatus.Done) and (flags & TINFL_FLAG_PARSE_ZLIB_HEADER != 0) and
            (r.check_adler32 != r.z_adler32))
        {
            status = TINFLStatus.Adler32Mismatch;
        }
    }

    // NOTE: Status here and in miniz_tester doesn't seem to match.
    return DecompressResult.new(
        status,
        in_buf.len - in_iter.len() - in_undo,
        out_buf.position() - out_buf_start_pos,
    );
}

test "Decompress.dummy" {
    assert(false == false);
}

test "Decompress.decompressor.one" {
    var d = Decompressor.new();
    var input = "\x78\x01\x73\x49\x4d\xcb\x49\x2c\x49\x55\x00\x11\x5c\x00\x21\x33\x04\x86";
    var expected = "Deflate late\n";
    var output = []u8 {0} ** 1024;
    var c = Cursor([]u8){.pos= 0, .inner = output[0..]};
    var res = decompress(&d, input[0..], &c, TINFL_FLAG_PARSE_ZLIB_HEADER | TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF);
    res.dump();
    if (res.outpos < 128) {
        warn("\n\n**  output='{}'\n", output[0..res.outpos]);
        if (mem.eql(u8, expected, output[0..res.outpos])) {
            warn("WHAT? Result is as expected\n");
        }
    }
    if (res.status == TINFLStatus.Done and res.outpos > 0) {
        assert(mem.eql(u8, expected, output[0..res.outpos]));
    }
}

test "Decompress.decompressor.two" {
    var d = Decompressor.new();
    var input = "\x78\x01\xa5\xc7\xa1\x0d\x00\x00\x08\x03\x30\xcf\x15\x1c\xb3\x47\x10\x43\x21\x91\x1c\x4f\x76\xc3\x4c\x93\x82\x3d\xb5\x4c\x71\x30\x13\x0f\x91\xcd\x1d\x59";
    var expected = "Deflate late|Deflate late|Deflate late|Deflate late|Deflate late|Deflate late\n";
    var output = []u8 {0} ** 1024;
    var c = Cursor([]u8){.pos= 0, .inner = output[0..]};
    var res = decompress(&d, input[0..], &c, TINFL_FLAG_PARSE_ZLIB_HEADER | TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF);
    res.dump();
    if (res.outpos < 128) {
        warn("\n\n**  output='{}'\n", output[0..res.outpos]);
        if (mem.eql(u8, expected, output[0..res.outpos])) {
            warn("WHAT? Result is as expected\n");
        }
    }
    if (res.status == TINFLStatus.Done and res.outpos > 0) {
        assert(mem.eql(u8, expected, output[0..res.outpos]));
    }
}

test "Decompress.decompressor.dynamic" {
    var d = Decompressor.new();
    var input = "\x78\x01\xa5\xc7\xa1\x0d\x00\x00\x08\x03\x30\xcf\x15\x1c\xb3\x47\x10\x43\x21\x91\x1c\x4f\x76\xc3\x4c\x93\x82\x3d\xb5\x4c\x71\x30\x13\x0f\x91\xcd\x1d\x59";
    var expected = "Deflate late|Deflate late|Deflate late|Deflate late|Deflate late|Deflate late\n";
    var output = []u8 {0} ** 1024;
    var c = Cursor([]u8){.pos= 0, .inner = output[0..]};
    var res = decompress(&d, input[0..], &c, TINFL_FLAG_PARSE_ZLIB_HEADER | TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF);
    res.dump();
    if (res.outpos < 128) {
        warn("\n\n**  output='{}'\n", output[0..res.outpos]);
        if (mem.eql(u8, expected, output[0..res.outpos])) {
            warn("WHAT? Result is as expected\n");
        }
    }
    if (res.status == TINFLStatus.Done and res.outpos > 0) {
        assert(mem.eql(u8, expected, output[0..res.outpos]));
    }
}

// #[cfg(test)]
// mod test {
//     use super::*;
//     //use std::io::Cursor;

//     //TODO: Fix these.

//     fn tinfl_decompress_oxide<'i>(
//         r: &mut Decompressor,
//         input_buffer: &'i [u8],
//         output_buffer: &mut [u8],
//         flags: u32,
//     ) -> (TINFLStatus, &'i [u8], usize) {
//         let (status, in_pos, out_pos) =
//             decompress(r, input_buffer, &mut Cursor::new(output_buffer), flags);
//         (status, &input_buffer[in_pos..], out_pos)
//     }

//     #[test]
//     fn decompress_zlib() {
//         let encoded = [
//             120, 156, 243, 72, 205, 201, 201, 215, 81, 168,
//             202, 201,  76,  82,  4,   0,  27, 101,  4,  19,
//         ];
//         let flags = TINFL_FLAG_COMPUTE_ADLER32 | TINFL_FLAG_PARSE_ZLIB_HEADER;

//         let mut b = Decompressor::new();
//         const LEN: usize = 32;
//         let mut b_buf = vec![0; LEN];

//         // This should fail with the out buffer being to small.
//         let b_status = tinfl_decompress_oxide(&mut b, &encoded[..], b_buf.as_mut_slice(), flags);

//         assert_eq!(b_status.0, TINFLStatus::Failed);

//         let flags = flags | TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF;

//         b = Decompressor::new();

//         // With TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF set this should no longer fail.
//         let b_status = tinfl_decompress_oxide(&mut b, &encoded[..], b_buf.as_mut_slice(), flags);

//         assert_eq!(b_buf[..b_status.2], b"Hello, zlib!"[..]);
//         assert_eq!(b_status.0, TINFLStatus::Done);
//     }

//     #[test]
//     fn raw_block() {
//         const LEN: usize = 64;

//         let text = b"Hello, zlib!";
//         let encoded = {
//             let len = text.len();
//             let notlen = !len;
//             let mut encoded =
//                 vec![1, len as u8, (len >> 8) as u8, notlen as u8, (notlen >> 8) as u8];
//             encoded.extend_from_slice(&text[..]);
//             encoded
//         };

//         //let flags = TINFL_FLAG_COMPUTE_ADLER32 | TINFL_FLAG_PARSE_ZLIB_HEADER |
//         let flags = TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF;

//         let mut b = Decompressor::new();

//         let mut b_buf = vec![0; LEN];

//         let b_status = tinfl_decompress_oxide(&mut b, &encoded[..], b_buf.as_mut_slice(), flags);
//         assert_eq!(b_buf[..b_status.2], text[..]);
//         assert_eq!(b_status.0, TINFLStatus::Done);
//     }

//     fn masked_lookup(table: &HuffmanTable, bit_buf: BitBuffer) -> (i32, u32) {
//         let ret = table.lookup(bit_buf).unwrap();
//         (ret.0 & 511, ret.1)
//     }

//     #[test]
//     fn fixed_table_lookup() {
//         let mut d = Decompressor::new();
//         d.block_type = 1;
//         start_static_table(&mut d);
//         let mut l = LocalVars {
//             bit_buf: d.bit_buf,
//             num_bits: d.num_bits,
//             dist: d.dist,
//             counter: d.counter,
//             num_extra: d.num_extra,
//             dist_from_out_buf_start: d.dist_from_out_buf_start,
//         };
//         init_tree(&mut d, &mut l);
//         let llt = &d.tables[LITLEN_TABLE];
//         let dt = &d.tables[DIST_TABLE];
//         assert_eq!(masked_lookup(llt, 0b00001100), (0, 8));
//         assert_eq!(masked_lookup(llt, 0b00011110), (72, 8));
//         assert_eq!(masked_lookup(llt, 0b01011110), (74, 8));
//         assert_eq!(masked_lookup(llt, 0b11111101), (143, 8));
//         assert_eq!(masked_lookup(llt, 0b000010011), (144, 9));
//         assert_eq!(masked_lookup(llt, 0b111111111), (255, 9));
//         assert_eq!(masked_lookup(llt, 0b00000000), (256, 7));
//         assert_eq!(masked_lookup(llt, 0b1110100), (279, 7));
//         assert_eq!(masked_lookup(llt, 0b00000011), (280, 8));
//         assert_eq!(masked_lookup(llt, 0b11100011), (287, 8));

//         assert_eq!(masked_lookup(dt, 0), (0, 5));
//         assert_eq!(masked_lookup(dt, 20), (5, 5));
//     }

//     fn check_result(input: &[u8], expected_status: TINFLStatus, expected_state: State, zlib: bool) {
//         let mut r = unsafe { Decompressor::with_init_state_only() };
//         let mut output_buf = vec![0; 1024 * 32];
//         let mut out_cursor = Cursor::new(output_buf.as_mut_slice());
//         let flags = if zlib {
//             inflate_flags::TINFL_FLAG_PARSE_ZLIB_HEADER
//         } else {
//             0
//         } | TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF | TINFL_FLAG_HAS_MORE_INPUT;
//         let (d_status, _in_bytes, _out_bytes) =
//             decompress(&mut r, input, &mut out_cursor, flags);
//         assert_eq!(expected_status, d_status);
//         assert_eq!(expected_state, r.state);
//     }

//     #[test]
//     fn bogus_input() {
//         use self::check_result as cr;
//         const F: TINFLStatus = TINFLStatus::Failed;
//         const OK: TINFLStatus = TINFLStatus::Done;
//         // Bad CM.
//         cr(&[0x77, 0x85], F, State::BadZlibHeader, true);
//         // Bad window size (but check is correct).
//         cr(&[0x88, 0x98], F, State::BadZlibHeader, true);
//         // Bad check bits.
//         cr(&[0x78, 0x98], F, State::BadZlibHeader, true);

//         // Too many code lengths. (From inflate library issues)
//         cr(
//             b"M\xff\xffM*\xad\xad\xad\xad\xad\xad\xad\xcd\xcd\xcdM",
//             F,
//             State::BadTotalSymbols,
//             false,
//         );
//         // Bad CLEN (also from inflate library issues)
//         cr(
//             b"\xdd\xff\xff*M\x94ffffffffff",
//             F,
//             State::BadTotalSymbols,
//             false,
//         );

//         // Port of inflate coverage tests from zlib-ng
//         // https://github.com/Dead2/zlib-ng/blob/develop/test/infcover.c
//         let c = |a, b, c| cr(a, b, c, false);

//         // Invalid uncompressed/raw block length.
//         c(&[0,0,0,0,0], F, State::BadRawLength);
//         // Ok empty uncompressed block.
//         c(&[3, 0], OK, State::DoneForever);
//         // Invalid block type.
//         c(&[6], F, State::BlockTypeUnexpected);
//         // Ok uncompressed block.
//         c(&[1, 1, 0, 0xfe, 0xff, 0], OK, State::DoneForever);
//         // Too many litlens, we handle this later than zlib, so this test won't
//         // give the same result.
//         //        c(&[0xfc, 0, 0], F, State::BadTotalSymbols);
//         // Invalid set of code lengths - TODO Check if this is the correct error for this.
//         c(&[4, 0, 0xfe, 0xff], F, State::BadTotalSymbols);
//         // Invalid repeat in list of code lengths.
//         // (Try to repeat a non-existant code.)
//         c(&[4, 0, 0x24, 0x49, 0], F, State::BadCodeSizeDistPrevLookup);
//         // Missing end of block code (should we have a separate error for this?) - fails on futher input
//         //    c(&[4, 0, 0x24, 0xe9, 0xff, 0x6d], F, State::BadTotalSymbols);
//         // Invalid set of literals/lengths
//         c(&[4, 0x80, 0x49, 0x92, 0x24, 0x49, 0x92, 0x24, 0x71, 0xff, 0xff, 0x93, 0x11, 0], F, State::BadTotalSymbols);
//         // Invalid set of distances _ needsmoreinput
//         // c(&[4, 0x80, 0x49, 0x92, 0x24, 0x49, 0x92, 0x24, 0x0f, 0xb4, 0xff, 0xff, 0xc3, 0x84], F, State::BadTotalSymbols);
//         // Invalid distance code
//         c(&[2, 0x7e, 0xff, 0xff], F, State::InvalidDist);

//         // Distance refers to position before the start
//         c(&[0x0c, 0xc0 ,0x81 ,0, 0, 0, 0, 0, 0x90, 0xff, 0x6b, 0x4, 0], F, State::DistanceOutOfBounds);

//         // Trailer
//         // Bad gzip trailer checksum GZip header not handled by miniz_oxide
//         //cr(&[0x1f, 0x8b, 0x08 ,0 ,0 ,0 ,0 ,0 ,0 ,0 ,0x03, 0, 0, 0, 0, 0x01], F, State::BadCRC, false)
//         // Bad gzip trailer length
//         //cr(&[0x1f, 0x8b, 0x08 ,0 ,0 ,0 ,0 ,0 ,0 ,0 ,0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0x01], F, State::BadCRC, false)
//     }

//     #[test]
//     fn empty_output_buffer_non_wrapping() {
//         let encoded = [
//             120, 156, 243, 72, 205, 201, 201, 215, 81, 168,
//             202, 201,  76, 82,   4,   0,  27, 101,  4,  19,
//         ];
//         let flags = TINFL_FLAG_COMPUTE_ADLER32 |
//             TINFL_FLAG_PARSE_ZLIB_HEADER |
//             TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF;
//         let mut r = Decompressor::new();
//         let mut output_buf = vec![];
//         let mut out_cursor = Cursor::new(output_buf.as_mut_slice());
//         // Check that we handle an empty buffer properly and not panicking.
//         // https://github.com/Frommi/miniz_oxide/issues/23
//         let res = decompress(&mut r, &encoded, &mut out_cursor, flags);
//         assert_eq!(res, (TINFLStatus::HasMoreOutput, 4, 0));
//     }

//     #[test]
//     fn empty_output_buffer_wrapping() {
//         let encoded =  [
//             0x73, 0x49, 0x4d, 0xcb,
//             0x49, 0x2c, 0x49, 0x55,
//             0x00, 0x11, 0x00
//         ];
//         let flags = TINFL_FLAG_COMPUTE_ADLER32;
//         let mut r = Decompressor::new();
//         let mut output_buf = vec![];
//         let mut out_cursor = Cursor::new(output_buf.as_mut_slice());
//         // Check that we handle an empty buffer properly and not panicking.
//         // https://github.com/Frommi/miniz_oxide/issues/23
//         let res = decompress(&mut r, &encoded, &mut out_cursor, flags);
//         assert_eq!(res, (TINFLStatus::HasMoreOutput, 2, 0));
//     }
// }
