// -*- mode:zig; indent-tabs-mode:nil;  -*-
const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;
const assert = std.debug.assert;

const builtin = @import("builtin");

// From https://docs.rs/lz4-compress/0.1.1/src/lz4_compress/compress.rs.html

const DICTIONARY_SIZE: usize = 4096;

/// A consecutive sequence of bytes found in already encoded part of the input.
// #[derive(Copy, Clone, Debug)]
const Duplicate = struct {
    /// The number of bytes before our cursor, where the duplicate starts.
    offset: u16,
    /// The length beyond the four first bytes.
    ///
    /// Adding four to this number yields the actual length.
    extra_bytes: u32,
};

/// A LZ4 block.
///
/// This defines a single compression "unit", consisting of two parts, a number of raw literals,
/// and possibly a pointer to the already encoded buffer from which to copy.
// #[derive(Debug)]
const Block = struct {
    /// The length (in bytes) of the literals section.
    lit_len: u32,
    /// The duplicates section if any.
    ///
    /// Only the last block in a stream can lack of the duplicates section.
    dup: ?Duplicate,
};


/// An LZ4 encoder.
const Encoder = struct {
    const Self = this;
    /// The raw uncompressed input.
    input: []const u8,
    /// The compressed output.
    output: []u8,
    /// The number of bytes from the input that are encoded.
    curpos: usize,
    /// The number of bytes from output
    outpos: usize,
    /// The dictionary of previously encoded sequences.
    ///
    /// This is used to find duplicates in the stream so they are not written multiple times.
    ///
    /// Every four bytes are hashed, and in the resulting slot their position in the input buffer
    /// is placed. This way we can easily look up a candidate to back references.
    dict: [DICTIONARY_SIZE]u32,

    /// Go forward by some number of bytes.
    ///
    /// This will update the cursor and dictionary to reflect the now processed bytes.
    ///
    /// This returns `false` if all the input bytes are processed.
    fn go_forward(self: *Self, steps: usize) bool {
        //DEBUG: warn("go_forward({})\n", steps);
        // Go over all the bytes we are skipping and update the cursor and dictionary.
        var i: usize = 0;
        //assert((self.curpos + steps) <= self.input.len);
        while (i < steps) : (i += 1) {
            // Insert the cursor position into the dictionary.
            self.insert_cursor();
            // Increment the cursor.
            self.curpos += 1;
        }

        // Return `true` if there's more to read.
        return self.curpos <= self.input.len;
    }

    /// Insert the batch under the cursor into the dictionary.
    inline fn insert_cursor(self: *Self) void {
        // Make sure that there is at least one batch remaining.
        if (self.remaining_batch()) {
            // Insert the cursor into the table.
            self.dict[self.get_cur_hash()] = @intCast(u32, self.curpos & 0xffffffff);
        }
    }

    /// Check if there are any remaining batches.
    inline fn remaining_batch(self: *Self) bool {
        return (self.curpos + 4) < self.input.len;
    }

    /// Read a 4-byte "batch" from some position.
    ///
    /// This will read a native-endian 4-byte integer from some position.
    fn get_batch(self: *Self, n: usize) u32 {
        assert(self.remaining_batch());

        //NativeEndian::read_u32(self.input[n..])
        comptime {if (builtin.endian == builtin.Endian.Little) {
            return u32(self.input[n + 0])
                | u32(self.input[n + 1]) << 8
                | u32(self.input[n + 2]) << 16
                | u32(self.input[n + 3]) << 24;
        } else if (builtin.endian == builtin.Endian.Big) {
            return u32(self.input[n + 3])
                | u32(self.input[n + 2]) << 8
                | u32(self.input[n + 1]) << 16
                | u32(self.input[n + 0]) << 24;
        } else {
            @compileError("Unsupported endian\n");
        }}
    }

    /// Read the batch at the cursor.
    inline fn get_batch_at_cursor(self: *Self) u32 {
        return self.get_batch(self.curpos);
    }

    /// Get the hash of the current four bytes below the cursor.
    ///
    /// This is guaranteed to be below `DICTIONARY_SIZE`.
    inline fn get_cur_hash(self: *Self) usize {
        //  just for fun, try some fibonacci hashing
        return (usize(self.get_batch_at_cursor()) *% 2654435769) & (DICTIONARY_SIZE - 1);
        // >> ((@sizeOf(usize) * 8) - 12);
        // Use PCG transform to generate a relatively good hash of the four bytes batch at the
        // cursor.
        // var x: usize = self.get_batch_at_cursor() *% 0xa4d94a4f;
        // const a = x >> 16;
        // const b = @intCast(u6, (x >> 30) & 0x3f);
        // x ^= a >> b;
        // x *%= 0xa4d94a4f;

        // const hh = x % DICTIONARY_SIZE;
        // warn("h={x04} vs hh={x04} {x}\n", h, hh, DICTIONARY_SIZE - 1);

        // return hh;
    }

    /// Find a duplicate of the current batch.
    ///
    /// If any duplicate is found, a tuple `(position, size - 4)` is returned.
    fn find_duplicate(self: *Self) ?Duplicate {
        // If there is no remaining batch, we return none.
        if (self.remaining_batch() == false) {
            return null;
        }

        // Find a candidate in the dictionary by hashing the current four bytes.
        const candidate: u32 = self.dict[self.get_cur_hash()];
        // DEBUG: warn("candidate = {x}\n", candidate);

        // Three requirements to the candidate exists:
        // - The candidate is not the trap value (0xFFFFFFFF), which represents an empty bucket.
        // - We should not return a position which is merely a hash collision, so w that the
        //   candidate actually matches what we search for.
        // - We can address up to 16-bit offset, hence we are only able to address the candidate if
        //   its offset is less than or equals to 0xFFFF.
        if ((candidate != 0xffffffff)
            and (self.get_batch(candidate) == self.get_batch_at_cursor())
            and ((self.curpos - candidate) <= 0xFFFF))
        {
            // DEBUG: warn("candidate = {x}, curpos={x}\n", candidate, self.curpos);
            // TODO: Decipher this from rust into zig...
            // Calculate the "extension bytes", i.e. the duplicate bytes beyond the batch. These
            // are the number of prefix bytes shared between the match and needle.
            //     let ext = self.input[self.curpos + 4..]
            //         .iter()
            //         .zip(&self.input[candidate + 4..])
            //         .take_while(|&(a, b)| a == b)
            //         .count();
            var ext: u32 = 0;
            var i: u32 = 4;
            while (i < self.input.len) : (i += 1) {
                if ((candidate + i) >= self.input.len) {
                    break;
                }
                if ((self.curpos + i) >= self.input.len) {
                    break;
                }
                if (self.input[self.curpos + i] != self.input[candidate + i]) {
                    break;
                }
                ext += 1;
            }
            // DEBUG: warn("ext={}\n", ext);

            return Duplicate {
                 .offset = @intCast(u16, (self.curpos - candidate) & 0xffff),
                 .extra_bytes = ext,
             };
        } else {
            // DEBUG: warn("null\n");
            return null;
        }
    }

    /// Write an integer to the output in LSIC format.
    inline fn write_integer(self: *Self, n: u32) void {
        assert((self.outpos + n) <= self.output.len);
        var nn = n;
        // Write the 0xFF bytes as long as the integer is higher than said value.
        while (nn >= 0xFF) {
            nn -= 0xFF;
            self.push_token(0xff);
        }

        // Write the remaining byte.
        self.push_token(@intCast(u8, nn & 0xff));
    }

    /// Read the block of the top of the stream.
    fn pop_block(self: *Self) Block {
        // The length of the literals section.
        var lit: u32 = 0;

        while (true) {
            // DEBG: warn("lit={}\n", lit);
            // Search for a duplicate.
            var optional_dup = self.find_duplicate();
            if (optional_dup) |dup| {
                // We found a duplicate, so the literals section is over...
                // Move forward. Note that `ext` is actually the steps minus 4, because of the
                // minimum matchlenght, so we need to add 4.
                _ = self.go_forward(dup.extra_bytes + 4);
                // DEBUG: warn("dup\n");
                return Block {
                    .lit_len = lit,
                    .dup = dup,
                };
            }

            // Try to move forward.
            if (self.go_forward(1) == false) {
                // We reached the end of the stream, and no duplicates section follows.
                return Block {
                    .lit_len = lit,
                    .dup = null,
                };
            }

            // No duplicates found yet, so extend the literals section.
            lit += 1;

            assert(lit <= self.input.len);
        }
    }

    inline fn push_token(self: *Self, t: u8) void {
        self.output[self.outpos] = t;
        self.outpos += 1;
    }


    fn complete(self: *Self) bool {
        // DEBUG: warn("input len={}, output len={}, curpos={}\n",
        //     self.input.len, self.output.len, self.curpos);
        // Construct one block at a time.
        while (true) {
            // The start of the literals section.
            const start = self.curpos;
            // DEBUG: warn("start={}\n", start);
            assert(start <= self.input.len);

            // Read the next block into two sections, the literals and the duplicates.
            const block = self.pop_block();

            // Generate the higher half of the token.
            var token = if (block.lit_len < 0xF)
                // Since we can fit the literals length into it, there is no need for saturation.
                @intCast(u8, block.lit_len & 0xf) << 4
            else
               // We were unable to fit the literals into it, so we saturate to 0xF. We will later
               // write the extensional value through LSIC encoding.
                0xF0;
            // Generate the lower half of the token, the duplicates length.
            const dup_extra_len = if (block.dup) |dup| dup.extra_bytes else 0 ;
            // DEBUG: warn("token={x},dup_extra_len={},block.lit_len={}\n",
            //     token, dup_extra_len, block.lit_len);
            token |= if (dup_extra_len < 0xF)
            // We could fit it in.
                @intCast(u8, dup_extra_len & 0xff)
            else
            // We were unable to fit it in, so we default to 0xF, which will later be extended
            // by LSIC encoding.
                0xF;

            // DEBUG: warn("token={x},dup_extra_len={},block.lit_len={}\n",
            //     token, dup_extra_len, block.lit_len);
            // Push the token to the output stream.
            self.push_token(token);

            // If we were unable to fit the literals length into the token, write the extensional
            // part through LSIC.
            if (block.lit_len >= 0xF) {
                self.write_integer(block.lit_len - 0xF);
            }

            // Now, write the actual literals.
            // self.output.extend_from_slice(&self.input[start..start + block.lit_len]);
            // DEBUG: warn("block.lit_len={}\n", block.lit_len);
            {
                var i: usize = 0;
                while (i < block.lit_len) : (i += 1) {
                    self.push_token(self.input[start + i]);
                }
            }

            //if let Some(Duplicate { offset, .. }) = block.dup {
            if (block.dup) |dup| {
                // Wait! There's more. Now, we encode the duplicates section.

                // Push the offset in little endian.
                self.push_token(@intCast(u8, dup.offset & 0xff));
                self.push_token(@intCast(u8, (dup.offset >> 8) & 0xff));

                // If we were unable to fit the duplicates length into the token, write the
                // extensional part through LSIC.
                if (dup_extra_len >= 0xF) {
                    self.write_integer(dup_extra_len - 0xF);
                }
            } else {
                // DEBUG: warn("done\n");
                break;
            }
        }
        return false;
    }

};

