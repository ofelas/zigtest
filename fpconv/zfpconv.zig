// -*- mode:zig; -*-

// This is based on C source with the follwoing license information.

// The MIT License
//
// Copyright (c) 2013 Andreas Samoljuk
//
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
// OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
// WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.// powers.h


// powers.h
const npowers = 87;
const steppowers: i32 = 8;
const firstpower: i32 = -348; // 10 ^ -348

const Fraction = u64;
const Exponent = i32;

const expmax: Exponent = -32;
const expmin: Exponent = -60;

struct Fp {
    frac: Fraction,
    exp: Exponent,
}

fn mkFP(f: Fraction, e: Exponent) -> Fp {
    return Fp { .frac = f, .exp = e, };
}

const powers_ten = []Fp {
    mkFP(18054884314459144840, -1220), mkFP(13451937075301367670, -1193),
    mkFP(10022474136428063862, -1166), mkFP(14934650266808366570, -1140),
    mkFP(11127181549972568877, -1113), mkFP(16580792590934885855, -1087),
    mkFP(12353653155963782858, -1060), mkFP(18408377700990114895, -1034),
    mkFP(13715310171984221708, -1007), mkFP(10218702384817765436, -980),
    mkFP(15227053142812498563, -954),  mkFP(11345038669416679861, -927),
    mkFP(16905424996341287883, -901),  mkFP(12595523146049147757, -874),
    mkFP(9384396036005875287,  -847),  mkFP(13983839803942852151, -821),
    mkFP(10418772551374772303, -794),  mkFP(15525180923007089351, -768),
    mkFP(11567161174868858868, -741),  mkFP(17236413322193710309, -715),
    mkFP(12842128665889583758, -688),  mkFP(9568131466127621947,  -661),
    mkFP(14257626930069360058, -635),  mkFP(10622759856335341974, -608),
    mkFP(15829145694278690180, -582),  mkFP(11793632577567316726, -555),
    mkFP(17573882009934360870, -529),  mkFP(13093562431584567480, -502),
    mkFP(9755464219737475723,  -475),  mkFP(14536774485912137811, -449),
    mkFP(10830740992659433045, -422),  mkFP(16139061738043178685, -396),
    mkFP(12024538023802026127, -369),  mkFP(17917957937422433684, -343),
    mkFP(13349918974505688015, -316),  mkFP(9946464728195732843,  -289),
    mkFP(14821387422376473014, -263),  mkFP(11042794154864902060, -236),
    mkFP(16455045573212060422, -210),  mkFP(12259964326927110867, -183),
    mkFP(18268770466636286478, -157),  mkFP(13611294676837538539, -130),
    mkFP(10141204801825835212, -103),  mkFP(15111572745182864684, -77),
    mkFP(11258999068426240000, -50),   mkFP(16777216000000000000, -24),
    mkFP(12500000000000000000,   3),   mkFP(9313225746154785156,   30),
    mkFP(13877787807814456755,  56),   mkFP(10339757656912845936,  83),
    mkFP(15407439555097886824, 109),   mkFP(11479437019748901445, 136),
    mkFP(17105694144590052135, 162),   mkFP(12744735289059618216, 189),
    mkFP(9495567745759798747,  216),   mkFP(14149498560666738074, 242),
    mkFP(10542197943230523224, 269),   mkFP(15709099088952724970, 295),
    mkFP(11704190886730495818, 322),   mkFP(17440603504673385349, 348),
    mkFP(12994262207056124023, 375),   mkFP(9681479787123295682,  402),
    mkFP(14426529090290212157, 428),   mkFP(10748601772107342003, 455),
    mkFP(16016664761464807395, 481),   mkFP(11933345169920330789, 508),
    mkFP(17782069995880619868, 534),   mkFP(13248674568444952270, 561),
    mkFP(9871031767461413346,  588),   mkFP(14708983551653345445, 614),
    mkFP(10959046745042015199, 641),   mkFP(16330252207878254650, 667),
    mkFP(12166986024289022870, 694),   mkFP(18130221999122236476, 720),
    mkFP(13508068024458167312, 747),   mkFP(10064294952495520794, 774),
    mkFP(14996968138956309548, 800),   mkFP(11173611982879273257, 827),
    mkFP(16649979327439178909, 853),   mkFP(12405201291620119593, 880),
    mkFP(9242595204427927429,  907),   mkFP(13772540099066387757, 933),
    mkFP(10261342003245940623, 960),   mkFP(15290591125556738113, 986),
    mkFP(11392378155556871081, 1013),  mkFP(16975966327722178521, 1039),
    mkFP(12648080533535911531, 1066)
};

