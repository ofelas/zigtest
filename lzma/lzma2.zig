// -*- zig -*-
const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;
const assert = std.debug.assert;

const File = std.fs.File;

pub const DummyInStream = @import("lzstream.zig").DummyInStream;
pub const DummyOutStream = @import("lzstream.zig").DummyOutStream;

pub const xz = @import("xz.zig");
pub const lzbuffer = @import("lzbuffers.zig");
pub const LZAccumBuffer = lzbuffer.LZAccumBuffer;
pub const LZCircularBuffer = lzbuffer.LZCircularBuffer;
pub const Decoder = @import("lzma.zig").Decoder;
pub const LZMAParams = @import("lzma.zig").LZMAParams;
pub const RangeDecoder = @import("rangecoder.zig").RangeDecoder;

pub fn decode_buffer(input: *DummyInStream, ostream: *DummyOutStream, obuf: []u8) !void {
    var accum = LZAccumBuffer.from_stream(ostream, obuf);
    var params = LZMAParams {.lc = 0, .lp = 0, .pb = 0, .dict_size = 0x4000, .unpacked_size = null, .pos = 0};
    var decoder = Decoder(LZAccumBuffer).init(accum, params);

    while (true) {
        const status = try input.read_u8();
        //         Err(error::Error::LZMAError(format!(
        //             "LZMA2 expected new status: {}",
        //             e
        //         )))
        //     })?;

        warn("LZMA2 status: {x}\n", status);

        if (status == 0) {
            warn("LZMA2 end of input\n");
            break;
        } else if (status == 1) {
            // uncompressed reset dict
            warn("uncompressed reset dict\n");
            try parse_uncompressed(&decoder, input, true);
        } else if (status == 2) {
            // uncompressed no reset
            warn("uncompressed no reset\n");
            try parse_uncompressed(&decoder, input, false);
        } else {
            warn("lzma...\n");
            try parse_lzma(&decoder, input, status);
        }
    }

    try decoder.output.finish();
}

pub fn dissect_block(input: []u8) !usize{
    // fake error
    if (input.len > 1024) {
        return error.Fake;
    }
    var pos: usize = 0;
    warn("{x}\n", input[0..16]);
    const blk_header_size = input[pos];
    pos += @sizeOf(u8);
    // skip index indicator
    //pos += @sizeOf(u8);
    const real_header_size = (blk_header_size + 1) * 4;
    warn("blk_header_size={}, real_header_size={}, pos={}\n",
         blk_header_size, real_header_size, pos);
    const block_flags = input[pos];
    pos += @sizeOf(u8);
    const num_filters = (block_flags & 0x03) + 1;
    const reserved = block_flags & 0x3c;
    const uncompressed_size_present = block_flags & 0x80 == 0x80;
    const compressed_size_present = block_flags & 0x40 == 0x40;
    warn("{}: block_flags={x}, uncompressed_size_present={},\ncompressed_size_present={}, num_filters={}\n",
         input.len, block_flags, uncompressed_size_present, compressed_size_present, num_filters);
    if (reserved != 0) {
        warn("block_flags={x}, reserved={}\n", block_flags, reserved);
        //return error.ReservedBitsSet;
    }
    var consumed: usize = 0;
    if (compressed_size_present) {
        const compressed_size = try xz.read_multibyte_int(input[pos..], &consumed);
        warn("compressed_size={}, consumed={}\n", compressed_size, consumed);
        pos += consumed;
    }
    if (uncompressed_size_present) {
        consumed = 0;
        const uncompressed_size = try xz.read_multibyte_int(input[pos..], &consumed);
        warn("uncompressed_size={}, consumed={}\n", uncompressed_size, consumed);
        pos += consumed;
    }
    if (num_filters > 0) {
        warn("Reading {} filters\n", num_filters);
        var cnt: @typeOf(num_filters) = 0;
        while (cnt < num_filters) : (cnt += 1) {
            consumed = 0;
            const filter_id = try xz.read_multibyte_int(input[pos..], &consumed);
            warn("filter_id={x}, consumed={}\n", filter_id, consumed);
            pos += consumed;
            consumed = 0;
            const filter_size = try xz.read_multibyte_int(input[pos..], &consumed);
            warn("filter_size={}, consumed={}\n", filter_size, consumed);
            pos += consumed + filter_size;
            if (filter_id == 0x21) {
                // check size of filter, this must by 1
                const bits: u8 = input[pos - filter_size] & 0x3f;
                const dict_size = u32(2 | (bits & 1)) << @truncate(u5, (bits / 2) + 11);
                warn("dict_size={}/{x}, bits={x}\n", dict_size, dict_size, bits);
            }
        }
        //return error.NotImplemented;
    }
    pos = real_header_size;
    var vli = xz.read_multibyte_int(input[pos..], &consumed);
    pos += consumed;
    warn("num_records={}/{x}\n", vli, vli);
    vli = xz.read_multibyte_int(input[pos..], &consumed);
    pos += consumed;
    warn("num_records={}/{x}\n", vli, vli);

    return real_header_size;
}