/// A LZ4 decoder.
///
/// This will decode in accordance to the LZ4 format. It represents a particular state of the
/// decompressor.
const Decoder = struct {
    const Self = this;
    /// The compressed input.
    input: []const u8,
    /// The decompressed output.
    output: []u8,
    inpos: usize,
    outpos: usize,
    /// The current block's "token".
    ///
    /// This token contains to 4-bit "fields", a higher and a lower, representing the literals'
    /// length and the back reference's length, respectively. LSIC is used if either are their
    /// maximal values.
    token: u8,

    /// Check if input is empty
    inline fn input_is_empty(self: *Self) bool {
        return self.inpos >= self.input.len;
    }

    /// Internal (partial) function for `take`.
    //#[inline]
    inline fn take_imp(self: *Self, n: usize) ![]const u8 {
        // Check if we have enough bytes left.
        if ((self.inpos + n) > self.input.len) {
            // No extra bytes. This is clearly not expected, so we return an error.
            return error.ExpectedAnotherByte;
        } else {
            // Take the first n bytes.
            var res = self.input[self.inpos..self.inpos + n];
            self.inpos += n;
            // Shift the stream to left, so that it is no longer the first byte.
            //*input = &input[n..];

            // Return the former first byte.
            return res;
        }
    }

    /// Pop n bytes from the start of the input stream.
    fn take(self: *Self, n: usize) ! []const u8 {
        return self.take_imp(n);
    }

    /// Write a buffer to the output stream.
    ///
    /// The reason this doesn't take `&mut self` is that we need partial borrowing due to the rules
    /// of the borrow checker. For this reason, we instead take some number of segregated
    /// references so we can read and write them independently.
    inline fn output(self: *Self, buf: []const u8) void {
        // We use simple memcpy to extend the vector.
        //output.extend_from_slice(&buf[..buf.len()]);
        var i: usize = 0;
        while (i < buf.len) {
            self.output[self.outpos + i] = buf[i];
            self.outpos += 1;
        }
    }

    /// Write an already decompressed match to the output stream.
    ///
    /// This is used for the essential part of the algorithm: deduplication. We start at some
    /// position `start` and then keep pushing the following element until we've added
    /// `match_length` elements.
    fn duplicate(self: *Self, start: usize, match_length: usize) void {
        //DEBUG: warn("duplicate({}, {}) {}\n", start, match_length, self.outpos);
        // We cannot simply use memcpy or `extend_from_slice`, because these do not allow
        // self-referential copies: http://ticki.github.io/img/lz4_runs_encoding_diagram.svg
        //for i in start..start + match_length {
        var i: usize = start;
        //DEBUG: warn("{} : {} {}\n", i, self.output.len, self.outpos);
        while (i < (start + match_length)) : (i += 1) {
            // const b = self.output[i];
            //DEBUG: warn("dup=0x{x}\n", b);
            self.output[self.outpos] = self.output[i];
            self.outpos += 1;
        }
    }

    /// Read an integer LSIC (linear small integer code) encoded.
    ///
    /// In LZ4, we encode small integers in a way that we can have an arbitrary number of bytes. In
    /// particular, we add the bytes repeatedly until we hit a non-0xFF byte. When we do, we add
    /// this byte to our sum and terminate the loop.
    ///
    /// # Example
    ///
    /// ```notest
    ///     255, 255, 255, 4, 2, 3, 4, 6, 7
    /// ```
    ///
    /// is encoded to _255 + 255 + 255 + 4 = 769_. The bytes after the first 4 is ignored, because
    /// 4 is the first non-0xFF byte.
    //#[inline]
    inline fn read_integer(self: *Self) !usize {
        // We start at zero and count upwards.
        var n: usize = 0;
        // If this byte takes value 255 (the maximum value it can take), another byte is read
        // and added to the sum. This repeats until a byte lower than 255 is read.
        while (true) {
            // We add the next byte until we get a byte which we add to the counting variable.
            const extra = try self.take(1);
            n += usize(extra[0]);

            // We continue if we got 255.
            if (extra[0] != 0xFF) {
                break;
            }
        }

        return n;
    }

    /// Read a little-endian 16-bit integer from the input stream.
    inline fn read_u16(self: *Self) !u16 {
        // We use byteorder to read an u16 in little endian.
        const v = try self.take(2);
        if (builtin.endian == builtin.Endian.Little) {
            return (u16(v[1]) << 8) | v[0];
        } else if (builtin.endian == builtin.Endian.Big){
            return (u16(v[0]) << 8) | v[1];
        } else {
            @compileError("Unknown endianess\n");
        }
    }

    /// Read the literals section of a block.
    ///
    /// The literals section encodes some bytes which are to be copied to the output without any
    /// modification.
    ///
    /// It consists of two parts:
    ///
    /// 1. An LSIC integer extension to the literals length as defined by the first part of the
    ///    token, if it takes the highest value (15).
    /// 2. The literals themself.
    fn read_literal_section(self: *Self) !void {
        // The higher token is the literals part of the token. It takes a value from 0 to 15.
        var literal = usize(self.token >> 4);
        //DEBUG: warn("literal=0x{x}, token=0x{x}\n", literal, self.token);
        // If the initial value is 15, it is indicated that another byte will be read and added to
        // it.
        if (literal == 15) {
            // The literal length took the maximal value, indicating that there is more than 15
            // literal bytes. We read the extra integer.
            literal += try self.read_integer();
        }

        // Now we know the literal length. The number will be used to indicate how long the
        // following literal copied to the output buffer is.

        // Read the literals segment and output them without processing.
        // Zigify Self::output(&mut self.output, Self::take_imp(&mut self.input, literal)?);
        // DEBUG: warn("input@{}=0x{x}\n", self.inpos,self.input[self.inpos]);
        var i: usize = 0;
        const taken = try self.take(literal);
        // DEBUG: warn("taken.len={}\n", taken.len);
        for (taken) |v, vi| {
            self.output[self.outpos] = v;
            self.outpos += 1;
        }

        return;
    }

    /// Read the duplicates section of the block.
    ///
    /// The duplicates section serves to reference an already decoded segment. This consists of two
    /// parts:
    ///
    /// 1. A 16-bit little-endian integer defining the "offset", i.e. how long back we need to go
    ///    in the decoded buffer and copy.
    /// 2. An LSIC integer extension to the duplicate length as defined by the first part of the
    ///    token, if it takes the highest value (15).
    fn read_duplicate_section(self: *Self) !void {
        // DEBUG: warn("read_duplicate_section\n");
        // Now, we will obtain the offset which we will use to copy from the output. It is an
        // 16-bit integer.
        const offset = try self.read_u16();

        // Obtain the initial match length. The match length is the length of the duplicate segment
        // which will later be copied from data previously decompressed into the output buffer. The
        // initial length is derived from the second part of the token (the lower nibble), we read
        // earlier. Since having a match length of less than 4 would mean negative compression
        // ratio, we start at 4.
        var match_length = usize(4 + (self.token & 0xF));

        // The intial match length can maximally be 19. As with the literal length, this indicates
        // that there are more bytes to read.
        if (match_length == (4 + 15)) {
            // The match length took the maximal value, indicating
            // that there is more bytes. We read the extra integer.
            match_length += try self.read_integer();
        }

        // We now copy from the already decompressed buffer. This
        // allows us for storing duplicates by simply referencing the
        // other location.

        // Calculate the start of this duplicate segment. We use
        // wrapping subtraction to avoid overflow checks, which we
        // will catch later.
        const start = self.outpos - usize(offset);

        // DEBUG: warn("offset={}, match_length={}, start={}, inpos={}\n",
        //     offset, match_length, start, self.inpos);

        // We'll do a bound check to avoid panicking.
        if (start < self.output.len) {
            // Write the duplicate segment to the output buffer.
            self.duplicate(start, match_length);

            return;
        } else {
            return error.OffsetOutOfBounds;
        }
    }

    /// Complete the decompression by reading all the blocks.
    ///
    /// # Decompressing a block
    ///
    /// Blocks consists of:
    ///  - A 1 byte token
    ///      * A 4 bit integer $t_1$.
    ///      * A 4 bit integer $t_2$.
    ///  - A $n$ byte sequence of 0xFF bytes (if $t_1 \neq 15$, then $n = 0$).
    ///  - $x$ non-0xFF 8-bit integers, L (if $t_1 = 15$, $x = 1$, else $x = 0$).
    ///  - $t_1 + 15n + L$ bytes of uncompressed data (literals).
    ///  - 16-bits offset (little endian), $a$.
    ///  - A $m$ byte sequence of 0xFF bytes (if $t_2 \neq 15$, then $m = 0$).
    ///  - $y$ non-0xFF 8-bit integers, $c$ (if $t_2 = 15$, $y = 1$, else $y = 0$).
    ///
    /// First, the literals are copied directly and unprocessed to the output buffer, then (after
    /// the involved parameters are read) $t_2 + 15m + c$ bytes are copied from the output buffer
    /// at position $a + 4$ and appended to the output buffer. Note that this copy can be
    /// overlapping.
    //#[inline]
    fn complete(self: *Self) !void {
        // Exhaust the decoder by reading and decompressing all blocks
        // until the remaining buffer is empty.
        while (self.input_is_empty() == false) {
            // Read the token. The token is the first byte in a
            // block. It is divided into two 4-bit subtokens, the
            // higher and the lower.
            var x = try self.take(1);
            self.token = x[0];
            //DEBUG: warn("token=0x{x}\n", self.token);

            // Now, we read the literals section.
            try self.read_literal_section();

            // If the input stream is emptied, we break out of the
            // loop. This is only the case in the end of the stream,
            // since the block is intact otherwise.
            if (self.input_is_empty()) {
                break;
            }

            // Now, we read the duplicates section.
            try self.read_duplicate_section();
        }

        return;
    }

};