const one_log_ten: f64 = 0.30102999566398114;

fn findCachedPow10(exp: i32, k: &i32) -> Fp {
    const approx: i32 = i32(@typeOf(one_log_ten)(-(exp + npowers)) * one_log_ten);
    var idx: usize = usize((approx - firstpower) / steppowers);

    while (true) {
        const current: Exponent = exp + powers_ten[idx].exp + 64;

        if (current < expmin) {
            idx += 1;
            continue;
        }

        if (current > expmax) {
            idx -=1 ;
            continue;
        }

        *k = (firstpower + (i32(idx) * steppowers));

        return powers_ten[idx];
    }
}

// fpconv.c
const fracmask  =  0x000FFFFFFFFFFFFF;
const expmask   =  0x7FF0000000000000;
const hiddenbit =  0x0010000000000000;
const signmask  =  0x8000000000000000;
const  expbias  = 1023 + 52;

// new type inference
fn absv(n: var) -> @typeOf(n) {
  if (n < 0) -n else n
}
// new type inference
fn minv(a: var, b: var) -> @typeOf(a + b) {
    if (a < b) a else b
}

const tens = []u64 {
    10000000000000000000,
    1000000000000000000,
    100000000000000000,
    10000000000000000,
    1000000000000000,
    100000000000000,
    10000000000000,
    1000000000000,
    100000000000,
    10000000000,
    1000000000,
    100000000,
    10000000,
    1000000,
    100000,
    10000,
    1000,
    100,
    10,
    1
};

// TODO: union
// struct DU {
//     dbl: f64,
//     i: u64,
// }

fn get_dbits(d: f64) -> u64 {
    //var dbl_bits = DU {.dbl = d, .i = u64(d) };
    const d_as_slice = (&u8)(&d);
    var result: u64 = undefined;
    const result_slice = ([]u8)((&result)[0...1]);
    if (@compileVar("is_big_endian") == false) {
        for (result_slice) |*b, i| {
            *b = d_as_slice[i];
        }
    } else { // big-endian, not tested
        for (result_slice) |*b, i| {
            *b = d_as_slice[@sizeOf(result) - i - 1];
        }
    }
    result
}

fn build_fp(dbits: u64) -> Fp {
    var fp = Fp { .frac = dbits & fracmask, .exp = i32((dbits & expmask) >> 52) };

    if (fp.exp != 0) {
        fp.frac += hiddenbit;
        fp.exp -= expbias;

    } else {
        fp.exp = -expbias + 1;
    }

    return fp;
}

fn fp_normalize(fp: &Fp) -> void {
    while ((fp.frac & hiddenbit) == 0) {
        fp.frac <<= 1;
        fp.exp -= 1;
    }

    const shift = 64 - 52 - 1;
    fp.frac <<= shift;
    fp.exp -= shift;
}

fn fp_get_normalized_boundaries(fp: &Fp, lower: &Fp, upper: &Fp) -> void {
    upper.frac = (fp.frac << 1) + 1;
    upper.exp  = fp.exp - 1;

    while ((upper.frac & (hiddenbit << 1)) == 0) {
        upper.frac <<= 1;
        upper.exp -= 1;
    }

    const u_shift = 64 - 52 - 2;

    upper.frac <<= u_shift;
    upper.exp = upper.exp - u_shift;


    const l_shift: i32 = if (fp.frac == hiddenbit) 2 else 1;

    lower.frac = (fp.frac << u64(l_shift)) - 1;
    lower.exp = fp.exp - l_shift;


    lower.frac <<= @typeOf(lower.frac)(lower.exp - upper.exp);
    lower.exp = upper.exp;
}

