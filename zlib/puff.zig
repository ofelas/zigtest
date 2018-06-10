// -*- mode:zig; indent-tabs-mode:nil; comment-start:"// "; comment-end:""; -*-
const warn = @import("std").debug.warn;
const assert = @import("std").debug.assert;

 // * puff.c
 // * Copyright (C) 2002-2013 Mark Adler
 // * For conditions of distribution and use, see copyright notice in puff.h
 // * version 2.3, 21 Jan 2013
 // *
 // * puff.c is a simple inflate written to be an unambiguous way to specify the
 // * deflate format.  It is not written for speed but rather simplicity.  As a
 // * side benefit, this code might actually be useful when small code is more
 // * important than speed, such as bootstrap applications.  For typical deflate
 // * data, zlib's inflate() is about four times as fast as puff().  zlib's
 // * inflate compiles to around 20K on my machine, whereas puff.c compiles to
 // * around 4K on my machine (a PowerPC using GNU cc).  If the faster decode()
 // * function here is used, then puff() is only twice as slow as zlib's
 // * inflate().
 // *
 // * All dynamically allocated memory comes from the stack.  The stack required
 // * is less than 2K bytes.  This code is compatible with 16-bit int's and
 // * assumes that long's are at least 32 bits.  puff.c uses the short data blktype,
 // * assumed to be 16 bits, for arrays in order to conserve memory.  The code
 // * works whether integers are stored big endian or little endian.
 // *
 // * In the comments below are "Format notes" that describe the inflate process
 // * and document some of the less obvious aspects of the format.  This source
 // * code is meant to supplement RFC 1951, which formally describes the deflate
 // * format:
 // *
 // *    http://www.zlib.org/rfc-deflate.html

const PuffError = error {
    OutOfInput,
    NotEnoughInput,
    OutOfCodes,
    InvalidSymbol,
    IncompleteCode,
};

// * Maximums for allocations and loops.  It is not useful to change these --
// * they are fixed by the deflate format.
const MAXBITS = 15;              // maximum bits in a code
const MAXLCODES = 286;           // maximum number of literal/length codes
const MAXDCODES = 30;            // maximum number of distance codes
const MAXCODES = (MAXLCODES+MAXDCODES);  // maximum codes lengths to read
const FIXLCODES = 288;           // number of fixed literal/length codes

const DBG = false;

