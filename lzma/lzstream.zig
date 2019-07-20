// -*- zig -*-
const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;
const assert = std.debug.assert;


pub const DummyInStream = struct {
    const Self = @This();

    buf: []u8,
    pos: usize,

    pub fn new(buf: []u8) Self {
        return DummyInStream {.buf = buf, .pos = 0};
    }

    pub fn read_u8(self: *Self) !u8 {
        if ((self.pos + @sizeOf(u8)) <= self.buf.len) {
            self.pos += @sizeOf(u8);
            return self.buf[self.pos - 1];
        } else {
            warn("## self.pos={} vs self.buf.len={}\n", self.pos, self.buf.len);
            return error.NoMoreData;
        }
    }

    pub fn read_u16(self: *Self, endian: builtin.Endian) !u16 {
        if (self.pos < (self.buf.len - @sizeOf(u16))) {
            const v = mem.readIntSlice(u16, self.buf[self.pos..], endian);
            self.pos += @sizeOf(u16);
            return v;
        } else {
            return error.NoMoreData;
        }
    }

    pub fn read_u32(self: *Self, endian: builtin.Endian) !u32 {
        if (self.pos < (self.buf.len - @sizeOf(u32))) {
            const v = mem.readIntSlice(u32, self.buf[self.pos..], endian);
            self.pos += @sizeOf(u32);
            return v;
        } else {
            return error.NoMoreData;
        }
    }

    pub fn read_exact(self: *Self, dest: []u8) !void {
        if (self.pos < (self.buf.len - dest.len)) {
            mem.copy(u8, dest[0..], self.buf[self.pos..self.pos + dest.len]);
            self.pos += dest.len;
        } else {
            return error.NoMoreData;
        }
    }

    pub fn take(self: *Self, amount: usize) ![]u8 {
        if (self.pos < (self.buf.len - amount)) {
            const pos = self.pos;
            self.pos += amount;
            return self.buf[pos .. self.pos];
        } else {
            return error.NotEnoughData;
        }
    }
    
    pub fn is_eof(self: *Self) bool {
        return (self.pos >= self.buf.len) or (self.buf[self.pos] == 0);
    }
};

pub const DummyOutStream = struct {
    const Self = @This();

    pos: usize,
    buf: []u8,

    /// Make a new stream (actually a fixed buffer for now)
    pub fn new(buf: []u8) Self {
        return Self {.buf = buf, .pos = 0};
    }

    pub fn write_all(self: *Self, buf: []u8) !void {
        // copy from slice to self.buf and update pos
        warn("write_all: {} [{}], buf.len={}\n", self, self.buf.len, buf.len);
        if ((self.buf.len - self.pos) > buf.len) {
            mem.copy(u8, self.buf[self.pos..], buf);
            self.pos += buf.len;
            return;
        }
        return error.NoMoreSpace;
    }

    /// Flush the output
    /// Ideally a bit smarter than this eventually...
    pub fn flush(self: *Self) !void {
        warn("Flushing {}\n", self);
        if (self.pos == 0) {
            return error.MissingImplementation;
        }
        self.pos = 0;
    }
};
