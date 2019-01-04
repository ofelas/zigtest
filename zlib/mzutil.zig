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

pub inline fn maxValue(comptime T: type) T {
    return std.math.maxInt(T);
}


pub fn deriveDebug(
    context: var,
    comptime fmt: []const u8,
    comptime Errors: type,
    output: fn (@typeOf(context), []const u8) Errors!void,
    value: var,
    level: usize,
) Errors!void {
    if (level > 3) {
        return output(context, "...");
    }
    const T = @typeOf(value);
    if (T == @typeOf(error.SomeError)) {
        try output(context, "error.");
        return output(context, @errorName(value));
    }
    switch (@typeInfo(T)) {
        builtin.TypeId.Int => {
            return std.fmt.format(context, Errors, output, "{}", value);
        },
        builtin.TypeId.Float => {
            return std.fmt.format(context, Errors, output, "{.6}", value);
        },
        builtin.TypeId.Void => {
            return output(context, "void");
        },
        builtin.TypeId.Bool => {
            return output(context, if (value) "true" else "false");
        },
        builtin.TypeId.Enum => |v| {
            try output(context, @typeName(T) ++ ".");
            return output(context, @tagName(value));
        },
        builtin.TypeId.Union => |v| {
            inline for (v.fields) |f| {
                if (mem.eql(u8, @tagName(value), f.name)) {
                    try deriveDebug(context, "{}", Errors, output, @field(value, f.name), level + 1);
                }
            }
            return output(context, "");
        },
        builtin.TypeId.Struct => |v| {
            try output(context, @typeName(T) ++ "{");
            return inline for (v.fields) |f, i| {
                if (i > 0) {
                    try output(context, ", ");
                }
                try output(context, "." ++ f.name ++ "=");
                try deriveDebug(context, "{}", Errors, output, @field(value, f.name), level + 1);
            } else try output(context, "}");
        },
        builtin.TypeId.Optional => {
            if (value) |payload| {
                return deriveDebug(context, "{}", Errors, output, payload, level + 1);
            } else {
                return output(context, "null");
            }
        },
        builtin.TypeId.ErrorUnion => {
            if (value) |payload| {
                return deriveDebug(context, fmt, Errors, output, payload, level + 1);
            } else |err| {
                return deriveDebug(context, fmt, Errors, output, err, level + 1);
            }
        },
        builtin.TypeId.ErrorSet => {
             try output(context, "error.");
             return output(context, @errorName(value));
        },
        builtin.TypeId.Promise => {
            return std.fmt.format(context, Errors, output, "promise@{x}", @ptrToInt(value));
        },
        builtin.TypeId.Pointer => |ptr_info| {
            switch (ptr_info.size) {
                builtin.TypeInfo.Pointer.Size.One => {
                    return deriveDebug(context, fmt, Errors, output, value.*, level + 1);
                },
                builtin.TypeInfo.Pointer.Size.Many => {
                    return output(context, "Many:" ++ @typeName(@typeOf(ptr_info)));
                },
                builtin.TypeInfo.Pointer.Size.Slice => {
                    const casted_value = ([]const u8)(value);
                    return std.fmt.format(context, Errors, output, "'{}'...",
                                          casted_value[0..MIN(usize, 3, value.len)]);
                },
                else => {
                    return output(context, @typeName(@typeOf(ptr_info)));
                }
            }
        },
        builtin.TypeId.Array => |info| {
            return std.fmt.format(context, Errors, output, "[{}]{}@{x}", value.len, @typeName(T.Child), @ptrToInt(&value));
        },
        else => @compileError("Unable to format type: '" ++ @typeName(T) ++ "'"),
    }
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
    const Self = @This();
    pub pos: usize,
    pub bit_buffer: u32,
    pub bits_in: u32,
    pub local: bool,

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

pub const SeekFrom = union(enum) {
    Start: isize,
    End: isize,
    Current: isize,
};


pub fn Cursor(comptime T: type) type {
    return struct {
        const Self = @This();
        pos: usize,
        inner: T,

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
            mem.writeIntSlice(u64, self.inner[self.pos..self.pos+@sizeOf(u64)], value, endian);
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
    const Self = @This();
    pub inner: Cursor([]u8),
    pub local: bool,
    pub bit_buffer: u32,
    pub bits_in: u32,

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

    inline fn len(self: *Self) usize {
        return self.inner.len();
    }

    inline fn write_u64_le(self: *Self, value: u64) !void {
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

    inline fn save(self: *Self) SavedOutputBuffer {
        var sb = SavedOutputBuffer {
            .pos = self.inner.position(),
            .bit_buffer = self.bit_buffer,
            .bits_in = self.bits_in,
            .local = self.local,
        };

        return sb;
    }

    inline fn load(self: *Self, saved: SavedOutputBuffer) void {
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

test "deriveDebug" {
    const E = enum {
        ONE,
        TWO,
        THREE,
    };
    const UE = union(enum) {
        const Self = @This();
        i: isize,
        u: usize,
        z: E,

        fn format(
            self: *const Self,
            comptime fmt: []const u8,
            context: var,
            comptime Errors: type,
            output: fn (@typeOf(context), []const u8) Errors!void,
        ) Errors!void {
            return deriveDebug(context, "{}", Errors, output, self.*, 0);
        }
    };

    const Bob = struct {
        const Self = @This();

        e: E,
        ue: UE,
        x: i32,
        f: f64,
        a: [2]u8,
        o8: ?u8,
        o16: ?u16,
        //TODO e8: error.Bob!u8,
        p8: *u8,
        pe: *UE,

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

    var b: u8 = 13;
    var a = "hi";
    var s = []u8 {0} ** 128;
    var ue = UE {.i = 1};
    var e = E.ONE;
    var bob = Bob {.e = E.TWO, .ue = UE{.z=e}, .x=123, .f=1.2, .a=a, .o8=0xff, .o16=null,
                   //TODO .e8=error.FixMe,
                   .p8= &b, .pe=&ue};
    warn("s='{}'\n", &bob);
    warn("f={}\n", &ue);
}