test "LZMA2.decode_stream.uncompressed" {
    // again from Python lzma.compress("The quick brown fox jumps over the lazy dog")
    // Header magic bytes: 0xfd,0x37,0x7a,0x58,0x5a,0x00 = 0xfd, 7, z, X, Z, 0x00
    // Next are the stream flags, 0x00, 0xZZ, then a 4-byte crc32
    // ...various stuff...
    // eventualy we get to the 0x21(!) LZMA2 filter id
    // 
    var input = "\xfd7zXZ\x00\x00\x01i\"\xde6\x02\xc0/+!\x01\x16\x00\xd2\xf9%\xae\x01\x00*The quick brown fox jumps over the lazy dog\x00\x009\xa3OA\x00\x01?+Wf\xe4\xd4\x90B\x99\r\x01\x00\x00\x00\x00\x01YZ";

    // quick check of some basic XZ facts
    var hdrpos: usize = 0;
    assert(mem.eql(u8, xz.XZ_MAGIC_HEADER[0..], input[hdrpos..xz.XZ_MAGIC_HEADER.len]));
    hdrpos += xz.XZ_MAGIC_HEADER.len;
    assert(mem.eql(u8, xz.XZ_MAGIC_FOOTER[0..], input[input.len - xz.XZ_MAGIC_FOOTER.len..]));

    const header_flags = mem.readIntSlice(u16, input[hdrpos..], builtin.Endian.Big);
    warn("header_flags={}\n", header_flags);
    hdrpos += @sizeOf(u16);
    const headcrc = mem.readIntSlice(u32, input[hdrpos..], builtin.Endian.Little);
    hdrpos += @sizeOf(u32);
    const blk_header_size = input[hdrpos];
    const real_header_size = (blk_header_size + 1) * 4;
    hdrpos += try dissect_block(input[hdrpos .. ]);
    warn("\nheadrcrc={}/{x:08}, blk_header_size={}, real_header_size={}, hdrpos={}\n",
         headcrc, headcrc, blk_header_size, real_header_size, hdrpos);

    var revpos = input.len - xz.XZ_MAGIC_FOOTER.len - @sizeOf(u16);
    const footer_flags = mem.readIntSlice(u16, input[revpos..], builtin.Endian.Big);
    const hdrcheck = @intToEnum(xz.CheckMethod, @truncate(u8, header_flags)); 
    warn("header_flags={x:04}, {}, footer_flags={x:04}\n", header_flags, hdrcheck, footer_flags);
    assert(header_flags == 0x0001);
    assert(header_flags == footer_flags);
    revpos -= @sizeOf(u32);
    const backward_size = mem.readIntSlice(u32, input[revpos..], builtin.Endian.Little);
    const real_backward_size = (backward_size + 1) * 4;
    revpos -= @sizeOf(u32);
    var crc = mem.readIntSlice(u32, input[revpos..], builtin.Endian.Little);
    warn("backward_size={}/{x:08}, real={}, crc={}/{x:08}\n",
         backward_size, backward_size, real_backward_size, crc, crc);
    warn("revpos={},{}\n", revpos, input.len - revpos);


    // swiftly skipping header and some block/stream info
    var instream = DummyInStream.new(input[hdrpos..revpos]);
    var outbuf = [_]u8{0} ** 256;
    var outstreambuf = [_]u8{0} ** 256;
    var outstream = DummyOutStream.new(outstreambuf[0..]);

    try decode_buffer(&instream, &outstream, outbuf[0..]);
}

