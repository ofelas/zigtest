// -*- mode:zig; -*-
// based on C sources with the following info
// /*
//  Copyright (c) 2011, Micael Hildenborg
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of Micael Hildenborg nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY Micael Hildenborg ''AS IS'' AND ANY
//  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL Micael Hildenborg BE LIABLE FOR ANY
//  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
//  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
//  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACgcc rotate instructionT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
//  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//  */
//
// /*
//  Contributors:
//  Gustav
//  Several members in the gamedev.se forum.
//  Gregory Petrosyan
//  */

//const want_static_eval: bool = false;

const io = @import("std").io;
const debug = @import("std").debug;

pub const Sha1Digest = u8;
const Sha1BitCount = 160;
pub const Sha1DigestSize = Sha1BitCount/Sha1Digest.bit_count; // 20
pub const Sha1HexDigestSize = (Sha1DigestSize * 2) + 1;       // 40 + 1 for termination

const Sha1State = u32;
const Sha1StateSize = Sha1BitCount/Sha1State.bit_count; // 5

const Sha1Buffer = u32;
const Sha1BufferSize = Sha1BitCount/2; // 80

// [5]u32 -> TODO array container initState
const INIT_STATE = []u32{
    0x67452301,
    0xefcdab89,
    0x98badcfe,
    0x10325476,
    0xc3d2e1f0,
};

//#static_eval_enable(!want_static_eval)
inline fn clearBuffer(cb: []Sha1Buffer) {
   for (cb) |*d| { *d = 0 };
}

//#static_eval_enable(!want_static_eval)
inline fn initState(res: []Sha1State) {
    res[0] = u32(0x67452301);
    res[1] = u32(0xefcdab89);
    res[2] = u32(0x98badcfe);
    res[3] = u32(0x10325476);
    res[4] = u32(0xc3d2e1f0);
}

//#static_eval_enable(!want_static_eval)
inline fn upperbitmask(bits: u32) -> u32{
   0xffffffff >> bits
}

//#static_eval_enable(!want_static_eval)
inline fn lowerbitmask(bits: u32) -> u32{
   ((0xffffffff) >> (32 - bits) << (32 - bits))
}

// circular shift...ror/rol
//#static_eval_enable(!want_static_eval)
inline fn rot(value: u32, bits: u32) -> u32 {
    //const um = upperbitmask(bits);
    //const lm = lowerbitmask(bits);
    //debug.assert(um | lm == 0xffffffff);
    //const v1 = (value & upperbitmask(bits)) << bits;
    //const v2 = (value & lowerbitmask(bits)) >> (32 - bits);
    //return v1 | v2;
    return (value <<% bits) | (value >> (32 - bits));
    //var v: %u32 =% (value <<% bits) | (value >> (32 - bits));
    //return %%v;
    //return (value << bits) | (value >> (u32)(-(i32)(bits)&31));
}

error WeHaveABug;

