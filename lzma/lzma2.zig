// -*- zig -*-
const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;
const warn = std.debug.warn;
const assert = std.debug.assert;
const assertError = std.debug.assertError;
const assertOrPanic = std.debug.assertOrPanic;

pub const DummyInStream = @import("lzstream.zig").DummyInStream;
pub const DummyOutStream = @import("lzstream.zig").DummyOutStream;

pub const lzbuffer = @import("lzbuffers.zig");
pub const LZAccumBuffer = lzbuffer.LZAccumBuffer;
pub const LZCircularBuffer = lzbuffer.LZCircularBuffer;
pub const Decoder = @import("lzma.zig").Decoder;
pub const LZMAParams = @import("lzma.zig").LZMAParams;


// XZ section, to go elsewhere...
const XZ_MAGIC_HEADER = [_]u8 {0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00};
const XZ_MAGIC_FOOTER = [_]u8 {0x59, 0x5A};

pub const CheckMethod = enum(u8) {
    None   = 0x00,
    CRC32  = 0x01,
    CRC64  = 0x04,
    SHA256 = 0x0A,
};

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
            //         parse_lzma(&mut decoder, input, status)?;
        }
    }

    try decoder.output.finish();
}

fn read_multibyte_int(input: []u8, consumed: *usize) !usize {
    var result: usize = 0;
    var cnt: u32 = 0;
    while (cnt < 9) : (cnt += 1) {
        // need range check?
        const byte = input[cnt];
        result ^= usize(byte & 0x7F) << @truncate(u6, cnt * 7);
        if ((byte & 0x80) == 0) {
            consumed.* = cnt + 1;
            return result;
        }
    }
    return error.InvalidMultiByte;
    
}

pub fn dissect_block(input: []u8) !void{
    // fake error
    if (input.len > 1024) {
        return error.Fake;
    }
    var pos: usize = 0;
    const block_flags = input[pos];
    const num_filters = block_flags & 0x03;
    const reserved = block_flags & 0x3c;
    if (reserved != 0) {
        return error.ReservedBitsSet;
    }
    const uncompressed_size_present = block_flags & 0x80 == 0x80;
    const compressed_size_present = block_flags & 0x40 == 0x40;
    warn("{}: block_flags={x}, uncompressed_size_present={},\ncompressed_size_present={}, num_filters={}\n",
         input.len, block_flags, uncompressed_size_present, compressed_size_present, num_filters);
    pos += @sizeOf(u8);
    var consumed: usize = 0;
    if (compressed_size_present) {
        const compressed_size = try read_multibyte_int(input[pos..], &consumed);
        warn("compressed_size={}, consumed={}\n", compressed_size, consumed);
        pos += consumed;
    }
    if (uncompressed_size_present) {
        consumed = 0;
        const uncompressed_size = try read_multibyte_int(input[pos..], &consumed);
        warn("uncompressed_size={}, consumed={}\n", uncompressed_size, consumed);
        pos += consumed;
    }
    if (num_filters > 0) {
        warn("Reading {} filters\n", num_filters);
        return error.NotImplemented;
    }
}

