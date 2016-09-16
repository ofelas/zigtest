// -*- indent-tabs-mode:nil; -*-
// based on C sources with the followin info
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
const want_static_eval: bool = false;

const io = @import("std").io;
const debug = @import("std").debug;

pub const Sha1DigestSize = 20;
pub const Sha1Digest = [Sha1DigestSize]u8;
const Sha1State = [5]u32;
const Sha1StateAddr = [5]&u32;
const Sha1Buffer = [80]u32;
//const Sha1HexString = [80]u8;

// [5]u32 -> TODO array container init
const INIT_STATE = []u32{
    0x67452301,
    0xefcdab89,
    0x98badcfe,
    0x10325476,
    0xc3d2e1f0,
};

#static_eval_enable(!want_static_eval)
fn clearBuffer(cb: Sha1Buffer) {
   for (cb) |*d| { *d = 0 };
}

#static_eval_enable(!want_static_eval)
fn init(res: Sha1State) {
    res[0] = u32(0x67452301);
    res[1] = u32(0xefcdab89);
    res[2] = u32(0x98badcfe);
    res[3] = u32(0x10325476);
    res[4] = u32(0xc3d2e1f0);
}

#static_eval_enable(!want_static_eval)
fn upperbitmask(bits: u32) -> u32{
   0xffffffff >> bits
}

#static_eval_enable(!want_static_eval)
fn lowerbitmask(bits: u32) -> u32{
   ((0xffffffff) >> (32 - bits) << (32 - bits))
}

// circular shift...ror/rol
#static_eval_enable(!want_static_eval)
fn rot(value: u32, bits: u32) -> u32 {
    const um = upperbitmask(bits);
    const lm = lowerbitmask(bits);
    debug.assert(um | lm == 0xffffffff);
    const v1 = (value & um) << bits;
    const v2 = (value & lm) >> (32 - bits);
    v1 | v2
    //var v: %u32 =% (value <<% bits) | (value >> (32 - bits));
    //return %%v;
}

error WeHaveABug;

#static_eval_enable(want_static_eval)
fn innerHash(state: Sha1State, w: Sha1Buffer) -> %void {
    var a: @typeOf(state[0]) = state[0];
    var b: u32 = state[1];
    var c: u32 = state[2];
    var d: u32 = state[3];
    var e: u32 = state[4];

    var round = usize(0);

    while (round < 16; round += 1) {
        // sha1macro((b & c) | (~b & d), u32(0x5a827999))
        var v: u32 = rot(a, 5);
        var t1: u32 = v +% ((b & c) | (~b & d));
        t1 +%= e +% u32(0x5a827999) +% w[round];
        e = d;
        d = c;
        c = rot(b, 30);
        b = a;
        a = t1;
    }

    while (round < 20; round += 1) {
        w[round] = rot((w[round - 3] ^ w[round - 8] ^ w[round - 14] ^ w[round - 16]), 1);
        // sha1macro((b & c) | (~b & d), u32(0x5a827999))
        var t2 = rot(a, 5);
        t2 +%= ((b & c) | (~b & d)) +% e +% u32(0x5a827999) +% w[round];
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
        var t6 = rot(a, 5);
        t6 +%= ((b & c) | (b & d) | (c & d)) +% e +% u32(0x8f1bbcdc) +% w[round];
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
        var t8 = ((b ^ c ^ d));
        t8 +%= rot(a, 5) +% e +% u32(0xca62c1d6) +% w[round];
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

    if (state[0] == 0) {
        // need the following line
        %%io.stdout.write("state[0]="); %%io.stdout.printInt(u32, state[0]); %%io.stdout.printf("\n");
        return error.WeHaveABug;
    }
}

//#static_eval_enable(!want_static_eval)
fn align(inline T: type, v: i32, alignment: T) -> T {
    ((alignment - 1) - (T(v) & (alignment - 1))) << (alignment - 1)
}

//#static_eval_enable(!want_static_eval)
fn computeInternal(src: []const u8, sz: usize, result: Sha1Digest) -> %void {
    var state: Sha1State = zeroes;
    var w: Sha1Buffer = zeroes;
    // changed, see local alternatives below
    // init(state);
    // clearBuffer(w);
    for (w) |*d| { *d = 0 }; // clearBuffer() alternative
    const byte_len = sz;
    // the length of the input may be less that 64!? hence i32/isize
    const end_of_full_blocks = i32(byte_len) - 64;
    var end_current_block = i32(0);
    var current_block = i32(0);

    // init(state) alternative, this fixes the state initialization
    for (state) |*d, i| { *d = INIT_STATE[i]; }
    // state[0] = u32(0x67452301);
    // state[1] = u32(0xefcdab89);
    // state[2] = u32(0x98badcfe);
    // state[3] = u32(0x10325476);
    // state[4] = u32(0xc3d2e1f0);

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
    // clearBuffer(w);
    for (w) |*d| { *d = 0 };
    var last_block_bytes = i32(0);
    while (last_block_bytes < end_current_block) {
        var value = u32(src[usize(last_block_bytes + current_block)])
                    << ((3 - (u32(last_block_bytes) & 3)) <<% 3);
        // const widx = usize(last_block_bytes >> 2);
        w[usize(last_block_bytes >> 2)] |= value;
        last_block_bytes += 1;
    }
    w[usize(last_block_bytes >> 2)] = w[usize(last_block_bytes >> 2)]
                                    | u32(0x80) <<% align(u32, last_block_bytes, 4);
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

#static_eval_enable(want_static_eval)
pub fn sha1(src: []u8, sz: usize, h: Sha1Digest) -> %void {
    computeInternal(src, sz, h)
}

const HexChars = "0123456789abcdef";
#static_eval_enable(want_static_eval)
pub fn hexdigest(h: Sha1Digest, dest: []u8) {
    for (h) |v, i| {
        dest[i << 1] = HexChars[(v & 0xf0) >> 4];
        dest[(i << 1) + 1] = HexChars[v & 0xf];
    }
}
