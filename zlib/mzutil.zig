// -*- mode:zig; indent-tabs-mode:nil;  -*-
const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;
const assert = std.debug.assert;
const assertError = std.debug.assertError;
const assertOrPanic = std.debug.assertOrPanic;
const builtin = @import("builtin");

const debug = false;

pub inline fn typeNameOf(v: var) []const u8 {
    return @typeName(@typeOf(v));
}


// Don't call this memset or it will call itself...
pub inline fn setmem(comptime T: type, slice: []T, val: T) void {
    //warn("setmem({} {})\n", slice.len, val);
    for (slice) |*x| {
        x.* = val;
    }
}


pub inline fn MIN(comptime T: type, a: T, b: T) T {
    if (T == bool) {
        return a or b;
    } else if (a <= b) {
        return a;
    } else {
        return b;
    }
}

pub inline fn MAX(comptime T: type, a: T, b: T) T {
    if (T == bool) {
        return a or b;
    } else if (a >= b) {
        return a;
    } else {
        return b;
    }
}

pub const SavedOutputBuffer = struct {
    const Self = this;
    pub pos: usize,
    pub bit_buffer: u32,
    pub bits_in: u32,
    pub local: bool,

    fn dump(self: *const Self) void {
        @setCold(true);
        warn("SavedOutputBuffer@{} pos={}, bit_buffer={x08}, bits_in={}, local={}\n",
             self, self.pos, self.bit_buffer, self.bits_in, self.local);
    }
};

pub const SeekFrom = union(enum) {
    Start: isize,
    End: isize,
    Current: isize,
};


pub fn Cursor(comptime T: type) type {
    return struct {
        const Self = this;
        pos: usize,
        inner: T,

        fn dump(self: *Self) void {
            @setCold(true);
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

        fn get_ref(self: *Self) T {
            return self.inner[0..];
        }

        fn get_mut(self: *Self) T {
            return self.inner[0..];
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

        fn write_one(self: *Self, c: u8) void{
            self.inner[self.pos] = c;
            self.pos += 1;
        }

        fn write_all(self: *Self, buf: []const u8) !void {
            if ((self.pos + buf.len) >= self.inner.len) {
                return error.NoSpace;
            }
            assert((self.pos + buf.len) < self.inner.len);
            for (buf) |c| {
                self.inner[self.pos] = c;
                self.pos += 1;
            }
        }
    };
}

pub const OutputBuffer = struct {
    const Self = this;
    pub inner: Cursor([]u8),
    pub local: bool,
    pub bit_buffer: u32,
    pub bits_in: u32,

    fn dump(self: *const Self) void {
        @setCold(true);
        warn("{} {x08} {}\n", self, self.bit_buffer, self.bits_in);
    }

    inline fn len(self: *Self) usize {
        return self.inner.len();
    }

    fn write_u64_le(self: *Self, value: u64) !void {
        //warn("Writing u64={x}\n", value);
        try self.inner.writeInt(value, builtin.Endian.Little);
    }

    inline fn put_bits(self: *Self, bits: u32, length: u32) void {
        // assert!(bits <= ((1u32 << len) - 1u32));
        assert(length < @typeOf(bits).bit_count);
        //warn("put_bits({x08},{})\n", bits, length);
        self.*.bit_buffer |= bits << @truncate(u5, self.*.bits_in);
        self.*.bits_in += length;
        while (self.*.bits_in >= 8) {
            const pos = self.*.inner.position();
            // .get_mut() read some Rust
            self.*.inner.inner[pos] = @truncate(u8, self.*.bit_buffer);
            self.*.inner.set_position(pos + 1);
            self.*.bit_buffer >>= 8;
            self.*.bits_in -= 8;
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

    inline fn pad_to_bytes(self: *Self) void {
        if (self.bits_in != 0) {
            const length = 8 - self.bits_in;
            if (debug) warn("pad_to_bytes bits_in={}, length={}\n", self.bits_in, length);
            self.put_bits(0, length);
        }
    }

};