// input and output state
const state = struct {
    // output state
    // unsigned char *out;         //* output buffer */
    outbuf: []u8,
    outlen: usize,       //* available space at out */
    outcnt: usize,       //* bytes written to out so far */

    // input state
    // const unsigned char *in;    //* input buffer */
    inbuf: []const u8,
    inlen: usize,        //* available input at in */
    incnt: usize,        //* bytes read so far */
    bitbuf: u32,                 //* bit buffer */
    bitcnt: u5,                 //* number of bits in bit buffer */

    //* input limit error return state for bits() and decode() */
    // jmp_buf env;

    // Return need bits from the input stream.  This always leaves less than
    // eight bits in the buffer.  bits() works properly for need == 0.
    //
    // Format notes:
    //
    // - Bits are stored in bytes from the least significant bit to the most
    //   significant bit.  Therefore bits are dropped from the bottom of the bit
    //   buffer, using shift right, and new bytes are appended to the top of the
    //   bit buffer, using shift left.
    fn bits(s: *state, need: u5) !u32 {
        assert(need <= 20);
        // load at least need bits into val
        var val: u32 = s.*.bitbuf; // bit accumulator (can use up to 20 bits)
        while (s.*.bitcnt < need) {
            if (s.*.incnt == s.*.inlen) {
                //longjmp(s.env, 1);         // out of input
                return error.OufOfInput;
            }
            val |= u32(s.inbuf[s.*.incnt]) << s.*.bitcnt;
            s.*.incnt += 1;
            s.*.bitcnt += 8;
        }

        // drop need bits and update buffer, always zero to seven bits left
        s.bitbuf = (val >> need);
        s.bitcnt -= need;

        // return need bits, zeroing the bits above that
        return u32(val & ((u32(1) << need) - 1));
    }

    // Decode a code from the stream s using huffman table h.  Return the symbol or
    // a negative value if there is an error.  If all of the lengths are zero, i.e.
    // an empty code, or if the code is incomplete and an invalid code is received,
    // then -10 is returned after reading MAXBITS bits.
    //
    // Format notes:
    //
    // - The codes as stored in the compressed data are bit-reversed relative to
    //   a simple integer ordering of codes of the same lengths.  Hence below the
    //   bits are pulled from the compressed data one at a time and used to
    //   build the code value reversed from what is in the stream in order to
    //   permit simple integer comparisons for decoding.  A table-based decoding
    //   scheme (as used in zlib) does not need to do this reversal.
    //
    // - The first code for the shortest length is all zeros.  Subsequent codes of
    //   the same length are simply integer increments of the previous code.  When
    //   moving up a length, a zero bit is appended to the code.  For a complete
    //   code, the last code of the longest length will be all ones.
    //
    // - Incomplete codes are handled by this decoder, since they are permitted
    //   in the deflate format.  See the format notes for fixed() and dynamic().
    fn decode(s: *state, h: *huffman) !u32 {
        var len: u32 = 0;            // current number of bits in code
        var code: u32 = 0;           // len bits being decoded
        var first: i32 = 0;          // first code of length len
        var index: u32 = 0;          // index of first code of length len in symbol table

        len = 1;
        while (len <= MAXBITS) {
            code |= try s.bits(1);  // get next bit
            const count = i32(h.*.count[len]); // number of codes of length len
            if ((i32(code) - count) < first) {      // if length len, return symbol
                //warn("code={x}, count={}, {}, first={}, len={}\n", code, count, i32(code) - count, first, len);
                return u32((h.*.symbol)[index + (code - u32(first))]);
            }
            index += u32(count);                 // else update for next length
            first += count;
            first <<= 1;
            code <<= 1;
            len += 1;
        }

    return error.OutOfCodes;    // ran out of codes
    }

    // Process a stored block.
    //
    // Format notes:
    //
    // - After the two-bit stored block blktype (00), the stored block length and
    //   stored bytes are byte-aligned for fast copying.  Therefore any leftover
    //   bits in the byte that has the last bit of the blktype, as many as seven, are
    //   discarded.  The value of the discarded bits are not defined and should not
    //   be checked against any expectation.
    //
    // - The second inverted copy of the stored block length does not have to be
    //   checked, but it's probably a good idea to do so anyway.
    //
    // - A stored block can have zero length.  This is sometimes used to byte-align
    //   subsets of the compressed data for random access or partial recovery.
    fn stored(s: *state) !u32 {
        var len: usize = 0;       // length of stored block
        
        // discard leftover bits from current byte (assumes s->bitcnt < 8)
        s.bitbuf = 0;
        s.bitcnt = 0;

        // get length and check against its one's complement
        if ((s.incnt + 4) > s.inlen) {
            return error.NotEnoughInput; // not enough input
        }
        len = s.inbuf[s.incnt];
        s.incnt += 1;
        len |= usize(s.inbuf[s.incnt]) << 8;
        s.incnt += 1;
        if (s.inbuf[s.incnt] != (~len & 0xff)) {
            if (s.inbuf[s.incnt + 1] != ((~len >> 8) & 0xff)) {
                s.incnt += 2;
                return error.ComplementMismatch;                              // didn't match complement!
            }
        }
        s.incnt += 2;               // compensate for s.incnt++ int if statements above

        // copy len bytes from in to out
        if ((s.incnt + len) > s.inlen) {
            return error.NotEnoughInput; // not enough input
        }
        if (s.outbuf.len == 0) {
            if ((s.outcnt + len) > s.outlen) {
                return 1;       // not enough output space
            }
            while (len > 0) {
                s.outbuf[s.outcnt] = s.inbuf[s.incnt];
                s.outcnt += 1;
                s.incnt += 1;
                len -= 1;
            }
        } else {                // just scanning
            s.outcnt += len;
            s.incnt += len;
        }

    //* done with a valid stored block */
    return 0;
}

};

// Huffman code decoding tables.  count[1..MAXBITS] is the number of symbols of
// each length, which for a canonical code are stepped through in order.
// symbol[] are the symbol values in canonical order, where the number of
// entries is the sum of the counts in count[].  The decoding process can be
// seen in the function decode() below.
const huffman = struct {
    count: [*]u16,       // number of symbols of each length
    symbol: [*]u16,      // canonically ordered symbols
};



