// -*- zig -*-
// Based on https://github.com/gendx/lzma-rs
// License: MIT (see the LICENSE file)

const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;

// XZ section, to go elsewhere...
pub const XZ_MAGIC_HEADER = [_]u8 {0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00};
pub const XZ_MAGIC_FOOTER = [_]u8 {0x59, 0x5A};

pub const CheckMethod = enum(u8) {
    None   = 0x00,
    CRC32  = 0x01,
    CRC64  = 0x04,
    SHA256 = 0x0A,
};

pub const CrcType = union(CheckMethod) {
    None: void,
    CRC32: u32,
    CRC64: u64,
    SHA256: [32]u8,
};

pub fn read_multibyte_int(input: []u8, consumed: *usize) !usize {
    var result: usize = 0;
    var cnt: u32 = 0;

    consumed.* = 0;
    while (cnt < 9) : (cnt += 1) {
        // need range check?
        const byte = input[cnt];
        result ^= usize(byte & 0x7F) << @truncate(u6, cnt * 7);
        if ((byte & 0x80) == 0) {
            consumed.* = cnt + 1;

            return result;
        }
    }

    return error.InvalidMultiByte;
}
