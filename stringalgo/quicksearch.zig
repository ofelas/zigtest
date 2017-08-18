// -*- mode: zig; -*-
const io = @import("std").io;

// Loads of documentation here; http://www-igm.univ-mlv.fr/~lecroq/string/

const ALPHABET_SIZE = @maxValue(u8) + 1;

error PatternTooLong;

fn pre_quicksearch_badchar(needle: []const u8, needlelen: usize, qsBc: []isize) {
    var i = usize(0);
    for (qsBc) |*d| { *d =isize(needlelen + 1); }
    while (i < needlelen) : (i += 1) {
        qsBc[needle[i]] = isize(needlelen - i);
    }
}

fn matches(a: []const u8, b: []const u8, sz: usize) -> bool {
    { var pos = usize(0);
        while (pos < sz) : (pos += 1) {
            if (a[pos] != b[pos]) return false;
        }
    }
    return true;
}

pub fn quicksearch(needle: []const u8, nlen: usize, haystack: []const u8, hlen: usize) -> isize {
    if (nlen > hlen) return isize(-2);

    var qsBc: [ALPHABET_SIZE]isize = undefined; // costly but safe?
    const endpos: isize = isize(hlen - nlen);

    if (nlen == 0) {
        return isize(-1);
    }
    // Preprocessing, (costly stuff) better done once during an init phase
    // e.g. a struct with the pattern and badchar, later maybe...
    //      and it's fairly easy to find all occurances
    pre_quicksearch_badchar(needle, nlen, qsBc[0..]); // costly

    // Searching
    {
        var pos = isize(0);
        while (pos <= endpos) {
            if (matches(needle, haystack[usize(pos) .. usize(pos)+nlen], nlen))
            {
                return pos;
            }
            // shift
            pos += qsBc[haystack[usize(pos + isize(nlen))]];
        }
    }

    return isize(-1);
}

pub const QuickSearch =  extern struct {
    badchar: [ALPHABET_SIZE]isize,
    searchpos: isize,
    pub patternlen: isize,

    pub fn init(qs: &QuickSearch, pattern: []u8) -> %void {
        if (pattern.len > @maxValue(isize)) return error.PatternTooLong;
        pre_quicksearch_badchar(pattern, pattern.len, qs.badchar);
        qs.searchpos = 0;
        qs.patternlen = isize(pattern.len);
    }

    pub fn search(qs: &QuickSearch, needle: []u8, haystack: []u8) -> isize {
        // Searching
        const nlen = isize(needle.len);
        const endpos = isize(haystack.len) - nlen;
        if ((needle.len == 0) or (haystack.len < needle.len)) return -1;
        while (qs.searchpos <= endpos) {
            if (matches(needle, haystack[usize(qs.searchpos) .. ], usize(nlen)))
            {
                const ret = qs.searchpos;
                qs.searchpos += nlen;
                return ret;
            }
            // shift
            qs.searchpos += qs.badchar[haystack[usize(qs.searchpos + isize(nlen))]];
        }

        return isize(-1);
    }
};