// A faster version of decode() for real applications of this code.   It's not
// as readable, but it makes puff() twice as fast.  And it only makes the code
// a few percent larger.
fn fdecode(s: *state, h: *huffman) !u32 {
// {
//     int len;            /* current number of bits in code */
//     int code;           /* len bits being decoded */
//     int first;          /* first code of length len */
//     int count;          /* number of codes of length len */
//     int index;          /* index of first code of length len in symbol table */
//     int bitbuf;         /* bits from stream */
//     int left;           /* bits left in next or left to process */
//     short *next;        /* next number of codes */

    var bitbuf = s.*.bitbuf;
    var left = s.*.bitcnt;
    var code: u32 = 0;
    var first: u32 = 0;
    var index: u32 = 0;
    var len: u32 = 1;
    var next: u32 = 1; // h.*.count[1];
    while (true) {
        while (left > 0) {
            code |= bitbuf & 1;
            bitbuf >>= 1;
            const count = h.*.count[next];
            next += 1;
            if (code - count < first) { // if length len, return symbol 
                s.*.bitbuf = bitbuf;
                s.*.bitcnt = u5(s.*.bitcnt - len) & 7;
                return u32(h.*.symbol[index + (code - first)]);
            }
            index += count;             // else update for next length
            first += count;
            first <<= 1;
            code <<= 1;
            len += 1;
            left -= 1;
        }
        left = u5(MAXBITS+1) - u5(len);
        if (left == 0) {
            break;
        }
        if (s.*.incnt == s.*.inlen) {
            //             longjmp(s->env, 1);         /* out of input */
            return error.OutOfInput;
        }
        bitbuf = s.*.inbuf[s.incnt];
        s.incnt += 1;
         if (left > 8) {
             left = 8;
         }
    }
    return error.OutOfCodes;    // ran out of codes
}

// Given the list of code lengths length[0..n-1] representing a canonical
// Huffman code for n symbols, construct the tables required to decode those
// codes.  Those tables are the number of codes of each length, and the symbols
// sorted by length, retaining their original order within each length.  The
// return value is zero for a complete code set, negative for an over-
// subscribed code set, and positive for an incomplete code set.  The tables
// can be used if the return value is zero or positive, but they cannot be used
// if the return value is negative.  If the return value is zero, it is not
// possible for decode() using that table to return an error--any stream of
// enough bits will resolve to a symbol.  If the return value is positive, then
// it is possible for decode() using that table to return an error for received
// codes past the end of the incomplete lengths.
//
// Not used by decode(), but used for error checking, h->count[0] is the number
// of the n symbols not in the code.  So n - h->count[0] is the number of
// codes.  This is useful for checking for incomplete codes that have more than
// one symbol, which is an error in a dynamic block.
//
// Assumption: for all i in 0..n-1, 0 <= length[i] <= MAXBITS
// This is assured by the construction of the length arrays in dynamic() and
// fixed() and is not verified by construct().
//
// Format notes:
//
// - Permitted and expected examples of incomplete codes are one of the fixed
//   codes and any code with a single symbol which in deflate is coded as one
//   bit instead of zero bits.  See the format notes for fixed() and dynamic().
//
// - Within a given code length, the symbols are kept in ascending order for
//   the code bits definition.
fn construct(h: *huffman, length: []u16, n: usize) !u32 {
    var symbol: usize = 0;         // current symbol when stepping through length[]
    var len: usize = 0;            // current length when stepping through h->count[]
    var left: i32 = 0;           // number of possible codes left of current length
    var offs: [MAXBITS+1]u16 = undefined;      // offsets in symbol table for each length

    // count number of codes of each length
    len = 0;
    while (len <= MAXBITS) {
        h.*.count[len] = 0;
        len += 1;
    }
    symbol = 0;
    while (symbol < n) : (symbol += 1) {
        h.*.count[length[symbol]] += 1;   // assumes lengths are within bounds
    }
    if (h.*.count[0] == n) {             // no codes!
        return 0;                       // complete, but decode() will fail
    }

    // check for an over-subscribed or incomplete set of lengths
    left = 1;                           // one possible code of zero length
    len = 1;
    while (len <= MAXBITS) {
        left <<= 1;                     // one more bit, double codes left
        left -= i32(h.count[len]);          // deduct count from possible codes
        if (left < 0) {
            return error.OverSubscribed;                // over-subscribed--return negative
        }
        len += 1;
    }                                   // left > 0 means incomplete
              
    // generate offsets into symbol table for each length for sorting
    offs[1] = 0;
    len = 1;
    while (len < MAXBITS) {
        offs[len + 1] = offs[len] + h.count[len];
        len += 1;
    }

    // put symbols in table sorted by length, by symbol order within
    // each length
    symbol = 0;
    while (symbol < n) {
        if (length[symbol] != 0) {
            h.symbol[offs[length[symbol]]] = u16(symbol);
            offs[length[symbol]] += 1;
        }
        symbol += 1;
    }
    // return zero for complete set, positive for incomplete set
    // warn("{} codes left\n", left);
    return u32(left);
}