fn fp_multiply(a: &Fp, b: &Fp) -> Fp {
    const lomask: u64 = 0x00000000FFFFFFFF;
    const ah_bl: u64 = (a.frac >> 32)    * (b.frac & lomask);
    const al_bh: u64 = (a.frac & lomask) * (b.frac >> 32);
    const al_bl: u64 = (a.frac & lomask) * (b.frac & lomask);
    const ah_bh: u64 = (a.frac >> 32)    * (b.frac >> 32);

    var tmp: u64 = (ah_bl & lomask) + (al_bh & lomask) + (al_bl >> 32);
    // round up
    tmp += u64(1) << 31;

    Fp {
        .frac = ah_bh + (ah_bl >> 32) + (al_bh >> 32) + (tmp >> 32),
        .exp = a.exp + b.exp + 64
    }
}

fn round_digit(digits: []u8, ndigits: i32, delta: u64, rem: u64, kappa: u64, frac: u64) -> void {
    var lrem = rem;
    while ((lrem < frac) && ((delta - lrem) >= kappa) &&
           (((lrem + kappa) < frac) || ((frac - lrem) > (lrem + kappa - frac)))) {

        digits[usize(ndigits - 1)] -= 1;
        lrem += kappa;
    }
}

fn fp_generate_digits(fp: &Fp, upper: &Fp, lower: &Fp, digits: []u8, K: &i32) -> i32 {
    var wfrac: Fraction = upper.frac - fp.frac;
    var delta: Fraction = upper.frac - lower.frac;
    const one = Fp {.frac = 1 << u64(-upper.exp), .exp  = upper.exp };
    var part1: u64 = upper.frac >> u64(-one.exp);
    var part2: u64 = upper.frac & (one.frac - 1);
    var idx: i32 = 0;
    var kappa: i32 = 10;

    {var tidx: usize = 10; while (kappa > 0; tidx += 1) {
        const div = tens[tidx];
        var digit: u64 = part1 / div;

        if ((digit > 0) || (idx > 0)) {
            digits[usize(idx)] = @truncate(u8, digit) + '0';
            idx += 1;
        }

        part1 -= digit * div;
        kappa -= 1;

        const tmp: u64 = (part1 << @typeOf(part1)(-one.exp)) + part2;
        if (tmp <= delta) {
            *K += kappa;
            round_digit(digits, idx, delta, tmp, div << @typeOf(div)(-one.exp), wfrac);

            return idx;
        }
    }}

    // 10
    var unitidx: usize = 18;
    while (true; unitidx -= 1) {
        const unit: u64 = tens[unitidx];
        part2 *= 10;
        delta *= 10;
        kappa -= 1;

        const digit: usize = part2 >> @typeOf(part2)(-one.exp);
        if ((digit != 0) || (idx != 0)) {
            digits[usize(idx)] = @truncate(u8, digit) + '0';
            idx += 1;
        }

        part2 &= (one.frac - 1);
        if (part2 < delta) {
            *K += kappa;
            round_digit(digits, idx, delta, part2, one.frac, wfrac * unit);

            return idx;
        }
    }
}

fn zgrisu2(d: f64, digits: []u8, dbits: u64, K: &i32) -> i32 {
    var w: Fp = build_fp(dbits);
    var lower: Fp = undefined;
    var upper: Fp = undefined;

    fp_get_normalized_boundaries(&w, &lower, &upper);
    fp_normalize(&w);

    var k: @typeOf(*K) = 0;
    var cp: Fp = findCachedPow10(upper.exp, &k);

    w     = fp_multiply(&w,     &cp);
    upper = fp_multiply(&upper, &cp);
    lower = fp_multiply(&lower, &cp);

    lower.frac += 1;
    upper.frac -= 1;

    *K = -k;

    return fp_generate_digits(&w, &upper, &lower, digits, K);
}

