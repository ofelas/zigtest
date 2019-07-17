// -*- zig -*-
const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;
const assert = std.debug.assert;

//===============================================================================
// RangeEncoder

pub const RangeEncoder = struct { // <'a, W>
    const Self = @This();

    pos: usize,                 // hack until we actually have a stream
    stream: []u8,               //&'a mut W,
    range: u32,
    low: u64,
    cache: u8,
    cachesz: u32,

    pub fn new(stream: []u8) Self {
        const enc = Self {
            .pos = 0,           // hack
            .stream = stream,
            .range = 0xFFFFFFFF,
            .low = 0,
            .cache = 0,
            .cachesz = 1,
        };
        //warn("0 {{ range: {x:08}, low: {x:010}}}\n", enc.range, enc.low);
        return enc;
    }

    fn write_low(self: *Self) !void {
        if ((self.low < 0xFF000000) or (self.low > 0xFFFFFFFF)) {
            var tmp = self.cache;
            while(true) {
                const byte = tmp +% @truncate(u8, self.low >> 32);
                // hack
                // self.stream.write_u8(byte)?;
                if (self.pos >= self.stream.len) {
                    return error.OutputFull;
                }
                warn("out {} = {}/{x:02}\n", self.pos, byte, byte);
                self.stream[self.pos] = byte;
                self.pos += 1;
                // debug!("> byte: {:02x}", byte);
                tmp = 0xFF;
                self.cachesz -= 1;
                if (self.cachesz == 0) {
                    break;
                }
            }
            self.cache = @truncate(u8, self.low >> 24);
        }

        self.cachesz += 1;
        self.low = (self.low << 8) & 0xFFFFFFFF;
    }

    pub fn finish(self: *Self) !void {
        //     for _ in 0..5 {
        var cnt: usize = 0;
        while (cnt < 5) : (cnt += 1) {
            try self.write_low();
            // debug!("$ {{ range: {:08x}, low: {:010x} }}", self.range, self.low);
        }
    }

    fn normalize(self: *Self) !void {
        while (self.range < 0x1000000) {
    //         debug!(
    //             "+ {{ range: {:08x}, low: {:010x}, cache: {:02x}, {} }}",
    //             self.range, self.low, self.cache, self.cachesz
    //         );
            self.range <<= 8;
            try self.write_low();
    //         debug!(
    //             "* {{ range: {:08x}, low: {:010x}, cache: {:02x}, {} }}",
    //             self.range, self.low, self.cache, self.cachesz
    //         );
        }
        //warn("  {{ range: {x:08}, low: {x:010}}}\n", self.range, self.low);
    }

    pub fn encode_bit(self: *Self, prob: *u16, bit: u1) !void {
        const bound: u32 = (self.range >> 11) * u32(prob.*);
        //warn("  bound: {x:08}, prob: {x:04}, bit: {}\n", bound, prob, bit);

        if (bit == 1) {
            prob.* -= (prob.* >> 5);
            self.low += u64(bound);
            self.range -= bound;
        } else {
            prob.* += (u16(0x800) - prob.*) >> 5;
            self.range = bound;
        }

        try self.normalize();
    }
};


test "RangeEncoder.new" {
    var buf = [_]u8{0} ** 256;

    var rec = RangeEncoder.new(buf[0..]);
    warn("rec={}\n", rec);
}

//==============================================================================
// DumbEncoder

const LC: u32 = 3;
const LP: u32 = 0;
const PB: u32 = 2;