// Decode literal/length and distance codes until an end-of-block code.
//
// Format notes:
//
// - Compressed data that is after the block blktype if fixed or after the code
//   description if dynamic is a combination of literals and length/distance
//   pairs terminated by and end-of-block code.  Literals are simply Huffman
//   coded bytes.  A length/distance pair is a coded length followed by a
//   coded distance to represent a string that occurs earlier in the
//   uncompressed data that occurs again at the current location.
//
// - Literals, lengths, and the end-of-block code are combined into a single
//   code of up to 286 symbols.  They are 256 literals (0..255), 29 length
//   symbols (257..285), and the end-of-block symbol (256).
//
// - There are 256 possible lengths (3..258), and so 29 symbols are not enough
//   to represent all of those.  Lengths 3..10 and 258 are in fact represented
//   by just a length symbol.  Lengths 11..257 are represented as a symbol and
//   some number of extra bits that are added as an integer to the base length
//   of the length symbol.  The number of extra bits is determined by the base
//   length symbol.  These are in the static arrays below, lens[] for the base
//   lengths and lext[] for the corresponding number of extra bits.
//
// - The reason that 258 gets its own symbol is that the longest length is used
//   often in highly redundant files.  Note that 258 can also be coded as the
//   base value 227 plus the maximum extra value of 31.  While a good deflate
//   should never do this, it is not an error, and should be decoded properly.
//
// - If a length is decoded, including its extra bits if any, then it is
//   followed a distance code.  There are up to 30 distance symbols.  Again
//   there are many more possible distances (1..32768), so extra bits are added
//   to a base value represented by the symbol.  The distances 1..4 get their
//   own symbol, but the rest require extra bits.  The base distances and
//   corresponding number of extra bits are below in the static arrays dist[]
//   and dext[].
//
// - Literal bytes are simply written to the output.  A length/distance pair is
//   an instruction to copy previously uncompressed bytes to the output.  The
//   copy is from distance bytes back in the output stream, copying for length
//   bytes.
//
// - Distances pointing before the beginning of the output data are not
//   permitted.
//
// - Overlapped copies, where the length is greater than the distance, are
//   allowed and common.  For example, a distance of one and a length of 258
//   simply copies the last byte 258 times.  A distance of four and a length of
//   twelve copies the last four bytes three times.  A simple forward copy
//   ignoring whether the length is greater than the distance or not implements
//   this correctly.  You should not use memcpy() since its behavior is not
//   defined for overlapped arrays.  You should not use memmove() or bcopy()
//   since though their behavior -is- defined for overlapping arrays, it is
//   defined to do the wrong thing in this case.

fn codes(s: *state, plencode: *huffman, pdistcode: *huffman) !u32 {
    var symbol: u32 = 0;         // decoded symbol
    var len: u32 = 0;            // length for copy
    var distance: u32 = 0;           // distance for copy
    const lens = [29]u16 { // Size base for length codes 257..285
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
        35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258};
    const lext = [29]u5 { // Extra bits for length codes 257..285
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0};
    const dists = [30]u16 { // Offset base for distance codes 0..29
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
        257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
        8193, 12289, 16385, 24577};
    const dext = [30]u5 { // Extra bits for distance codes 0..29
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
        7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
        12, 12, 13, 13};

    // decode literals and length/distance pairs
    while (true) {
        symbol = try s.decode(plencode);
        if (symbol < 256) {             // literal: symbol is the byte
            //warn("literal symbol {x}\n", symbol);
            // write out the literal
            if (s.*.outbuf.len != 0) {
                if (s.*.outcnt == s.*.outlen) {
                    return error.OutputFull;
                }
                s.*.outbuf[s.*.outcnt] = u8(symbol);
            }
            s.*.outcnt += 1;
        }
        else if (symbol > 256) {        // length
            // get and compute length
            symbol -= 257;
            const sy = symbol;
            if (symbol >= 29) {
                return error.InvalidFixedCode; // invalid fixed code
            }
            len = lens[symbol];
            len += try s.bits(lext[u5(symbol)]);

            // get and check distance
            symbol = try s.decode(pdistcode);
            //warn("symbol={}\n", symbol);
            // symbol cannot be < 0 here, we use u32...
            if (symbol < 0) {
                return error.InvalidSymbol; // invalid symbol
            }
            distance = dists[symbol];
            distance += try s.bits(dext[u5(symbol)]);
            //warn("sy={}, symbol={}, len={}, distance={}\n", sy, symbol, len, distance);
            if (distance > s.*.outcnt) {
                 return error.DistanceTooFarBack;
            }

            // copy length bytes from distance bytes back
            if (s.*.outbuf.len > 0) {
                if ((s.*.outcnt + len) > s.*.outlen) {
                    return error.OutputFull;
                }
                while (len > 0) {
                    s.*.outbuf[s.*.outcnt] = s.*.outbuf[s.*.outcnt - distance];
// #ifdef INFLATE_ALLOW_INVALID_DISTANCE_TOOFAR_ARRR
//                         distance > s->outcnt ?
//                             0 :
//                            s.outbuf[s.outcnt - distance];
// #endif
                    s.*.outcnt += 1;
                    len -= 1;
                }
            } else  {
                s.*.outcnt += len;
            }
        }
        if (symbol == 256) {    // end of symbol block
            warn("end of symbol block\n");
            break;
        }
    } //while (symbol != 256);            /* end of block symbol */

    //* done with a valid fixed or dynamic block */
    return 0;
}