test "LZMA2.decode_stream" {
    // again from Python lzma.compress("The quick brown fox jumps over the lazy dog")
    // Header magic bytes: 0xfd,0x37,0x7a,0x58,0x5a,0x00 = 0xfd, 7, z, X, Z, 0x00
    // Next are the stream flags, 0x00, 0xZZ, then a 4-byte crc32
    // ...various stuff...
    // eventualy we get to the 0x21(!) LZMA2 filter id
    // 
    var input = "\xfd7zXZ\x00\x00\x01i\"\xde6\x02\xc0/+!\x01\x16\x00\xd2\xf9%\xae\x01\x00*The quick brown fox jumps over the lazy dog\x00\x009\xa3OA\x00\x01?+Wf\xe4\xd4\x90B\x99\r\x01\x00\x00\x00\x00\x01YZ";

    // quick check of some basic XZ facts
    var hdrpos: usize = 0;
    assert(mem.eql(u8, XZ_MAGIC_HEADER[0..], input[hdrpos..XZ_MAGIC_HEADER.len]));
    hdrpos += XZ_MAGIC_HEADER.len;
    assert(mem.eql(u8, XZ_MAGIC_FOOTER[0..], input[input.len - XZ_MAGIC_FOOTER.len..]));

    const header_flags = mem.readIntSlice(u16, input[hdrpos..], builtin.Endian.Big);
    hdrpos += @sizeOf(u16);
    const headcrc = mem.readIntSlice(u32, input[hdrpos..], builtin.Endian.Little);
    hdrpos += @sizeOf(u32);
    const blk_header_size = input[hdrpos];
    const real_header_size = (blk_header_size + 1) * 4;
    try dissect_block(input[hdrpos + 1 .. hdrpos + 1 + real_header_size]);
    warn("\nheadrcrc={}/{x:08}, blk_header_size={}, real_header_size={}, hdrpos={}\n",
         headcrc, headcrc, blk_header_size, real_header_size, hdrpos);
    hdrpos += real_header_size;

    var revpos = input.len - XZ_MAGIC_FOOTER.len - @sizeOf(u16);
    const footer_flags = mem.readIntSlice(u16, input[revpos..], builtin.Endian.Big);
    const hdrcheck = @intToEnum(CheckMethod, @truncate(u8, header_flags)); 
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

// fn parse_lzma<'a, R, W>(
//     decoder: &mut lzma::DecoderState<lzbuffer::LZAccumBuffer<'a, W>>,
//     input: &mut R,
//     status: u8,
// ) -> error::Result<()>
// where
//     R: io::BufRead,
//     W: io::Write,
// {
//     if status & 0x80 == 0 {
//         return Err(error::Error::LZMAError(format!(
//             "LZMA2 invalid status {}, must be 0, 1, 2 or >= 128",
//             status
//         )));
//     }

//     let reset_dict: bool;
//     let reset_state: bool;
//     let reset_props: bool;
//     match (status >> 5) & 0x3 {
//         0 => {
//             reset_dict = false;
//             reset_state = false;
//             reset_props = false;
//         }
//         1 => {
//             reset_dict = false;
//             reset_state = true;
//             reset_props = false;
//         }
//         2 => {
//             reset_dict = false;
//             reset_state = true;
//             reset_props = false;
//         }
//         3 => {
//             reset_dict = true;
//             reset_state = true;
//             reset_props = true;
//         }
//         _ => unreachable!(),
//     }

//     let unpacked_size = input.read_u16::<BigEndian>().or_else(|e| {
//         Err(error::Error::LZMAError(format!(
//             "LZMA2 expected unpacked size: {}",
//             e
//         )))
//     })?;
//     let unpacked_size = ((((status & 0x1F) as u64) << 16) | (unpacked_size as u64)) + 1;

//     let packed_size = input.read_u16::<BigEndian>().or_else(|e| {
//         Err(error::Error::LZMAError(format!(
//             "LZMA2 expected packed size: {}",
//             e
//         )))
//     })?;
//     let packed_size = (packed_size as u64) + 1;

//     info!(
//         "LZMA2 compressed block {{ unpacked_size: {}, packed_size: {}, reset_dict: {}, reset_state: {}, reset_props: {} }}",
//         unpacked_size,
//         packed_size,
//         reset_dict,
//         reset_state,
//         reset_props
//     );

//     if reset_dict {
//         decoder.output.reset()?;
//     }

//     if reset_state {
//         let lc: u32;
//         let lp: u32;
//         let mut pb: u32;

//         if reset_props {
//             let props = input.read_u8().or_else(|e| {
//                 Err(error::Error::LZMAError(format!(
//                     "LZMA2 expected new properties: {}",
//                     e
//                 )))
//             })?;

//             pb = props as u32;
//             if pb >= 225 {
//                 return Err(error::Error::LZMAError(format!(
//                     "LZMA2 invalid properties: {} must be < 225",
//                     pb
//                 )));
//             }

//             lc = pb % 9;
//             pb /= 9;
//             lp = pb % 5;
//             pb /= 5;

//             if lc + lp > 4 {
//                 return Err(error::Error::LZMAError(format!(
//                     "LZMA2 invalid properties: lc + lp ({} + {}) must be <= 4",
//                     lc, lp
//                 )));
//             }

//             info!("Properties {{ lc: {}, lp: {}, pb: {} }}", lc, lp, pb);
//         } else {
//             lc = decoder.lc;
//             lp = decoder.lp;
//             pb = decoder.pb;
//         }

//         decoder.reset_state(lc, lp, pb);
//     }

//     decoder.set_unpacked_size(Some(unpacked_size));

//     let mut taken = input.take(packed_size);
//     let mut rangecoder = rangecoder::RangeDecoder::new(&mut taken).or_else(|e| {
//         Err(error::Error::LZMAError(format!(
//             "LZMA input too short: {}",
//             e
//         )))
//     })?;
//     decoder.process(&mut rangecoder)
// }

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
