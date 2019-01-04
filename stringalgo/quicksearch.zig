// -*- mode: zig; -*-
const std = @import("std");
const math = std.math;
const warn = std.debug.warn;

// Loads of documentation here; http://www-igm.univ-mlv.fr/~lecroq/string/

inline fn maxValue(comptime T: type) T {
    return math.mxInt(T);
}

const ALPHABET_SIZE: usize = 256;


fn pre_quicksearch_badchar(needle: []const u8, needlelen: usize, qsBc: []usize) void {
    var i: usize = 0;
    for (qsBc) |*d| { d.* = needlelen + 1; }
    while (i < needlelen) : (i += 1) {
        qsBc[needle[i]] = needlelen - i;
    }
}

fn matches(a: []const u8, b: []const u8, sz: usize) bool {
    { var pos = usize(0);
        while (pos < sz) : (pos += 1) {
            if (a[pos] != b[pos]) return false;
        }
    }
    return true;
}

pub fn quicksearch(needle: []const u8, nlen: usize, haystack: []const u8, hlen: usize) isize {
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

pub const QuickSearch = struct {
    const Self = @This();

    badchar: [ALPHABET_SIZE]usize,
    searchpos: usize,
    pub patternlen: usize,

    pub fn init(pattern: []const u8) QuickSearch {
        var qs = QuickSearch {.badchar = undefined,
                              .searchpos = 0,
                              .patternlen = pattern.len};
        pre_quicksearch_badchar(pattern, pattern.len, qs.badchar[0..]);

        return qs;
    }

    pub fn search(qs: *Self, needle: []const u8, haystack: []const u8) !usize {
        // Searching
        const nlen = needle.len;
        const endpos = haystack.len - nlen;
        if ((needle.len == 0) or (haystack.len < needle.len)) return error.BadLength;
        while (qs.searchpos <= endpos) {
            if (matches(needle, haystack[qs.searchpos .. ], nlen))
            {
                const ret = qs.searchpos;
                qs.searchpos += nlen;
                return ret;
            }
            // shift
            qs.searchpos += qs.badchar[haystack[qs.searchpos + nlen]];
        }

        return error.NotFound;
    }
};

test "quicksearch.dummy" {
    var qs = QuickSearch.init("reading");

    while (qs.search("reading", "I was reading about it while someone else was reading about simeting else"))  |pos| {
        warn("Found at {}\n", pos);
    } else |err| {
    }
}