// Process a fixed codes block.
//
// Format notes:
//
// - This block blktype can be useful for compressing small amounts of data for
//   which the size of the code descriptions in a dynamic block exceeds the
//   benefit of custom codes for that block.  For fixed codes, no bits are
//   spent on code descriptions.  Instead the code lengths for literal/length
//   codes and distance codes are fixed.  The specific lengths for each symbol
//   can be seen in the "for" loops below.
//
// - The literal/length code is complete, but has two symbols that are invalid
//   and should result in an error if received.  This cannot be implemented
//   simply as an incomplete code since those two symbols are in the "middle"
//   of the code.  They are eight bits long and the longest literal/length \
//   code is nine bits.  Therefore the code must be constructed with those
//   symbols, and the invalid symbols must be detected after decoding.
//
// - The fixed distance codes also have two invalid symbols that should result
//   in an error if received.  Since all of the distance codes are the same
//   length, this can be implemented as an incomplete code.  Then the invalid
//   codes are detected while decoding.
var virgin = true;
var lencnt: [MAXBITS+1]u16 = undefined;
var lensym: [FIXLCODES]u16 = undefined;
var distcnt: [MAXBITS+1]u16 = undefined;
var distsym: [MAXDCODES]u16 = undefined;

var lencode: huffman = undefined;
var distcode: huffman = undefined;
fn fixed(s: *state) !void {

    // build fixed huffman tables if first call (may not be thread safe)
    warn("fixed\n");
    if (virgin) {
        warn("virgin\n");
        var symbol: usize = 0;
        var lengths: [FIXLCODES]u16 = undefined;

        // construct lencode and distcode 
        lencode.count = &lencnt;
        lencode.symbol = &lensym;
        distcode.count = &distcnt;
        distcode.symbol = &distsym;

        // literal/length table
        symbol = 0;
        while (symbol < 144) {
            lengths[symbol] = 8;
            symbol += 1;
        }
        while (symbol < 256) {
            lengths[symbol] = 9;
            symbol += 1;
        }
        while (symbol < 280) {
            lengths[symbol] = 7;
            symbol += 1;
        }
        while (symbol < FIXLCODES) {
            lengths[symbol] = 8;
            symbol += 1;
        }
        //for (lengths) |l, i|{
        //    warn("[{}]={}\n", i, l);
        //}
        _ = construct(&lencode, lengths[0..], FIXLCODES);

        // distance table
        symbol = 0;
        while (symbol < MAXDCODES) {
            lengths[symbol] = 5;
            symbol += 1;
        }
        _ = construct(&distcode, lengths[0..], MAXDCODES);

        // do this just once
        virgin = false;
    }

    // decode data until end-of-block code
    warn("calling codes\n");
    _ = try codes(s, &lencode, &distcode);
    return ;
}

