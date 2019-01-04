// -*- mode: zig; -*-
/// A wrapper for the output slice used when decompressing.
///
/// Using this rather than `Cursor` lets us implement the writing methods directly on
/// the buffer and lets us use a usize rather than u64 for the position which helps with
/// performance on 32-bit systems.

const deriveDebug = @import("mzutil.zig").deriveDebug;

pub const OutputBuffer = struct {
    const Self = @This();
    slice: []u8,
    pos: usize,

    pub fn format(
        self: *const Self,
        comptime fmt: []const u8,
        context: var,
        comptime Errors: type,
        output: fn (@typeOf(context), []const u8) Errors!void,
    ) Errors!void {
        // We ignore the actual format char for now
        return deriveDebug(context, "{}", Errors, output, self.*, 0);
    }

    //#[inline]
    pub inline fn from_slice_and_pos(slice: []u8, pos: usize) OutputBuffer {
        return OutputBuffer {
            .slice = slice,
            .pos = pos,
        };
    }

    //#[inline]
    pub inline fn position(self: *const Self) usize {
        return self.pos;
    }

    //#[inline]
    pub inline fn set_position(self: *Self, pos: usize) void {
        self.pos = pos;
    }

    /// Write a byte to the current position and increment
    ///
    /// Assumes that there is space.
    //#[inline]
    pub inline fn write_byte(self: *Self, byte: u8) void {
        self.slice[self.pos] = byte;
        self.pos += 1;
    }

    /// Write a slice to the current position and increment
    ///
    /// Assumes that there is space.
    //#[inline]
    pub inline fn write_slice(self: *Self, data: []u8) void {
        const len = data.len;
        //self.slice[self.position..self.position + len].copy_from_slice(data);
        for (data) |d, ii| {
            self.slice[self.pos + ii] = d;
        }
        self.pos += data.len;
    }

    //#[inline]
    pub inline fn bytes_left(self: *const Self) usize {
        return self.slice.len - self.pos;
    }

    //#[inline]
    pub inline fn get_ref(self: *const Self) []u8 {
        return self.slice;
    }

    //#[inline]
    pub inline fn get_mut(self: *Self) []u8 {
        return self.slice;
    }
};


test "mzoutputbuffer.dummy" {
    const std = @import("std");
    const warn = std.debug.warn;
    var buffer: [256]u8 = undefined;
    var ob = OutputBuffer.from_slice_and_pos(buffer[0..], 0);

    warn("ob={}\n", ob);
}
