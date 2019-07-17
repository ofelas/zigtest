// -*- zig -*-
const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;
const assert = std.debug.assert;

const DummyOutStream = @import("lzstream.zig").DummyOutStream;

// An accumulating buffer for LZ sequences
pub const LZAccumBuffer = struct {
    const Self = @This();

    stream: *DummyOutStream,     //&'a mut W, // Output sink
    buf: []u8,                  // Buffer
    len: usize,       // Total number of bytes sent through the buffer

    pub fn from_stream(stream: *DummyOutStream, buf: []u8) Self {
        return Self {
            .stream = stream,
            .buf = buf,
            .len = 0,
        };
    }

    // Append bytes
    pub fn append_bytes(self: *Self, buf: []u8) !void {
        //self.buf.extend_from_slice(buf);
        if (self.buf.len - self.len < buf.len) {
            return error.NoMoreSpace;
        }
        mem.copy(u8, self.buf[self.len..], buf[0..]);
        self.len += buf.len;
    }

    // Reset the internal dictionary
    pub fn reset(self: *Self) !void {
        try self.stream.write_all(self.buf[0..self.len]);
        //try self.buf.clear();
        warn("WARNING: not clearing buf!!!\n");
        // TODO: clear the length ?
    }

    fn length(self: *const Self) usize {
        return self.len;
    }

    // Retrieve the last byte or return a default
    fn last_or(self: *const Self, lit: u8) u8 {
        const buf_len = self.len;
        if (buf_len == 0) {
            return lit;
        } else {
            return self.buf[buf_len - 1];
        }
    }

    // Retrieve the n-th last byte
    fn last_n(self: *const Self, dist: usize) !u8 {
        const buf_len = self.len;
        if (dist > buf_len) {
            warn("Match distance {} is beyond output size {}\n", dist, buf_len);
            return error.DistanceLargerThanBuffer;
        }
        return self.buf[buf_len - dist];
    }

    // Append a literal
    fn append_literal(self: *Self, lit: u8) !void {
        if (self.cursor >= self.buf.len) {
            return error.NoMoreSpace;
        }
        self.buf[self.len] = lit;
        self.len += 1;
    }

    // Fetch an LZ sequence (length, distance) from inside the buffer
    fn append_lz(self: *Self, len: usize, dist: usize) !void {
        warn("LZ {{ len: {}, dist: {} }}\n", len, dist);
        const buf_len = self.len;
        if (dist > buf_len) {
            warn("LZ distance {} is beyond output size {}\n", dist, buf_len);
            return error.DistanceLargerThanBuffer;
        }
        // TODO: check len too?

        var offset = buf_len - dist;
        var cnt: @typeOf(len) = 0;
        // for _ in 0..len {
        while (cnt < len) : ({cnt += 1; offset += 1;}) {
            self.buf[self.len + cnt] = self.buf[offset];
        }
        self.len += len;
    }

    // Flush the buffer to the output
    fn finish(self: *const Self) !void {
        try self.stream.write_all(self.buf[0..self.len]);
        try self.stream.flush();
    }
};


// A circular buffer for LZ sequences
pub const LZCircularBuffer = struct { //<'a, W>
    const Self = @This();
    
    stream: DummyOutStream,      // &'a mut W, // Output sink
    buf: []u8,         //Vec<u8>,      // Circular buffer
    dict_size: usize,  // Length of the buffer
    cursor: usize,     // Current position
    len: usize,        // Total number of bytes sent through the buffer

    pub fn from_buffer(stream: DummyOutStream, dict_size: usize, buf: []u8) Self {
        return Self {.stream = stream, .buf = buf, .dict_size = dict_size, .cursor = 0, .len = 0};
    }

    pub fn length(self: *const Self) usize {
        return self.buf.len;
    }

    // Retrieve the last byte or return a default
    pub fn last_or(self: *const Self, lit: u8) u8 {
        //warn("last_or: lit={}, {}\n", lit, self);
        if (self.len == 0) {
            return lit;
        } else {
            return self.buf[(self.dict_size + self.cursor - 1) % self.dict_size];
        }
    }

    // Retrieve the n-th last byte
    fn last_n(self: *const Self, dist: usize) !u8 {
        if (dist > self.dict_size) {
            warn("Match distance {} is beyond dictionary size {}",
                 dist, self.dict_size);
            return error.MatchDistanceLargerThanDictionary;
        }
        if (dist > self.len) {
            warn("Match distance {} is beyond output size {}",
                 dist, self.len);
            return error.MatchDistanceLargerThanOutput;
        }

        const offset = (self.dict_size + self.cursor - dist) % self.dict_size;
        return self.buf[offset];
    }

    // Append a literal
    fn append_literal(self: *Self, lit: u8) !void {
        //warn("len={}, cursor={}, lit={}/{c}\n", self.len, self.cursor, lit, lit);
        self.buf[self.cursor] = lit;
        self.cursor += 1;
        self.len += 1;

        // Flush the circular buffer to the output
        if (self.cursor == self.dict_size) {
            try self.stream.write_all(self.buf);
            self.cursor = 0;
        }
    }

    // Fetch an LZ sequence (length, distance) from inside the buffer
    fn append_lz(self: *Self, plen: usize, dist: usize) !void {
        //warn("LZ {{ len: {}, dist: {} }}\n", plen, dist);
        if (dist > self.dict_size) {
            warn("LZ distance {} is beyond dictionary size {}\n",
                 dist, self.dict_size);
            return error.MatchDistanceLargerThanDictionary;
        }
        if (dist > self.len) {
            warn("LZ distance {} is beyond output size {}\n",
                 dist, self.len);
            return error.MatchDistanceLargerThanOutput;
        }

        var offset = (self.dict_size + self.cursor - dist) % self.dict_size;
        var i: @typeOf(plen) = 0;
        while (i < plen) : (i += 1) {
            const x = self.buf[offset];
            //warn("Append {}/{c}\n", x, x);
            try self.append_literal(x);
            offset += 1;
            if (offset == self.dict_size) {
                offset = 0;
            }
        }
    }
    
    // Flush the buffer to the output
    fn finish(self: *Self) !void {
        if (self.cursor > 0) {
            try self.stream.write_all(self.buf[0..self.cursor]);
            try self.stream.flush();
        }
    }
};