// Process a dynamic codes block.
//
// Format notes:
//
// - A dynamic block starts with a description of the literal/length and
//   distance codes for that block.  New dynamic blocks allow the compressor to
//   rapidly adapt to changing data with new codes optimized for that data.
//
// - The codes used by the deflate format are "canonical", which means that
//   the actual bits of the codes are generated in an unambiguous way simply
//   from the number of bits in each code.  Therefore the code descriptions
//   are simply a list of code lengths for each symbol.
//
// - The code lengths are stored in order for the symbols, so lengths are
//   provided for each of the literal/length symbols, and for each of the
//   distance symbols.
//
// - If a symbol is not used in the block, this is represented by a zero as
//   as the code length.  This does not mean a zero-length code, but rather
//   that no code should be created for this symbol.  There is no way in the
//   deflate format to represent a zero-length code.
//
// - The maximum number of bits in a code is 15, so the possible lengths for
//   any code are 1..15.
//
// - The fact that a length of zero is not permitted for a code has an
//   interesting consequence.  Normally if only one symbol is used for a given
//   code, then in fact that code could be represented with zero bits.  However
//   in deflate, that code has to be at least one bit.  So for example, if
//   only a single distance base symbol appears in a block, then it will be
//   represented by a single code of length one, in particular one 0 bit.  This
//   is an incomplete code, since if a 1 bit is received, it has no meaning,
//   and should result in an error.  So incomplete distance codes of one symbol
//   should be permitted, and the receipt of invalid codes should be handled.
//
// - It is also possible to have a single literal/length code, but that code
//   must be the end-of-block code, since every dynamic block has one.  This
//   is not the most efficient way to create an empty block (an empty fixed
//   block is fewer bits), but it is allowed by the format.  So incomplete
//   literal/length codes of one symbol should also be permitted.
//
// - If there are only literal codes and no lengths, then there are no distance
//   codes.  This is represented by one distance code with zero bits.
//
// - The list of up to 286 length/literal lengths and up to 30 distance lengths
//   are themselves compressed using Huffman codes and run-length encoding.  In
//   the list of code lengths, a 0 symbol means no code, a 1..15 symbol means
//   that length, and the symbols 16, 17, and 18 are run-length instructions.
//   Each of 16, 17, and 18 are follwed by extra bits to define the length of
//   the run.  16 copies the last length 3 to 6 times.  17 represents 3 to 10
//   zero lengths, and 18 represents 11 to 138 zero lengths.  Unused symbols
//   are common, hence the special coding for zero lengths.
//
// - The symbols for 0..18 are Huffman coded, and so that code must be
//   described first.  This is simply a sequence of up to 19 three-bit values
//   representing no code (0) or the code length for that symbol (1..7).
//
// - A dynamic block starts with three fixed-size counts from which is computed
//   the number of literal/length code lengths, the number of distance code
//   lengths, and the number of code length code lengths (ok, you come up with
//   a better name!) in the code descriptions.  For the literal/length and
//   distance codes, lengths after those provided are considered zero, i.e. no
//   code.  The code length code lengths are received in a permuted order (see
//   the order[] array below) to make a short code length code length list more
//   likely.  As it turns out, very short and very long codes are less likely
//   to be seen in a dynamic code description, hence what may appear initially
//   to be a peculiar ordering.
//
// - Given the number of literal/length code lengths (nlen) and distance code
//   lengths (ndist), then they are treated as one long list of nlen + ndist
//   code lengths.  Therefore run-length coding can and often does cross the
//   boundary between the two sets of lengths.
//
// - So to summarize, the code description at the start of a dynamic block is
//   three counts for the number of code lengths for the literal/length codes,
//   the distance codes, and the code length codes.  This is followed by the
//   code length code lengths, three bits each.  This is used to construct the
//   code length code which is used to read the remainder of the lengths.  Then
//   the literal/length code lengths and distance lengths are read as a single
//   set of lengths using the code length codes.  Codes are constructed from
//   the resulting two sets of lengths, and then finally you can start
//   decoding actual compressed data in the block.
//
// - For reference, a "typical" size for the code description in a dynamic
//   block is around 80 bytes.

