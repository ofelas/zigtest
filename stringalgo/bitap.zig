// -*- mode:zig; -*-

const U8_MAX = @maxValue(u8);
const BITAP_TYPE = usize;
const BITAP_BIT_COUNT = BITAP_TYPE.bit_count - 1;

error PatternTooLong;
error EmptyInput;

pub fn bitap_search(text: []u8, pattern: []u8) -> %isize {
    if ((pattern.len == 0) || pattern[0] == 0) return -1; //error.EmptyInput;
    if (pattern.len > BITAP_BIT_COUNT) return error.PatternTooLong;

    const m = pattern.len;
    var R: BITAP_TYPE = ~BITAP_TYPE(1);          // Initialize bit array
    var pattern_mask: [U8_MAX + 1]BITAP_TYPE = []BITAP_TYPE{~BITAP_TYPE(0)} ** (U8_MAX + 1);
    var i: usize = 0;

    // Init pattern mask
    i = 0; while (i < m; i += 1) {
        pattern_mask[pattern[i]] &= ~(1 << i);
    }
    // search
    i = 0; while (text[i] != 0 && i < text.len; i += 1) {
        R |= pattern_mask[text[i]];
        R <<%= 1;

        if (0 == (R & (1 << m))) {
            // found
            return isize(i - m) + 1;
        }
    }

    // not found
    return isize(-1);
}