//#static_eval_enable(want_static_eval)
inline fn innerHash(state: []Sha1State, w: []Sha1Buffer) -> %void {
    var a  = state[0];
    var b = state[1];
    var c = state[2];
    var d = state[3];
    var e = state[4];

    var round = usize(0);

    while (round < 16; round += 1) {
        // sha1macro((b & c) | (~b & d), u32(0x5a827999))
        const t1 = rot(a, 5) +% ((b & c) | (~b & d)) +% e +% u32(0x5a827999) +% w[round];
        e = d;
        d = c;
        c = rot(b, 30);
        b = a;
        a = t1;
    }

    while (round < 20; round += 1) {
        w[round] = rot((w[round - 3] ^ w[round - 8] ^ w[round - 14] ^ w[round - 16]), 1);
        // sha1macro((b & c) | (~b & d), u32(0x5a827999))
        const t2 = rot(a, 5) +% ((b & c) | (~b & d)) +% e +% u32(0x5a827999) +% w[round];
        e = d;
        d = c;
        c = rot(b, 30);
        b = a;
        a = t2;
    }

    while (round < 40; round += 1) {
        w[round] = rot((w[round - 3] ^ w[round - 8] ^ w[round - 14] ^ w[round - 16]), 1);
        // sha1macro(b ^ c ^ d, u32(0x6ed9eba1))
        var t4 = rot(a, 5);
        t4 +%= (b ^ c ^ d) +% e +% u32(0x6ed9eba1) +% w[round];
        e = d;
        d = c;
        c = rot(b, 30);
        b = a;
        a = t4;
    }

    while (round < 60; round += 1) {
        w[round] = rot((w[round - 3] ^ w[round - 8] ^ w[round - 14] ^ w[round - 16]), 1);
        // sha1macro((b & c) | (b & d) | (c & d), 0x8f1bbcdc)
        const t6 = rot(a, 5) +% ((b & c) | (b & d) | (c & d)) +% e +% u32(0x8f1bbcdc) +% w[round];
        e = d;
        d = c;
        c = rot(b, 30);
        b = a;
        a = t6;
    }

    while (round < 80; round += 1)
    {
        w[round] = rot((w[round - 3] ^ w[round - 8] ^ w[round - 14] ^ w[round - 16]), 1);
        // sha1macro(b ^ c ^ d, u32(0xca62c1d6))
        const t8 = ((b ^ c ^ d)) +% rot(a, 5) +% e +% u32(0xca62c1d6) +% w[round];
        e = d;
        d = c;
        c = rot(b, 30);
        b = a;
        a = t8;
    }

    state[0] +%= a;
    state[1] +%= b;
    state[2] +%= c;
    state[3] +%= d;
    state[4] +%= e;

    // if (state[0] == 0) {
    //     // need the following line
    //     %%io.stdout.write("state[0]="); %%io.stdout.printInt(u32, state[0]); %%io.stdout.printf("\n");
    //     return error.WeHaveABug;
    // }
}

//#static_eval_enable(!want_static_eval)
inline fn align(comptime T: type, v: i32, alignment: T) -> T {
    ((alignment - 1) - (T(v) & (alignment - 1))) << (alignment - 1)
}

//#static_eval_enable(!want_static_eval)
fn computeInternal(src: []const u8, sz: usize, result: []Sha1Digest) -> %void {
    var state: [5]Sha1State = undefined;
    var w: [80]Sha1Buffer = undefined;
    const byte_len = sz;
    // the length of the input may be less that 64!? hence i32/isize
    const end_of_full_blocks = i32(byte_len) - 64;
    var end_current_block = i32(0);
    var current_block = i32(0);

    initState(state);
    // for (state) |*d, i| { *d = INIT_STATE[i]; }
    clearBuffer(w);
    //for (w) |*d| { *d = 0 }; // clearBuffer() alternative

    while (current_block <= end_of_full_blocks) {
        end_current_block = current_block + 64;
        { var i: usize = 0; while (current_block < end_current_block) {
            w[i] = u32(src[usize(current_block + 3)])
                 | u32(src[usize(current_block + 2)]) <<% 8
                 | u32(src[usize(current_block + 1)]) <<% 16
                 | u32(src[usize(current_block)]) <<% 24;
            current_block +%= 4;
            i += 1;
        }}

        %%innerHash(state, w);
    }

    // Handle last and not full 64 byte block if existing
    end_current_block = i32(byte_len) -% current_block;
    // w = zeroes; // makes no difference
    clearBuffer(w);
    //for (w) |*d| { *d = 0 };
    var last_block_bytes = i32(0);
    while (last_block_bytes < end_current_block) {
        const value = u32(src[usize(last_block_bytes + current_block)])
                    << ((3 - (u32(last_block_bytes) & 3)) <<% 3);
        // const widx = usize(last_block_bytes >> 2);
        w[usize(last_block_bytes >> 2)] |= value;
        last_block_bytes += 1;
    }
    w[usize(last_block_bytes >> 2)] |= u32(0x80) <<% align(u32, last_block_bytes, 4);
                                    // ((3 - (u32(last_block_bytes) & 3)) <<% 3);

    if (end_current_block >= 56) {
        %%innerHash(state, w);
        clearBuffer(w);
    }

    w[15] = u32(byte_len <<% 3);

    %%innerHash(state, w);

    { var z = usize(0); while (z < Sha1DigestSize; z +%= 1) {
        result[z] = u8(((state[z >> 2]) >> ((3-(z & 3)) <<% 3)) & 0xff);
    }}
}

pub fn sha1(src: []const u8, sz: usize, h: [Sha1DigestSize]Sha1Digest) -> %void {
    computeInternal(src, sz, h)
}