fn dynamic(s: *state) !u32 {
    //int nlen, ndist, ncode;             // number of lengths in descriptor
    var nlen: usize = 0;
    var ndist: usize = 0;
    var ncode: usize = 0;
    var index: usize = 0;                          // index of lengths[]
    var err: u32 = 0;                            // construct() return value
    var lengths: [MAXCODES]u16 = undefined;            // descriptor code lengths
    // dlencode memory
    var dlencnt: [MAXBITS+1]u16 = undefined;
    var dlensym: [MAXLCODES]u16 = undefined;
    // ddistcode memory
    var ddistcnt: [MAXBITS+1]u16 = undefined;
    var ddistsym: [MAXDCODES]u16 = undefined;       
    var dlencode: huffman = undefined;   // length and distance codes
    var ddistcode: huffman = undefined;
    var order = [19] u16 // permutation of code length codes
    {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};

    warn("dynamic\n");
    // construct dlencode and ddistcode
    dlencode.count = &dlencnt;
    dlencode.symbol = &dlensym;
    ddistcode.count = &ddistcnt;
    ddistcode.symbol = &ddistsym;

    // get number of lengths in each table, check lengths
    nlen = 257 + try s.bits(5);
    ndist = 1 + try s.bits(5);
    ncode = 4 + try s.bits(4);
    if ((nlen > MAXLCODES) or (ndist > MAXDCODES)) {
        return error.BadCounts;                      // bad counts
    }

    // read code length code lengths (really), missing lengths are zero
    index = 0;
    while (index < ncode) {
        lengths[order[index]] = u16(try s.bits(3));
        index += 1;
    }
    while (index < 19) {
        lengths[order[index]] = 0;
        index += 1;
    }

    // build huffman table for code lengths codes (use dlencode temporarily)
    err = try construct(&dlencode, lengths[0..], 19);
    if (err != 0) {              // require complete code set here
        return error.IncompleteCodeSet;
    }

    // read length/literal and distance code length tables
    index = 0;
    while (index < (nlen + ndist)) {
        var symbol: u32 = 0;             // decoded value
        var len: u32 = 0;                // last length to repeat

        symbol = try s.decode(&dlencode);
        if (symbol < 0) {
            return symbol;          // invalid symbol
        }
        if (symbol < 16) {               // length in 0..15
            lengths[index] = u16(symbol);
            index += 1;
        } else {                          // repeat instruction
            len = 0;                    // assume repeating zeros
            if (symbol == 16) {         // repeat last length 3..6 times
                if (index == 0) {
                    return error.NoLastLength;          // no last length!
                }
                len = lengths[index - 1];       // last length
                symbol = 3 + try s.bits(2);
            } else if (symbol == 17) {     // repeat zero 3..10 times
                symbol = 3 + try s.bits(3);
            } else {                        // == 18, repeat zero 11..138 times
                symbol = 11 + try s.bits(7);
            }
            if (index + symbol > nlen + ndist) {
                return error.TooManyLength;              // too many lengths!
            }
            while (symbol > 0) {            // repeat last or zero symbol times
                lengths[index] = u16(len);
                index += 1;
                symbol -= 1;
            }
        }
    }

    // check for end-of-block code -- there better be one!
    if (lengths[256] == 0) {
        return error.NoEndOfBlock;
    }

    // build huffman table for literal/length codes
    err = try construct(&dlencode, lengths[0..], nlen);
    if ((err < 0) or (nlen != (dlencode.count[0] + dlencode.count[1]))) {
        return error.IncompleteCode;      // incomplete code ok only for single length 1 code
    }

    // build huffman table for distance codes
    err = try construct(&ddistcode, lengths[nlen..], ndist);
    if ((err < 0) or (ndist != (ddistcode.count[0] + ddistcode.count[1]))) {
        return error.IncompleteCode;      // incomplete code ok only for single length 1 code
    }

    // decode data until end-of-block code
    return try codes(s, &dlencode, &ddistcode);
}

// Inflate source to dest.  On return, destlen and sourcelen are updated to the
// size of the uncompressed data and the size of the deflate data respectively.
// On success, the return value of puff() is zero.  If there is an error in the
// source data, i.e. it is not in the deflate format, then a negative value is
// returned.  If there is not enough input available or there is not enough
// output space, then a positive error is returned.  In that case, destlen and
// sourcelen are not updated to facilitate retrying from the beginning with the
// provision of more input data or more output space.  In the case of invalid
// inflate data (a negative error), the dest and source pointers are updated to
// facilitate the debugging of deflators.
//
// puff() also has a mode to determine the size of the uncompressed output with
// no output written.  For this dest must be (unsigned char *)0.  In this case,
// the input value of *destlen is ignored, and on return *destlen is set to the
// size of the uncompressed output.
//
// The return codes are:
//
//   2:  available inflate data did not terminate
//   1:  output space exhausted before completing inflate
//   0:  successful inflate
//  -1:  invalid block blktype (blktype == 3)
//  -2:  stored block length did not match one's complement
//  -3:  dynamic block code description: too many length or distance codes
//  -4:  dynamic block code description: code lengths codes incomplete
//  -5:  dynamic block code description: repeat lengths with no first length
//  -6:  dynamic block code description: repeat more than specified lengths
//  -7:  dynamic block code description: invalid literal/length code lengths
//  -8:  dynamic block code description: invalid distance code lengths
//  -9:  dynamic block code description: missing end-of-block code
// -10:  invalid literal/length or distance code in fixed or dynamic block
// -11:  distance is too far back in fixed or dynamic block
//
// Format notes:
//
// - Three bits are read for each block to determine the kind of block and
//   whether or not it is the last block.  Then the block is decoded and the
//   process repeated if it was not the last block.
//
// - The leftover bits in the last byte of the deflate data after the last
//   block (if it was a fixed or dynamic block) are undefined and have no
//   expected values to check.