/// Decompress all bytes of `input` into `output`.
pub fn decompress_into(input: []const u8, output: []u8) !void {
    // Decode into our vector.
    var decoder = Decoder {
        .input = input,
        .output = output,
        .inpos = 0,
        .outpos = 0,
        .token = 0,
    };
    return decoder.complete();
}

/// Decompress all bytes of `input`.
pub fn decompress(input: []const u8, output: []u8) !void {
    return decompress_into(input[0..], output[0..]);
}

/// Compress all bytes of `input` into `output`.
pub fn compress_into(input: []const u8, output: []u8) bool {
    var encoder = Encoder {
        .input = input,
        .output = output,
        .curpos = 0,
        .outpos = 0,
        .dict = []u32 {@maxValue(u32)} ** DICTIONARY_SIZE,
    };

    var r = encoder.complete();
    //warn("curpos={}, outpos={}\n", encoder.curpos, encoder.outpos);
    return r;
}

/// Compress all bytes of `input`.
pub fn compress(input: []const u8, output: []u8) bool {
    // In most cases, the compression won't expand the size, so we set
    // the input size as capacity.
    return compress_into(input[0..], output[0..]);
}

pub fn main() !void {
    var input = "abcdabcdabcdabcd";
    var compressed = []u8 {0} ** 1024;
    var uncompressed = []u8 {0} ** 1024;
    warn("## compressing ##\n");
    var comp = compress(input[0..], compressed[0..]);
    warn("## decompressing ({}) ##\n", comp);
    var decomp = try decompress(compressed[0..input.len + 2], uncompressed[0..]);
    assert(mem.eql(u8, uncompressed[0..input.len], input[0..]));
    warn("done\n");
}

test "compress" {
    //var input  = "aaaaaabcbcbcbc"; // 0x11, b'a', 1, 0, 0x22, b'b', b'c', 2, 0
    // var input = "a49"; // 0x30, b'a', b'4', b'9', = {0x30, 0x61, 0x34, 0x39, 0x0 <repeats 1020 times>}
    // var input = "aaaaaa"; // 0x11, b'a', 1, 0, = {0x11, 0x61, 0x1, 0x0 <repeats 1021 times>}
    var input = "The quick brown fox jumps over the lazy dog";
    var compressed = []u8 {0} ** 1024;
    var uncompressed = []u8 {0} ** 1024;
    warn("## compressing ##\n");
    var comp = compress(input[0..], compressed[0..]);
    warn("## decompressing ({}) ##\n", comp);
    var decomp = try decompress(compressed[0..input.len + 2], uncompressed[0..]);
    assert(mem.eql(u8, uncompressed[0..input.len], input[0..]));
    warn("done\n");
}
