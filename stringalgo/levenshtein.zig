// -*- mode: zig; indent-tabs-mode:nil; -*-
fn min3(comptime T: type, a: T, b: T, c: T) -> T {
    if (a < b) {
        if (a < c) a else c
    } else {
        if (b < c) b else c
    }
    // or this; if (a < b) if (a < c) a else c else if (b < c) b else c
}

// Wagner-Fischer? https://en.wikipedia.org/wiki/Wagner%E2%80%93Fischer_algorithm
pub fn wagnerfisher(s1: []const u8, s2: []const u8) -> usize {
    const s1len = s1.len;
    const s2len = s2.len;

    if ((s1len == 0) or (s2len == 0)) return 0;

    //var column: [(if (s1len > s2len) s1len else s2len) + 1]usize = zeroes;
    const maxlen: usize = (if (s1len > s2len) s1len else s2len) + usize(1);
    var column: [128]usize = []usize{usize(0)} ** 128;

    // Check that maxlen is less than column.len?!
    //var column = @alloca(usize, maxlen);
    for (column) |*b| {
            *b = 0;
    }

    var last: usize = 0;
    var prev: usize = 0;
    var x: usize = 0;
    var y: usize = 0;
    y = 1;
    while (y <= s1len) : (y += 1) {
        column[y] = y;
    }
    x = 1;
    while (x <= s2len) : (x += 1) {
        column[0] = x;
        last = x - 1;
        y = 1;
        while (y <= s1len) : (y += 1) {
            prev = column[y];
            column[y] = min3(usize, column[y] + 1, column[y-1] + 1, last +
                             if (s1[y-1] == s2[x-1]) usize(0) else usize(1));
            last = prev;
        }
    }
    return column[s1len];
}