pub fn puff(dest: []u8,           // pointer to destination pointer
            destlen: *usize,        // amount of output space
            source: []const u8,   // pointer to source data pointer
            sourcelen: *usize) !u32 {     // amount of input available
    var s: state = undefined;             // input/output state
    var last: u32 = 0;
    var blktype: u32 = 0;          // block information
    var err: u32 = 0;                    // return value

    // initialize output state
    s.outbuf = dest;
    s.outlen = destlen.*;                // ignored if dest is NIL
    s.outcnt = 0;

    // initialize input state
    s.inbuf = source;
    s.inlen = sourcelen.*;
    s.incnt = 0;
    s.bitbuf = 0;
    s.bitcnt = 0;

    // return if bits() or decode() tries to read past available input
    //if (setjmp(s.env) != 0) {             // if came back here via longjmp()
    //    err = 2;                        // then skip do-loop, return error
    //} else
    {
        // process blocks until last block or error
        while (true) {
            last = try s.bits(1);    // one if last block
            blktype = try s.bits(2); // block blktype 0..3
            //warn("*** last={x}, blktype={x}, bitcnt={}, bitbuf={x}, outlen={}, outcnt={}\n", last, blktype, s.bitcnt, s.bitbuf, s.outlen, s.outcnt);
            //err = blktype == 0 ? stored(&s) : (blktype == 1 ? fixed(&s) : (blktype == 2 ? dynamic(&s) : -1));       // blktype == 3, invalid
            if (blktype == 0) {
                err = try s.stored();
            } else if (blktype == 1) {
                try fixed(&s);
            } else if (blktype == 2) {
                err = try dynamic(&s);
            } else {
                return error.InvalidBlockType;
            }
        
            if (err != 0) {
                warn("err={}\n", err);
                break;                  // return with error
            }
            if (last != 0) {
                warn("last={}\n", last);
                break;
            }
        } // while (!last);
    }

    // update the lengths and return
    if (err <= 0) {
        destlen.* = s.outcnt;
        sourcelen.* = s.incnt;
    }
    return err;
}

test "puff function" {
    var dest = []u8 {0} ** 8192;
    var destlen = dest.len;
    const ZTEST = struct { input: []const u8, output: []const u8 };
    const pufftests = []ZTEST {
        ZTEST {.input = "KL$\t\x00\x00\xab\xa6\x11\xd0",
               .output = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
        ZTEST {.input = "\xab\xf1\xcfKUHIMLQH)M\xceV(O,V(O-QH\xccKQ(.\x01\x8a\xe8)\x84d\xa4\x16\xa5*d\x96\x80\xe5\xf2KK\x14\xf2\xd3\x14r\x8025\x00p\x1a\x14\xf2",
               .output = "|One dead duck was wet and stuck. There it was out of luck|"},
        ZTEST {.input = "KLJ$\x1d\x02\x00!H\x140",
               .output = "ababababababababababababababababababababababababababa"},
        ZTEST {.input = "30426153\xb7\xb04\x80\xb3\x00*\x80\x04\x1b",
               .output = "01234567890123456789" },
    };
    // Created with python zlib.compress() and initial byte(s) dropped
    //const s = "|One dead duck was wet and stuck. There it was out of luck|";
    //var input = "\xab\xf1\xcfKUHIMLQH)M\xceV(O,V(O-QH\xccKQ(.\x01\x8a\xe8)\x84d\xa4\x16\xa5*d\x96\x80\xe5\xf2KK\x14\xf2\xd3\x14r\x8025\x00p\x1a\x14\xf2";
    const s = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    var input = "KL$\t\x00\x00\xab\xa6\x11\xd0";
    var sourcelen = input.len;

    for (pufftests) |t| {
        // clear dest
        for (dest) |*d| {
            d.* = 0;
        }
        destlen = dest.len;
        sourcelen = t.input.len;
        const ret = try puff(dest[0..], &destlen, t.input[0..], &sourcelen);
        warn("{} bytes, '{}', consumed={}, ret={}\n", destlen, dest, sourcelen, ret);
        assert(destlen == t.output.len);
        //assert(sourcelen == t.input.len);
    }

    //           "|One dead duck was wet and stuck. There it was out of luck|"
    // 59 bytes, '|One dead duck was wet and stduc. There itk wasout of lduc|'
    //                                         ^            ^    ^       ^
}