test "LZMA2.decode_stream.compressed" {
    const file_name = "tests/lzstream.zig.xz";
    var input = @embedFile(file_name);
    {
        var file = try File.openRead(file_name);
        defer file.close();
        const file_size = try file.getEndPos();
        warn("File is {} bytes ({})\n", file_size, input.len);
        assert(file_size == input.len);
    }
    // quick check of some basic XZ facts
    var hdrpos: usize = 0;
    assert(mem.eql(u8, xz.XZ_MAGIC_HEADER[0..], input[hdrpos..xz.XZ_MAGIC_HEADER.len]));
    hdrpos += xz.XZ_MAGIC_HEADER.len;
    //assert(mem.eql(u8, XZ_MAGIC_FOOTER[0..], input[input.len - XZ_MAGIC_FOOTER.len..]));

    const header_flags = mem.readIntSlice(u16, input[hdrpos..], builtin.Endian.Big);
    hdrpos += @sizeOf(u16);
    const hcrc = mem.readIntSlice(u32, input[hdrpos..], builtin.Endian.Little);
    hdrpos += @sizeOf(u32);
    const hdrcheck = @intToEnum(xz.CheckMethod, @truncate(u8, header_flags)); 
    warn("header_flags={}, hdrcheck={}, hdrpos={}\n", header_flags, hdrcheck, hdrpos);
    // There might be a CRC32, CRC64 or a SHA256 header checksum
    var headcrc = xz.CrcType {.None = {}};
    const blk_header_size = input[hdrpos];
    //hdrpos += @sizeOf(u8);
    // From here on we are processing blocks?!?
    hdrpos += try dissect_block(input[hdrpos.. hdrpos + 64]);
    var revpos = input.len - xz.XZ_MAGIC_FOOTER.len - @sizeOf(u16);
    const footer_flags = mem.readIntSlice(u16, input[revpos..], builtin.Endian.Big);
    warn("header_flags={x:04}, {}, footer_flags={x:04}\n", header_flags, hdrcheck, footer_flags);
    //assert(header_flags == 0x0001);
    assert(header_flags == footer_flags);
    revpos -= @sizeOf(u32);
    const backward_size = mem.readIntSlice(u32, input[revpos..], builtin.Endian.Little);
    const real_backward_size = (backward_size + 1) * 4;
    revpos -= @sizeOf(u32);
    var crc = mem.readIntSlice(u32, input[revpos..], builtin.Endian.Little);
    warn("backward_size={}/{x:08}, real={}, crc={}/{x:08}\n",
         backward_size, backward_size, real_backward_size, crc, crc);
    warn("revpos={},{}\n", revpos, input.len - revpos);
    warn("input[{}]={x:02}, {c}\n", revpos, input[revpos], input[revpos]);
    var instream = DummyInStream.new(input[hdrpos..revpos + @sizeOf(u32)]);
    var outbuf = [_]u8{0} ** 4096;
    var outstreambuf = [_]u8{0} ** 4096;
    var outstream = DummyOutStream.new(outstreambuf[0..]);

    try decode_buffer(&instream, &outstream, outbuf[0..]);
}