pub const Encoder = struct { //<'a, W>
    const Self = @This();

    rangecoder: RangeEncoder,
    literal_probs: [8][0x300]u16,
    is_match: [4]u16, // true = LZ, false = literal

    pub fn from_stream(stream: []u8) !Self {
        if (stream.len < 13) {
            return error.InsufficientOutputSpace;
        }
        const dict_size: u32 = 0x00800000;
        var idx: usize = 0;

        // Properties
        const props = @truncate(u8, LC + 9 * (LP + 5 * PB));
        warn("Properties {{ lc: {}, lp: {}, pb: {} }}\n", LC, LP, PB);
        //stream.write_u8(props)?;
        stream[idx] = props;
        idx += @sizeOf(u8);

        // Dictionary
        warn("Dict size: {}\n", dict_size);
        // stream.write_u32::<LittleEndian>(dict_size)?;
        stream[idx+0] = 0x00;
        stream[idx+1] = 0x00;
        stream[idx+2] = 0x80;
        stream[idx+3] = 0x00;
        idx += @sizeOf(u32);

        // Unpacked size
        warn("Unpacked size: unknown\n");
        // stream.write_u64::<LittleEndian>(0xFFFF_FFFF_FFFF_FFFF)?;
        stream[idx+0] = 0xff;
        stream[idx+1] = 0xff;
        stream[idx+2] = 0xff;
        stream[idx+3] = 0xff;
        stream[idx+4] = 0xff;
        stream[idx+5] = 0xff;
        stream[idx+6] = 0xff;
        stream[idx+7] = 0xff;
        idx += @sizeOf(u64);

        var encoder = Encoder {
            .rangecoder = RangeEncoder.new(stream[idx..]),
            .literal_probs = [_][0x300]u16{[_]u16{0x400} ** 0x300} ** 8, //: [[0x400; 0x300]; 8],
            .is_match = [_]u16{0x400} ** 4,
        };

        return encoder;
    }

    pub fn process(self: *Self, input: []u8) !usize {
        var prev_byte: u8 = 0;
        var input_len: usize = 0;

        // for (out_len, byte_result) in input.bytes().enumerate() {
        for (input) |byte, out_len| {
            // let byte = byte_result?;
            warn("{}, {}\n", out_len, byte);
            const pos_state = out_len & 3;
            input_len = out_len;

            // Literal
            try self.rangecoder.encode_bit(&self.is_match[pos_state], 0);

            try self.encode_literal(byte, prev_byte);
            prev_byte = byte;
        }

        try self.finish(input_len + 1);

        return self.rangecoder.pos + 13; // we wrote 13 bytes of initial stuff
    }

    fn finish(self: *Self, input_len: usize) !void {
        // Write end-of-stream marker
        const pos_state = input_len & 3;

        // Match
        try self.rangecoder.encode_bit(&self.is_match[pos_state], 1);
        warn("{x}\n", self.rangecoder.stream);
        // New distance
        var val: u16 = 0x400;
        try self.rangecoder.encode_bit(&val, 0);

        // Dummy len, as small as possible (len = 0)
        //  for _ in 0..4 {
        var idx: usize = 0;
        while (idx < 4) : (idx += 1) {
            val = 0x400;
            try self.rangecoder.encode_bit(&val, 0);
        }

        // Distance marker = 0xFFFFFFFF
        // pos_slot = 63
        // for _ in 0..6 {
        idx = 0;
        while (idx < 6) : (idx += 1) {
            val = 0x400;
            try self.rangecoder.encode_bit(&val, 1);
        }
        // num_direct_bits = 30
        // result = 3 << 30 = C000_0000
        //        + 3FFF_FFF0  (26 bits)
        //        + F          ( 4 bits)
        // for _ in 0..30 {
        idx = 0;
        while (idx < 30) : (idx += 1) {
            val = 0x400;
            try self.rangecoder.encode_bit(&val, 1);
        }
        //        = FFFF_FFFF

        // Flush range coder
        try self.rangecoder.finish();
    }

    fn encode_literal(self: *Self, pbyte: u8, pprev_byte: u8) !void {
        const prev_byte = usize(pprev_byte);
        var byte = pbyte;

        var result: usize = 1;
        const lit_state = prev_byte >> 5;
        var probs = &self.literal_probs[lit_state];

        // for i in 0..8 {
        var i: usize = 0;
        while (i < 8) : (i += 1) {
            const bit = @truncate(u1, (byte >> @truncate(u3, 7 - i))); // != 0
            try self.rangecoder.encode_bit(&probs[result], bit);
            result = (result << 1) ^ usize(bit);
        }
    }
};

test "Encoder.from_stream" {
    var buf = [_]u8{0} ** 256;

    var enc = try Encoder.from_stream(buf[0..]);
    warn("enc={}\n", enc);
}

test "Encoder.process" {
    var buf = [_]u8{0} ** 256;
    var input = "The quick brown fox jumps over the lazy";
    // Should get something like;
    // 5d00000400ffffffffffffffff002a1a08a2032566f14b78c5a205ff2ee6d9d2201aad34f8e21de84136fadc0669
    // bb3ce410342709ebb366ec1a172ffffcce9000

    // We get this, which decodes with Python, hurray;
    // 5d00008000ffffffffffffffff002a1a08a2032566f14b78c5a205ff2ee6d9d2201aad34f8e21de84136fadc0669
    // baa7fbdac4ef87e950a2a0eb4415ffffc5e70000

    // In [87]: lzma.decompress('5d00008000f...69baa7fbdac4ef87e950a2a0eb4415ffffc5e70000'.decode("hex"))
    // Out[87]: 'The quick brown fox jumps over the lazy dog'

    var enc = try Encoder.from_stream(buf[0..]);
    warn("enc={}\n", enc);
    const l = try enc.process(input[0..]);
    warn("l={}, buf={x}\n", l, buf[0..l]);
}
