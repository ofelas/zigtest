// -*- rust -*-
/// See https://github.com/gendx/lzma-rs.git
/// License: MIT
const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;
const assert = std.debug.assert;
const assertError = std.debug.assertError;
const assertOrPanic = std.debug.assertOrPanic;
const builtin = @import("builtin");

pub const DummyInStream = struct {
    const Self = @This();

    buf: []u8,
    pos: usize,

    pub fn new(buf: []u8) Self {
        return DummyInStream {.buf = buf, .pos = 0};
    }

    pub fn read_u8(self: *Self) !u8 {
        if (self.pos < self.buf.len) {
            self.pos += @sizeOf(u8);
            return self.buf[self.pos - 1];
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

    pub fn is_eof(self: *Self) bool {
        return (self.pos >= self.buf.len) or (self.buf[self.pos] == 0);
    }
};


pub const RangeDecoder = struct {
    const Self = @This();

    stream: *DummyInStream,
    range: u32,
    code: u32,

    pub fn new(stream: *DummyInStream) !Self {
        var dec = Self {
            .stream = stream,
            .range = 0xFFFFFFFF,
            .code = 0,
        };
        const byte = try dec.stream.read_u8();
        dec.code = try dec.stream.read_u32(builtin.Endian.Big);
        warn("New {}\n", dec);

        if ((byte != 0) or (dec.code == dec.range)) {
            return error.CorruptedStream;
        }

        return dec;
    }

    // #[inline]
    pub fn is_finished_ok(self: *Self) bool {
        return (self.code == 0) and (self.stream.is_eof());
    }

    // #[inline]
    fn normalize(self: *Self) !void {
        warn("{{ range: {x:08}, code: {x:08}}}\n", self.range, self.code);
        if (self.range < 0x1000000) {
            self.range <<= 8;
            const tmp = try self.stream.read_u8();
            self.code = (self.code << 8) ^ (u32(tmp));

            warn("+ {{ range: {x:08}, code: {x:08}}}\n", self.range, self.code);
        }
    }

    // #[inline]
    fn get_bit(self: *Self) !bool {
        self.range >>= 1;

        if (self.code == self.range) {
            return error.CorruptRangeCoding;
        }

        const bit = self.code > self.range;
        if (bit) {
            self.code -= self.range;
        }

        try self.normalize();

        return bit;
    }

    pub fn get(self: *Self, count: usize) !u32 {
        var result: u32 = 0;
        var i: @typeOf(count) = 0;
        while (i < count) : (i += 1) {
            const bit = @typeOf(result)(@boolToInt(try self.get_bit()));
            result = (result << 1) ^ bit;
        }
        return result;
    }

    // #[inline]
    pub fn decode_bit(self: *Self, prob: *u16) !bool {
        const bound: u32 = (self.range >> 11) *% (u32(prob.*));

        warn(" bound: {x:08}, prob: {x:04}, bit: {}", bound, prob.*, (self.code > bound));
        if (self.code < bound) {
            prob.* += (0x800 -% prob.*) >> 5;
            self.range = bound;

            try self.normalize();
            return false;
        } else {
            prob.* -= prob.* >> 5;
            self.code -= bound;
            self.range -= bound;

            try self.normalize();
            return true;
        }
    }

    fn parse_bit_tree(self: *Self, num_bits: usize, probs: []u16) !u32 {
        var tmp: u32 = 1;
        var cnt: @typeOf(num_bits) = 0;
        warn("probs.len={}, num_bits={}\n", probs.len, num_bits);
        while (cnt < num_bits) : (cnt += 1) {
            const bit = @typeOf(tmp)(@boolToInt(try self.decode_bit(&probs[tmp])));
            tmp = (tmp << 1) ^ bit;
        }
        warn("num_bits={}, cnt={}, tmp={}\n", num_bits, cnt, tmp);
        return tmp - (u32(1) << @truncate(u5, num_bits));
    }

    pub fn parse_reverse_bit_tree(
        self: *Self,
        num_bits: usize,
        probs: []u16,
        offset: usize,
    ) !u32 {
        var result: u32 = 0;
        var tmp: usize = 1;
        var i: @typeOf(num_bits) = 0;
        while (i < num_bits) : (i += 1) {
            const bit = try self.decode_bit(&probs[offset + tmp]);
            tmp = (tmp << 1) ^ (usize(@boolToInt(bit)));
            result ^= (u32(@boolToInt(bit))) << @truncate(u5, i);
        }
        return result;
     }
};

test "RangeDecoder.001" {
    var test_data = "]\x00\x00\x80\x00\xff\xff\xff\xff\xff\xff\xff\xff\x00*\x1a\x08\xa2\x03%f\xf1Kx\xc5\xa2\x05\xff.\xe6\xd9\xd2 \x1a\xb9\n\xaa\xdc\xb6J\x05\xf7LU\x9b\xdc\xd9\x7f\x00\x06Sl\x03;\x9eb\xe9w>\x0c<\xff\xfa~P\x00";

    var stream = DummyInStream.new(test_data[13..]);
    var dec = try RangeDecoder.new(&stream);
    var prob: u16 = 0x400;

    var ifo = dec.is_finished_ok();
    warn("ifo={}\n", ifo);
    ifo = try dec.decode_bit(&prob);
    warn("ifo={}\n", ifo);
}

// TODO: parametrize by constant and use [u16; 1 << num_bits] as soon as Rust supports this
// #[derive(Clone)]
pub fn BitTree(comptime N: usize) type {
    return struct {
        const Self = @This();

        num_bits: usize,
        probs: [1 << N]u16,


        pub fn init() Self {
            var bt = Self {.num_bits = N, .probs = [_]u16{0x400} ** (1 << N) };
            return bt;
        }

        pub fn parse(self: *Self, rangecoder: *RangeDecoder) !u32 {
            return rangecoder.parse_bit_tree(self.num_bits, self.probs[0..]);
        }

        pub fn parse_reverse(self: *Self, rangecoder: *RangeDecoder) !u32 {
            return rangecoder.parse_reverse_bit_tree(self.num_bits, self.probs[0..], 0);
        }
    };
}

test "BitTree.init" {
    const bt3 = BitTree(3).init();
    warn("{}\n", bt3);
    var bt8 = BitTree(8).init();
    warn("{}\n", bt8);
}

pub fn LenDecoder(comptime N: usize, comptime M: usize) type {
    return struct {
        const Self = @This();
        choice: u16,
        choice2: u16,
        low_coder: [16]BitTree(N),
        mid_coder: [16]BitTree(N),
        high_coder: BitTree(M),

        pub fn init() Self {
            return Self {.choice = 0x400, .choice2 = 0x400,
                         .low_coder = [_]BitTree(N) {BitTree(N).init()} ** 16,
                         .mid_coder = [_]BitTree(N) {BitTree(N).init()} ** 16,
                         .high_coder = BitTree(M).init()};
        }

        pub fn decode(self: *Self, rangecoder: *RangeDecoder, pos_state: usize) !usize {
            if (! try rangecoder.decode_bit(&self.choice)) {
                return usize(try self.low_coder[pos_state].parse(rangecoder));
            } else {
                if (! try rangecoder.decode_bit(&self.choice2)) {
                    return usize(try self.mid_coder[pos_state].parse(rangecoder)) + 8;
                } else {
                    return usize(try self.high_coder.parse(rangecoder)) + 16;
                }
            }
        }
    };
}