fn emit_digits(digits: []u8, ndigits: i32, dest: []u8, ofs: usize, K: i32, neg: bool) -> usize {
    var exp: i32 = absv(K + ndigits - 1);
    var ldigits = ndigits;
    var idx: usize = ofs;

    // write plain integer
    if((K >= 0) && (exp < (ndigits + 7))) {
        { var todo: usize = 0; while (todo < usize(ndigits); todo += 1) {
             dest[idx] = digits[todo];
             idx += 1;
        }}
        //@memset(&dest[idx+usize(ndigits)], '0', usize(K));
        // ziggish highlevel memset
        for (dest[idx...idx+usize(K)]) |*b| *b = '0';
        idx += usize(K);

        return idx - ofs;
    }

    // write decimal w/o scientific notation
    if ((K < 0) && ((K > -7) || (exp < 4))) {
        var offset: i32 = ndigits - absv(K);
        // fp < 1.0 -> write leading zero
        if (offset <= 0) {
            offset = -offset;
            dest[idx] = '0';
            dest[idx + 1] = '.';
            idx += 2;
            for (dest[2...2+usize(offset)]) |*b| *b = '0';
            const idxofs = usize(offset);
            for (digits) |c, i| {
                if (i == usize(ndigits)) break;
                dest[idx + idxofs + i] = c;
            }
            idx += usize(ndigits);

            return idx - ofs;

        // fp > 1.0
        } else {
            // get the first number of chars from digits
            {var todo: usize = 0; while (todo < usize(offset); todo += 1) {
                dest[idx] = digits[todo];
                idx += 1;
            }}
            // add a '.'
            dest[idx] = '.';
            idx += 1;
            // then get the rest, which seems to work
            {var todo: usize = 0; while (todo < usize(ndigits - offset); todo += 1) {
                dest[idx] = digits[usize(offset) + todo];
                idx += 1;
            }}

            return idx - ofs;
        }
    }

    // write decimal w/ scientific notation
    // use ldigits from here on (ndigits is read-only)
    ldigits = minv(ndigits, 18 - @typeOf(ndigits)(neg));

    dest[idx] = digits[0];
    idx += 1;

    if (ldigits > 1) {
        dest[idx] = '.';
        idx += 1;
        {var todo: usize = 0; while (todo < usize(ldigits - 1); todo += 1) {
            dest[idx] = digits[todo];
            idx += 1;
        }}
    }

    dest[idx] = 'e';
    idx += 1;

    const sign: u8 = if ((K + ldigits - 1) < 0) '-' else '+';
    dest[idx] = sign;
    idx += 1;

    var cent: i32 = 0;

    if(exp > 99) {
        cent = exp / 100;
        dest[idx] = u8(cent) + '0';
        idx += 1;
        exp -= cent * 100;
    }

    if(exp > 9) {
        const dec = u8(exp / 10);
        dest[idx] = dec + '0';
        idx += 1;
        exp -= dec * 10;
    } else if (cent != 0) {
        dest[idx] = '0';
        idx += 1;
    }

    dest[idx] = u8(exp % 10) + '0';
    idx += 1;

    // return the number of digits emitted
    return idx - ofs;
}

fn filter_special(fp: f64, bits: u64, dest: [24]u8, ofs: usize) -> usize {

    if (fp == 0.0) {
        dest[0] = '0';
        return 1;
    }

    // avoid converting the thing again...
    //const bits: u64 = get_dbits(fp);
    const nan: bool = (bits & expmask) == expmask;

    if (!nan) {
        return 0;
    }

    if ((bits & fracmask) != 0) {
        dest[ofs] = 'n'; dest[ofs + 1] = 'a'; dest[ofs + 2] = 'n';

    } else {
        dest[ofs] = 'i'; dest[ofs + 1] = 'n'; dest[ofs + 2] = 'f';
    }

    return 3;
}

pub fn zfpconv_dtoa(d: f64, dest: [24]u8) -> usize {
    var digits: [24]u8 = undefined;

    var str_len: usize = 0;
    var neg: bool = false;
    const dbits = get_dbits(d);

    if ((dbits & signmask) == signmask) {
        dest[0] = '-';
        str_len += 1;
        neg = true;
    }

    const spec: usize = filter_special(d, dbits, dest, str_len);

    if (spec > 0) {
        return str_len + spec;
    }

    var K:i32 = 0;
    const ndigits = zgrisu2(d, digits, dbits, &K);

    // ???We probably get a copy when using the slize dest[str_len...], not what we want
    // nah, probably wrong about that
    str_len += emit_digits(digits, ndigits, dest, str_len, K, neg);

    // dest is not '\0' terminated
    return str_len;
}