const HexChars = "0123456789abcdef";
pub fn hexdigest(h: [Sha1DigestSize]Sha1Digest, dest: []u8) {
    for (h) |v, i| {
        dest[i << 1] = HexChars[(v & 0xf0) >> 4];
        dest[(i << 1) + 1] = HexChars[v & 0xf];
    }
}


/// Sha1Context
pub const Sha1Context = struct {
    byteoffset: usize,           // current buffer offset
    blockoffset: usize,          // current block offset
    consumed: usize,             // total amount of bytes processed
    state: [Sha1StateSize]u32,   // state
    buffer: [80]u32,             // working area
    charbuf: [64]u8,             // we keep incomplete bytes/blocks here

    /// use this first to initialize the context
    pub fn init(ctx: &Sha1Context) {
        ctx.byteoffset = 0;
        ctx.blockoffset = 0;
        ctx.consumed = 0;
        initState(ctx.state);
        clearBuffer(ctx.buffer)
    }

    /// incrementally feed it data
    pub fn update(ctx: &Sha1Context, src: []u8, bytecount: usize) {
        // fill the buffer, do the transform/innerHash for every block (64 bytes)
        // we have ctx.bytecount and get bytecount more
        // how many blocks will there be? (1 << 6) is 64
        ctx.consumed +%= bytecount;
        var srcidx = usize(0);
        var blocks = (ctx.byteoffset + bytecount) >> 6;
        // now a rethink; getting 1 byte at a time will eventually trigger blocks
        // but we did not get that much in one go
        if (blocks > 0) {
            // copy to charbuf
            var cidx = ctx.byteoffset;
            while(cidx < 64; {cidx += 1; srcidx += 1;}) {
                ctx.charbuf[cidx] = src[srcidx];
            }
            cidx = 0;
            while (cidx < 64; cidx += 1) {
                ctx.buffer[cidx >> 2] |= u32(ctx.charbuf[cidx]) << u32((3 - (cidx & 3)) <<% 3);
            }
            blocks -= 1;
            ctx.byteoffset = 0;
            %%innerHash(ctx.state, ctx.buffer);
            var current_block = usize(0);
            while (current_block < blocks) {
                const end_current_block = srcidx + 64;
                var i = usize(0);
                while (srcidx < end_current_block) {
                    ctx.buffer[i] = u32(src[srcidx + 3])
                        | u32(src[srcidx + 2]) <<% 8
                        | u32(src[srcidx + 1]) <<% 16
                        | u32(src[srcidx]) <<% 24;
                    srcidx +%= 4;
                    ctx.byteoffset +%= 4;
                    i += 1;
                }
                current_block +%= 1;
                %%innerHash(ctx.state, ctx.buffer);
                // ok, start over
                ctx.byteoffset = 0;
            }
        }
        // any bytes left goes to the charbuf...
        while (srcidx < bytecount; {srcidx += 1; ctx.byteoffset += 1;}) {
            // refill the charbuf from src...
            ctx.charbuf[ctx.byteoffset] = src[srcidx];
        }

    }

    /// and finally end it
    pub fn final(ctx: &Sha1Context, digest: []u8) {
        // do the final step, if there is anything left...
        var origsize = ctx.byteoffset;
        clearBuffer(ctx.buffer);
        // %%io.stdout.printInt(@typeOf(origsize), (64 - origsize)); %%io.stdout.printf(" final refill\n");
        ctx.charbuf[ctx.byteoffset] = 0x80;
        ctx.byteoffset +%= 1;
        var cidx = usize(0);
        while (cidx < ctx.byteoffset; cidx += 1) {
            ctx.buffer[cidx >> 2] |= u32(ctx.charbuf[cidx]) << u32((3 - (cidx & 3)) <<% 3);
        }

        if (origsize >= 56) {
            // TODO: remains to be tested
            %%innerHash(ctx.state, ctx.buffer);
            clearBuffer(ctx.buffer);
        }

        ctx.buffer[15] = u32(ctx.consumed <<% 3);

        %%innerHash(ctx.state, ctx.buffer);

        { var z = usize(0);
            while (z < Sha1DigestSize; z +%= 1) {
                digest[z] = u8(((ctx.state[z >> 2]) >> ((3-(z & 3)) <<% 3)) & 0xff);
            }
        }
        // is it a safety measure to clear the data?
        ctx.init(); // %%innerHash(ctx.state, ctx.buffer);
    }
};