fn parse_lzma(decoder: *Decoder(LZAccumBuffer), input: *DummyInStream, status: u8) !void {
    if (status & 0x80 == 0) {
        warn("LZMA2 invalid status {}, must be 0, 1, 2 or >= 128\n", status);
        return error.InvalidStatus;
    }

    var reset_dict: bool = false;
    var reset_state: bool = false;
    var reset_props: bool = false;
    switch ((status >> 5) & 0b11) {
        0b00 => {
            reset_dict = false;
            reset_state = false;
            reset_props = false;
        },
        0b01 => {
            reset_dict = false;
            reset_state = true;
            reset_props = false;
        },
        0b10 => {
            reset_dict = false;
            reset_state = true;
            reset_props = false;
        },
        0b11 => {
            reset_dict = true;
            reset_state = true;
            reset_props = true;
        },
        else => {}, //unreachable(),
    }

    const unpacked_size = try input.read_u16(builtin.Endian.Big);
    const real_unpacked_size = (((u64(status & 0x1F)) << 16) | u64(unpacked_size)) + 1;
    warn("unpacked_size={}, real={}\n", unpacked_size, real_unpacked_size);
    const packed_size = try input.read_u16(builtin.Endian.Big);
    const real_packed_size = u64(packed_size) + 1;
    warn("packed_size={}, real={}, input.len={}\n",
         packed_size, real_packed_size, input.buf.len);

    warn("LZMA2 compressed block {{unpacked_size: {}, packed_size: {}, reset_dict: {}, reset_state: {}, reset_props: {}}}\n",
         real_unpacked_size, real_packed_size, reset_dict, reset_state, reset_props);

    if (reset_dict) {
        try decoder.output.reset();
    }

    if (reset_state) {
        var lc: u32 = undefined;
        var lp: u32 = undefined;
        var pb: u32 = undefined;

        if (reset_props) {
            const props = try input.read_u8(); // .or_else(|e| {
            //      Err(error::Error::LZMAError(format!(
            //          "LZMA2 expected new properties: {}",
            //          e
            //      )))
            //  })?;

            pb = u32(props);
            if (pb >= 225) {
                warn("LZMA2 invalid properties: pb ({}) must be < 225\n",
                     pb);
                return error.InvalidProperties;
            }

             lc = pb % 9;
             pb /= 9;
             lp = pb % 5;
             pb /= 5;

            if ((lc + lp) > 4) {
                warn("LZMA2 invalid properties: lc + lp ({} + {}) must be <= 4\n",
                     lc, lp);
            }

            warn("Properties {{lc: {}, lp: {}, pb: {}}}\n", lc, lp, pb);
        } else {
            lc = decoder.lc;
            lp = decoder.lp;
            pb = decoder.pb;
        }
        decoder.reset_state(lc, lp, pb);
    }

    decoder.set_unpacked_size(real_unpacked_size);
    warn("input.pos={}\n", input.pos);

    {
        // get a slice of the input, actually it seems like it wants an input stream...
        var taken = DummyInStream.new(try input.take(real_packed_size));
        var rangecoder = try RangeDecoder.new(&taken); //.or_else(|e| {
        //         Err(error::Error::LZMAError(format!(
        //             "LZMA input too short: {}",
        //             e
        //         )))
        //     })?;
        if (decoder.process(&rangecoder)) |_| {
            warn("### Completed {}\n", decoder.output.len);
        } else |err| {
            warn("{}\n", decoder);
            return err;
        }
    }
}

fn parse_uncompressed(decoder: *Decoder(LZAccumBuffer), input: *DummyInStream,  reset_dict: bool) !void {
    var sunpacked_size = try input.read_u16(builtin.Endian.Big);
    const unpacked_size = usize(sunpacked_size) + 1;

     warn("LZMA2 uncompressed block unpacked_size={}, reset_dict={} (sunpacked_size={x})\n",
          unpacked_size, reset_dict, sunpacked_size);
    
    if (reset_dict) {
        try decoder.output.reset();
    }

    // need an allocator, a bit hackish right now...
    // maybe we could read straight into the decoder.output?!?
    // e.g. with input.take()?
    var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;
    var buf = try allocator.alloc(u8, unpacked_size);
    warn("allocated buffer of {} bytes ({})\n", buf.len, unpacked_size);

    if (input.read_exact(buf[0..])) |_| {
        try decoder.output.append_bytes(buf[0..]);
    } else |err| {
        return error.NotEnoughInput;
    }
}
