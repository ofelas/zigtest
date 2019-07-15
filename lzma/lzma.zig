// -*- rust -*-
// Well, this is actually zig...
// https://en.wikipedia.org/wiki/LZMA
// See https://github.com/gendx/lzma-rs.git
// License: MIT

const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;
const assert = std.debug.assert;
const assertError = std.debug.assertError;
const assertOrPanic = std.debug.assertOrPanic;
const builtin = @import("builtin");

const rangecoder = @import("rangecoder.zig");
const RangeDecoder = rangecoder.RangeDecoder;

const crc32 = std.hash.crc.Crc32;

//

pub const DummyOutStream = struct {
    const Self = @This();

    buf: []u8,
    pos: usize,

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

// A circular buffer for LZ sequences
pub const LZCircularBuffer = struct { //<'a, W>
    const Self = @This();

    stream: DummyOutStream,      // &'a mut W, // Output sink
    buf: []u8,         //Vec<u8>,      // Circular buffer
    dict_size: usize,  // Length of the buffer
    cursor: usize,     // Current position
    len: usize,        // Total number of bytes sent through the buffer

    pub fn from_buffer(stream: DummyOutStream, dict_size: usize, buf: []u8) Self {
        return Self {.stream = stream, .buf = buf, .dict_size = dict_size, .cursor = 0, .len = buf.len};
    }

    pub fn len(self: *const Self) usize {
        return self.buf.len;
    }

    // Retrieve the last byte or return a default
    pub fn last_or(self: *const Self, lit: u8) u8 {
        warn("last_or: lit={}, {}\n", lit, self);
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
        warn("LZ {{ len: {}, dist: {} }}\n", plen, dist);
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

//

pub const LZMAParams = struct {
    // most lc significant bits of previous byte are part of the literal context
    lc: u32, // 0..8
    lp: u32, // 0..4
    // context for literal/match is plaintext offset modulo 2^pb
    pb: u32, // 0..4
    dict_size: u32,
    unpacked_size: ?u64,
    // NOTE: Temporary hack
    pos: usize,

    pub fn read_header(input: []u8) !LZMAParams
    {
        // Properties
        var idx: usize = 0;
        // NOTE: Arbitrary check for now
        if (input.len < 13) {
            warn("LZMA header too short: {}\n", input.len);
            return error.LZMAError;
        }

        const props = input[idx];
        idx += @sizeOf(u8);

        var pb = u32(props);
        if (pb >= 225) {
            warn("LZMA header invalid properties: {} must be < 225\n", pb);
            return error.LZMAError;
        }

        const lc: u32 = pb % 9;
        pb /= 9;
        const lp: u32 = pb % 5;
        pb /= 5;

        warn("Properties {{ lc: {}, lp: {}, pb: {} }}\n", lc, lp, pb);

        // Dictionary

        
        // const dict_size_provided = mem.readIntSlice(u32, input[idx..idx + @sizeOf(u32)],
        //                                             builtin.Endian.Little);
        const dict_size_provided = u32(input[idx + 3]) | u32(input[idx + 2]) << 8
            | u32(input[idx + 1]) << 16 | u32(input[idx + 0]) << 24;
        idx += @sizeOf(u32);
        const dict_size = if (dict_size_provided < 0x1000) 0x1000 else dict_size_provided;
        warn("dict_size={x}, dict_size_provided={}\n", dict_size, dict_size_provided);

        // Unpacked size
        const unpacked_size_provided = mem.readIntSlice(u64, input[idx..], builtin.Endian.Little);
        idx += @sizeOf(u64);
        const marker_mandatory: bool = unpacked_size_provided == 0xFFFFFFFFFFFFFFFF;
        const unpacked_size = if (marker_mandatory) null else unpacked_size_provided;
        warn("Unpacked size={}, mandatory={}, idx={}\n", unpacked_size, marker_mandatory, idx);

        return LZMAParams {.lc = lc, .lp = lp, .pb = pb,
                           .dict_size = dict_size, .unpacked_size = unpacked_size, .pos = idx};
    }
};

test "LZMAParams.structs" {
    const params: LZMAParams = undefined;

    // lzma.compress("The quick brown foxs jumps over the lazy dog", {"format": "alone"}

    var test_data = "]\x00\x00\x80\x00\xff\xff\xff\xff\xff\xff\xff\xff\x00*\x1a\x08\xa2\x03%f\xf1Kx\xc5\xa2\x05\xff.\xe6\xd9\xd2 \x1a\xb9\n\xaa\xdc\xb6J\x05\xf7LU\x9b\xdc\xd9\x7f\x00\x06Sl\x03;\x9eb\xe9w>\x0c<\xff\xfa~P\x00";

    var result = try LZMAParams.read_header(test_data[0..]);
    warn("{}\n", result);
    warn("{x}\n", test_data[result.pos..]);
    // Now it is probably time to do a range decoder
}

// maybe we were a bit lucky here
test "LZMA.decompress.worked" {
    var test_data = "]\x00\x00\x04\x00\xff\xff\xff\xff\xff\xff\xff\xff\x00*\x1a\x08\xa2\x03%f\xf1Kx\xc5\xa2\x05\xff.\xe6\xd9\xd2 \x1a\xb9\n\xaa\xdc\xb6J\x05\xf7LU\x9b\xdc\xd9\x7f\x00\x06Sl\x03;\x9eb\xe9w>\x0c<\xff\xfa~P\x00";
    const params = try LZMAParams.read_header(test_data[0..]);
    var outbuf = [_]u8{0} ** 256;
    var output = DummyOutStream.new(outbuf[0..]);
    var buffer = [_]u8{0} ** 8192;
    var cb = LZCircularBuffer.from_buffer(output, params.dict_size, buffer[0..]);
    var decoder = Decoder(LZCircularBuffer).init(cb, params);
    var instream = rangecoder.DummyInStream.new(test_data[params.pos .. ]);
    var rycoder = try RangeDecoder.new(&instream);

    try decoder.process(&rycoder);
    try decoder.output.finish();

    warn("decoder.output.stream='{}'\n", decoder.output.stream);
    assert(mem.eql(u8, decoder.output.stream.buf[0..44],
                   "The quick brown foxs jumps over the lazy dog"));
}

test "LZMA.decompress.attempt2" {
    //lzma.compress("The quick brown fox jumps over the lazy dog", {"format": "alone", "level":0})
    var test_data = "]\x00\x00\x04\x00\xff\xff\xff\xff\xff\xff\xff\xff\x00*\x1a\x08\xa2\x03%f\xf1Kx\xc5\xa2\x05\xff.\xe6\xd9\xd2 \x1a\xad4\xf8\xe2\x1d\xe8A6\xfa\xdc\x06i\xbb<\xe4\x104'\t\xeb\xb3f\xec\x1a\x17/\xff\xfc\xce\x90\x00";
    const params = try LZMAParams.read_header(test_data[0..]);
    var outbuf = [_]u8{0} ** 256;
    var output = DummyOutStream.new(outbuf[0..]);
    var buffer = [_]u8{0} ** 8192;
    var cb = LZCircularBuffer.from_buffer(output, params.dict_size, buffer[0..]);
    var decoder = Decoder(LZCircularBuffer).init(cb, params);
    var instream = rangecoder.DummyInStream.new(test_data[params.pos .. ]);
    var rycoder = try RangeDecoder.new(&instream);

    try decoder.process(&rycoder);
    try decoder.output.finish();

    warn("decoder.output.stream='{}'\n", decoder.output.stream);
    assert(mem.eql(u8, decoder.output.stream.buf[0..43],
                   "The quick brown fox jumps over the lazy dog"));
}

test "LZMA.decompress.attempt3" {
    //lzma.compress("dog dog dog dog dog dog dog dog", {"format": "alone", "level":0})
    var test_data = "]\x00\x00\x04\x00\xff\xff\xff\xff\xff\xff\xff\xff\x002\x1b\xc9\x14\x9e\xe3\x0b\x0e\x03\xa7\xff\xfe\xf9\xc0\x00";
    const params = try LZMAParams.read_header(test_data[0..]);
    var outbuf = [_]u8{0} ** 256;
    var output = DummyOutStream.new(outbuf[0..]);
    var buffer = [_]u8{0} ** (32 * 1024);
    var cb = LZCircularBuffer.from_buffer(output, params.dict_size, buffer[0..]);
    var decoder = Decoder(LZCircularBuffer).init(cb, params);
    var instream = rangecoder.DummyInStream.new(test_data[params.pos .. ]);
    var rycoder = try RangeDecoder.new(&instream);

    try decoder.process(&rycoder);
    try decoder.output.finish();

    warn("params={}\n", params);
    warn("decoder.output.stream='{}'\n", decoder.output.stream);
    assert(mem.eql(u8, decoder.output.stream.buf[0..31],
                   "dog dog dog dog dog dog dog dog"));
}

test "LZMA.decompress.attempt4" {
    //lzma.compress("The quick brown fox jumps over the lazy dog", {"format": "alone", "level":6})
    var test_data = "]\x00\x00\x80\x00\xff\xff\xff\xff\xff\xff\xff\xff\x00*\x1a\x08\xa2\x03%f\xf1Kx\xc5\xa2\x05\xff.\xe6\xd9\xd2 \x1a\xad4\xf8\xe2\x1d\xe8A6\xfa\xdc\x06i\xbb<\xe4\x104'\t\xeb\xb3f\xec\x1a\x17/\xff\xfc\xce\x90\x00";
    const params = try LZMAParams.read_header(test_data[0..]);
    var outbuf = [_]u8{0} ** 256;
    var output = DummyOutStream.new(outbuf[0..]);
    var buffer = [_]u8{0} ** (32 * 1024);  // probably needs to use params.dict_size;
    var cb = LZCircularBuffer.from_buffer(output, params.dict_size, buffer[0..]);
    var decoder = Decoder(LZCircularBuffer).init(cb, params);
    var instream = rangecoder.DummyInStream.new(test_data[params.pos .. ]);
    var rycoder = try RangeDecoder.new(&instream);

    try decoder.process(&rycoder);
    try decoder.output.finish();

    warn("params={}\n", params);
    warn("decoder.output.stream='{}'\n", decoder.output.stream);
    assert(mem.eql(u8, decoder.output.stream.buf[0..43],
                   "The quick brown fox jumps over the lazy dog"));
}

test "LZMA.decompress.attempt5" {
    //lzma.compress("The quick brown fox jumps over the lazy dog, The quick brown fox jumps over the lazy dog",
    //              {"format": "alone", "level":9})
    var test_data = "]\x00\x00\x00\x04\xff\xff\xff\xff\xff\xff\xff\xff\x00*\x1a\x08\xa2\x03%f\xf1Kx\xc5\xa2\x05\xff.\xe6\xd9\xd2 \x1a\xad4\xf8\xe2\x1d\xe8A6\xfa\xdc\x06i\xbb<\xe4\x104'\t\xeb\xb3f\xe3\xd4q:\xfaH\x93\t\xa7\xff\xfak`\x00";
    const params = try LZMAParams.read_header(test_data[0..]);
    var outbuf = [_]u8{0} ** 256;
    var output = DummyOutStream.new(outbuf[0..]);
    var buffer = [_]u8{0} ** (32 * 1024);  // probably needs to use params.dict_size;
    var cb = LZCircularBuffer.from_buffer(output, params.dict_size, buffer[0..]);
    var decoder = Decoder(LZCircularBuffer).init(cb, params);
    var instream = rangecoder.DummyInStream.new(test_data[params.pos .. ]);
    var rycoder = try RangeDecoder.new(&instream);

    try decoder.process(&rycoder);
    try decoder.output.finish();

    warn("params={}\n", params);
    warn("decoder.output.stream='{}'\n", decoder.output.stream);
    assert(mem.eql(u8, decoder.output.stream.buf[0..43+43+2],
                   "The quick brown fox jumps over the lazy dog, The quick brown fox jumps over the lazy dog"));
}


// Initialize decoder with circular buffer
pub fn Decoder(comptime T: type, ) type {
    // Decoder
    return struct {
        const Self = @This();

        pub output: T,
        // most lc significant bits of previous byte are part of the literal context
        pub lc: u32, // 0..8
        pub lp: u32, // 0..4
        // context for literal/match is plaintext offset modulo 2^pb
        pub pb: u32, // 0..4
        unpacked_size: ?u64,
        // TODO: We may have maxed this out...
        literal_probs: [4096][0x300]u16, //Vec<Vec<u16>>,
        pos_slot_decoder: [4]rangecoder.BitTree(6),
        align_decoder: rangecoder.BitTree(4),
        pos_decoders: [115]u16,
        is_match: [192]u16, // true = LZ, false = literal
        is_rep: [12]u16,
        is_rep_g0: [12]u16,
        is_rep_g1: [12]u16,
        is_rep_g2: [12]u16,
        is_rep_0long: [192]u16,
        state: usize,
        rep: [4]usize,
        len_decoder: rangecoder.LenDecoder(3, 8),
        rep_len_decoder: rangecoder.LenDecoder(3, 8),

        pub fn init(output: T, params: LZMAParams) Self {
            return Self {
                .output = output,
                .lc = params.lc,
                .lp = params.lp,
                .pb = params.pb,
                .unpacked_size = params.unpacked_size,
                .literal_probs = [_][0x300]u16{[_]u16{0x400} ** 0x300} ** 4096,
                .pos_slot_decoder = [_]rangecoder.BitTree(6) {rangecoder.BitTree(6).init()} ** 4,
                .align_decoder = rangecoder.BitTree(4).init(),
                .pos_decoders = [_]u16{0x400} ** 115,
                .is_match = [_]u16{0x400} ** 192,
                .is_rep = [_]u16{0x400} ** 12,
                .is_rep_g0 = [_]u16{0x400} ** 12,
                .is_rep_g1 = [_]u16{0x400} ** 12,
                .is_rep_g2 = [_]u16{0x400} ** 12,
                .is_rep_0long = [_]u16{0x400} ** 192,
                .state = 0,
                .rep = [_]usize{0,0,0,0},
                .len_decoder = rangecoder.LenDecoder(3, 8).init(),
                .rep_len_decoder = rangecoder.LenDecoder(3, 8).init()
            };
        }


        pub fn set_unpacked_size(self: *Self, unpacked_size: ?u64) void {
            self.unpacked_size = unpacked_size;
        }


        pub fn process(self: *Self, rcoder: *rangecoder.RangeDecoder) !void {
            // For debugging
            var iter = usize(0);
            while (true) {
                iter += 1;
                warn("Loop {}, {}\n", iter, self.output);
                if (self.unpacked_size) |_| {
                    if (rcoder.is_finished_ok()) {
                        break;
                    }
                }
                const pos_state = self.output.len & ((usize(1) << @truncate(u6, self.pb)) - 1);
                warn("### self.state={}, pos_state={}\n", self.state, pos_state);

                // Literal
                // TODO: assumes pb = 2 ??
                if (! try rcoder.decode_bit(&self.is_match[(self.state << 4) + pos_state])) {
                    const byte: u8 = try self.decode_literal(rcoder);
                    warn("Literal: {}\n", byte);
                    try self.output.append_literal(byte);

                    self.state = if (self.state < 4) 0 else if (self.state < 10) self.state - 3
                        else self.state - 6;
                    
                    continue;
                }
                // LZ
                var len: usize = undefined;
                // Distance is repeated from LRU
                if (try rcoder.decode_bit(&self.is_rep[self.state])) {
                    warn("1\n");
                    // dist = rep[0]
                    if (! try rcoder.decode_bit(&self.is_rep_g0[self.state])) {
                        // len = 1
                        if (! try rcoder.decode_bit(&self.is_rep_0long[(self.state << 4) + pos_state]))
                        {
                            warn("update state (short rep)\n");
                            // update state (short rep)
                            self.state = if (self.state < 7) usize(9) else 11;
                            const dist = self.rep[0] + 1;
                            try self.output.append_lz(1, dist);
                            continue;
                        }
                        // dist = rep[i]
                    } else {
                        warn("1 else\n");
                        var idx: usize = undefined;
                        if (! try rcoder.decode_bit(&self.is_rep_g1[self.state])) {
                            idx = 1;
                        } else {
                            if (! try rcoder.decode_bit(&self.is_rep_g2[self.state])) {
                                idx = 2;
                            } else {
                                idx = 3;
                            }
                        }
                        // Update LRU
                        const dist = self.rep[idx];
                        // for i in (0..idx).rev() {
                        //     self.rep[i + 1] = self.rep[i];
                        // }
                        var i: usize = idx - 1;
                        while(i > 0) : (i -= 1) {
                            self.rep[i + 1] = self.rep[i];
                            
                        }
                        self.rep[0] = dist;
                    }

                    len = try self.rep_len_decoder.decode(rcoder, pos_state);
                    // update state (rep)
                    self.state = if (self.state < 7) 8 else usize(11);
                    // New distance
                } else {
                    warn("New distance, update LRU\n");
                    // Update LRU
                    self.rep[3] = self.rep[2];
                    self.rep[2] = self.rep[1];
                    self.rep[1] = self.rep[0];
                    len = try self.len_decoder.decode(rcoder, pos_state);

                    // update state (match)
                    self.state = if (self.state < 7) usize(7) else usize(10);
                    self.rep[0] = try self.decode_distance(rcoder, len);

                    if (self.rep[0] == 0xFFFFFFFF) {
                        if (rcoder.is_finished_ok()) {
                            break;
                        }
                        warn("Found end-of-stream marker but more bytes are available");
                        return error.EndOfStreamButMoreBytes;
                    }
                }

                len += 2;

                const dist = self.rep[0] + 1;
                try self.output.append_lz(len, dist);
            }
                    
            if (self.unpacked_size) |len| {
                if (self.output.len != len) {
                    warn("Expected unpacked size of {} but decompressed to {}", len, self.output.len);
                }
            }

            return;
        }

        pub fn decode_literal(self: *Self, rcoder: *RangeDecoder) !u8 {
            const def_prev_byte: u8 = 0;
            const prev_byte = usize(self.output.last_or(def_prev_byte));

            var result: usize = 1;
            const lit_state =
                ((self.output.len & ((usize(1) << @truncate(u6, self.lp)) - 1))
                 << @truncate(u6, self.lc)) + (prev_byte >> @truncate(u6, 8 - self.lc));
            var probs = &self.literal_probs[lit_state];
            warn("probs={}, lit_state={}\n", probs, lit_state);

            if (self.state >= 7) {
                var match_byte = usize(try self.output.last_n(self.rep[0] + 1));

                while (result < 0x100) {
                    const match_bit = (match_byte >> 7) & 1;
                    match_byte <<= 1;
                    const bit =
                        @boolToInt(try rcoder.decode_bit(&probs[((1 + match_bit) << 8) + result]));
                    result = (result << 1) ^ bit;
                    if (match_bit != bit) {
                        break;
                    }
                }
            }
            
            while (result < 0x100) {
                result = (result << 1) ^ usize(@boolToInt(try rcoder.decode_bit(&probs[result])));
            }

            const res = @truncate(u8, result - 0x100);
            warn("decode_literal={}, {}\n", res, result);
            return res;
        }

        fn decode_distance(self: *Self, rcoder: *RangeDecoder, length: usize) !usize {
            const len_state = if (length > 3) 3 else length;
            const pos_slot = usize(try self.pos_slot_decoder[len_state].parse(rcoder));
            if (pos_slot < 4) {
                return pos_slot;
            }

            const num_direct_bits = (pos_slot >> 1) - 1;
            var result = (2 ^ (pos_slot & 1)) << @truncate(u6, num_direct_bits);

            if (pos_slot < 14) {
                result += usize(
                    try rcoder.parse_reverse_bit_tree(
                        num_direct_bits,
                        &self.pos_decoders,
                        result - pos_slot));
            } else {
                result += usize(try rcoder.get(num_direct_bits - 4)) << 4;
                result += usize(try self.align_decoder.parse_reverse(rcoder));
            }

            return result;
        }

    };
}
