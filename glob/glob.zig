// -*- mode: rust -*-
// Based on https://github.com/rust-lang-nursery/glob
//
// Licensed under the MIT license <LICENSE-MIT or
// http://opensource.org/licenses/MIT>. This file may not be copied,
// modified, or distributed except according to those terms.

/// A compiled Unix shell style pattern.
///
/// - `?` matches any single character.
///
/// - `*` matches any (possibly empty) sequence of characters.
///
/// - `**` matches the current directory and arbitrary subdirectories. This
///   sequence **must** form a single path component, so both `**a` and `b**`
///   are invalid and will result in an error.  A sequence of more than two
///   consecutive `*` characters is also invalid.
///
/// - `[...]` matches any character inside the brackets.  Character sequences
///   can also specify ranges of characters, as ordered by Unicode, so e.g.
///   `[0-9]` specifies any character between 0 and 9 inclusive. An unclosed
///   bracket is invalid.
///
/// - `[!...]` is the negation of `[...]`, i.e. it matches any characters
///   **not** in the brackets.
///
/// - The metacharacters `?`, `*`, `[`, `]` can be matched by using brackets
///   (e.g. `[?]`).  When a `]` occurs immediately following `[` or `[!` then it
///   is interpreted as being part of, rather then ending, the character set, so
///   `]` and NOT `]` can be matched by `[]]` and `[!]]` respectively.  The `-`
///   character can be specified inside a character sequence pattern by placing
///   it at the start or the end, e.g. `[abc-]`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = @import("std").debug.assert;
const warn  = @import("std").debug.warn;
pub const String = []const u8;

const PatternToken = union(enum) {
    const Self = @This();

    Char: u8,
    AnyChar,
    AnySequence,
    AnyRecursiveSequence,
    AnyWithin: ArrayList(CharSpecifier),
    AnyExcept: ArrayList(CharSpecifier),

    // custom formatter
    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        context: var,
        comptime Errors: type,
        output: fn (@typeOf(context), []const u8) Errors!void,
    ) Errors!void {
        switch (self) {
            PatternToken.Char => |c|  return std.fmt.format(context, Errors, output, "Char::{c}", c),
            PatternToken.AnyChar => return std.fmt.format(context, Errors, output, "AnyChar"),
            PatternToken.AnySequence => return std.fmt.format(context, Errors, output, "AnySequence"),
            PatternToken.AnyRecursiveSequence => return std.fmt.format(context, Errors, output, "AnyRecursiveSequence"),
            PatternToken.AnyWithin => |al| return std.fmt.format(context, Errors, output, "AnyWithin[{}]", al.len),
            PatternToken.AnyExcept => |al| return std.fmt.format(context, Errors, output, "AnyExcept[{}]", al.len),
        }
    }
};

const CharSet = struct {
    from: u8,
    to: u8,
};

const CharSpecifier = union(enum) {
    SingleChar: u8,
    CharRange: CharSet,
};

const MatchResult = enum {
    Match,
    SubPatternDoesntMatch,
    EntirePatternDoesntMatch,
};

inline fn is_separator(ch: u8) bool {
    return ch == '/' or ch == '\\';
}

pub const Pattern = struct {
    const Self = @This();
    allocator: *Allocator,
    original: String,
    tokens: ArrayList(PatternToken),
    num_tokens: usize,
    is_recursive: bool,

    // custom formatter
    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        context: var,
        comptime Errors: type,
        output: fn (@typeOf(context), []const u8) Errors!void,
    ) Errors!void {
        return std.fmt.format(context, Errors, output, "Pattern('{}', {}, {})",
                              self.original, self.num_tokens, self.is_recursive);
    }

    /// This function compiles Unix shell style patterns.
    ///
    /// An invalid glob pattern will yield a `PatternError`.
    pub fn new(allocator: *Allocator, pattern: String) !Pattern {
        //warn("New pattern from '{}'\n", pattern);
        const pattern_length = pattern.len;
        var tokens = ArrayList(PatternToken).init(allocator);
        var tix: usize = 0;
        var is_recursive = false;
        var i: usize = 0;
        outer: while (i < pattern_length) {
            const c = pattern[i];
            //warn("Checking '{c}'\n", c);
            switch (c) {
                '?' => {
                    try tokens.append(PatternToken {.AnyChar = {}});
                    tix += 1;
                    i += 1;
                },
                '*' => {
                    var start = i;
                    while ((i < pattern_length) and (pattern[i] == '*')) {
                         i += 1;
                    }
                    const count = i - start;
                    if (count > 2) {
                        return error.WildCard;
                        // PatternError { pos: old + 2, msg: ERROR_WILDCARDS, });
                    } else if (count == 2) {
                        // ** can only be an entire path component
                        // i.e. a/**/b is valid, but a**/b or a/**b is not
                        // invalid matches are treated literally
                        var is_valid = false;
                        if ((i == 2) or (is_separator(pattern[i - count - 1]))) {
                            if ((i < pattern_length) and is_separator(pattern[i])) {
                                i += 1;
                                is_valid = true;
                            } else if (i == pattern_length) {
                                is_valid = true;
                            }
                        }
                        if (is_valid) {
                            // collapse consecutive AnyRecursiveSequence to a
                            // single one
                            const tokens_len = tokens.len;
                            if (!((tokens_len > 1) and (tokens.at(tokens_len - 1) == PatternToken.AnyRecursiveSequence))) {
                                is_recursive = true;
                                try tokens.append(PatternToken.AnyRecursiveSequence);
                                tix += 1;
                            }
                        } else {
                            return error.WildCard;
                        }
                    } else {    // 1
                        try tokens.append(PatternToken {.AnySequence = {}});
                        tix += 1;
                    }
                },
                '[' => {
                    if (((i + 4) <= pattern.len) and (pattern[i + 1] == '!')) {
                        for (pattern[i + 3..]) |x, j| {
                            if (x == ']') {
                                //warn("{c}@{}\n", x, j);
                                var cs =  try parse_char_specifiers(allocator, pattern[i + 2..i + 3 + j]);
                                try tokens.append(PatternToken { .AnyExcept = cs });
                                tix += 1;
                                i += j + 4;
                                continue :outer;
                            }
                        }
                    } else if (((i + 3) <= pattern.len) and (pattern[i + 1] != '!')) {
                        // find the matching ]
                        for (pattern[i + 2..]) |x, j| {
                            if (x == ']') {
                                //warn("{c}@{}\n", x, j);
                                var cs =  try parse_char_specifiers(allocator, pattern[i + 1..i + 2 + j]);
                                try tokens.append(PatternToken { .AnyWithin = cs });
                                tix += 1;
                                i += j + 3;
                                continue :outer;
                            }
                        }
                    }
                    // if we get here then this is not a valid range pattern
                    return error.BadPattern;
                    // return Err(PatternError {
                    //     pos: i,
                    //     msg: ERROR_INVALID_RANGE,
                    // });
                },
                else => {
                    try tokens.append(PatternToken {.Char = c});
                    tix += 1;
                    i += 1;
                }
            }
        }
        if (tix == 0) {
            return error.EmptyPattern;
        } else {
            var result = Pattern {.allocator = allocator,
                                  .original = pattern,
                                  .tokens = tokens,
                                  .num_tokens = tix,
                                  .is_recursive = is_recursive};
            //warn("Pattern is {}\n", result);
            return result;
        }
    }

    /// Return if the given `str` matches this `Pattern` using the default
    /// match options (i.e. `MatchOptions::new()`).
    pub fn matches(self: *Self, str: String) bool {
        return self.matches_with(str, &MatchOptions.new());
    }

    /// Return if the given `str` matches this `Pattern` using the specified
    /// match options.
    pub fn matches_with(self: *Self, str: String, options: *MatchOptions) bool {
        return self.matches_from(true, str, 0, options) == MatchResult.Match;
    }

    // private, no docs yet...
    fn matches_from(self: *Self, follows_separator: bool, file: String, i: usize, options: *MatchOptions) MatchResult {
        var ci: usize = 0;
        var follows_sep = follows_separator;
        var matched = false;
        var tokenslice = self.tokens.toSlice();
        for (tokenslice[i..]) |token, ti| {
            //warn("[{d2}] {}\n", ti + i, token);
            switch (token) {
                PatternToken.AnySequence, PatternToken.AnyRecursiveSequence => {
                    // ** must be at the start.
                    // debug_assert!(match *token {
                    //     AnyRecursiveSequence => follows_separator,
                    //     _ => true,
                    // });
                    // Empty match
                    matched = switch (self.matches_from(follows_sep, file[ci..], i + ti + 1, options)) {
                        MatchResult.SubPatternDoesntMatch => true, // keep trying
                        else => |m| return m,
                    };
                    //warn("keep trying\n");
                    while (ci < file.len) {
                        const c = file[ci];
                        ci += 1;
                        if (follows_sep and options.require_literal_leading_dot and (c == '.')) {
                            return MatchResult.SubPatternDoesntMatch;
                        }
                        follows_sep = c == '/';
                        if (token == PatternToken.AnyRecursiveSequence and !follows_sep) {
                            continue;
                        } else if (token == PatternToken.AnySequence and options.require_literal_separator
                                   and follows_sep) {
                            return MatchResult.SubPatternDoesntMatch;
                        }
                        matched = switch (self.matches_from(follows_sep, file[ci..], i + ti + 1, options)) {
                            MatchResult.SubPatternDoesntMatch => true, // keep trying
                            else => |m| return m,
                        };
                    }
                },
                else => {
                    if (ci >= file.len) {
                        return MatchResult.EntirePatternDoesntMatch;
                    }
                    const c = file[ci];
                    ci += 1;
                    //warn("Looking at '{c}'\n", c);
                    const is_sep = c == '/';
                    switch (token) {
                        PatternToken.AnyChar => {
                            matched = if ((options.require_literal_separator and is_sep) or
                                (follows_separator and options.require_literal_leading_dot and
                                 (c == '.'))) false else true;
                        },
                        PatternToken.Char => |pc| {
                            matched = pc == c;
                        },
                        PatternToken.AnyWithin => |*specifiers| {
                            matched = if ((options.require_literal_separator and is_sep) or
                                (follows_separator and options.require_literal_leading_dot and
                                 (c == '.'))) false else in_char_specifiers(specifiers, c, options);
                        },
                        PatternToken.AnyExcept => |*specifiers| {
                            matched = if ((options.require_literal_separator and is_sep) or
                                (follows_separator and options.require_literal_leading_dot and
                                 (c == '.'))) false else !in_char_specifiers(specifiers, c, options);
                        },
                        PatternToken.AnySequence,
                        PatternToken.AnyRecursiveSequence => unreachable,
                    }
                    if (!matched) {
                        return MatchResult.SubPatternDoesntMatch;
                    }
                    //warn("Matched is {}\n", matched);
                    follows_sep = is_sep;
                }
            }
        }

        if (ci == file.len) {
            return if (matched) MatchResult.Match else MatchResult.SubPatternDoesntMatch;
        } else {
            return MatchResult.SubPatternDoesntMatch;
        }
    }

    /// Escape metacharacters within the given string by surrounding them in
    /// brackets. The resulting string will, when compiled into a `Pattern`,
    /// match the input string and nothing else.
    // pub fn escape(s: &str) -> String {
    //     let mut escaped = String::new();
    //     for c in s.pattern() {
    //         match c {
    //             // note that ! does not need escaping because it is only special
    //             // inside brackets
    //             '?' | '*' | '[' | ']' => {
    //                 escaped.push('[');
    //                 escaped.push(c);
    //                 escaped.push(']');
    //             }
    //             c => {
    //                 escaped.push(c);
    //             }
    //         }
    //     }
    //     escaped
    // }
};

inline
fn parse_char_specifiers(allocator: *Allocator, s: []const u8) !ArrayList(CharSpecifier) {
    var cs = ArrayList(CharSpecifier).init(allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (((i + 3) <= s.len) and (s[i + 1] == '-')) {
            try cs.append(CharSpecifier { .CharRange = CharSet {.from = s[i], .to = s[i + 2] } });
            i += 3;
        } else {
            try cs.append(CharSpecifier { .SingleChar = s[i] });
            i += 1;
        }
    }
    return cs;
}

inline
fn in_char_specifiers(specifiers: *const ArrayList(CharSpecifier), c: u8, options: *MatchOptions) bool {
    var specslice = specifiers.toSlice();
    for (specslice[0..]) |specifier| {
        switch (specifier) {
            CharSpecifier.SingleChar => |sc| {
                if (sc == c) {
                    return true;
                }
            },
            CharSpecifier.CharRange => |cr| {
                // TODO: case insensitive
                if ((cr.from <= c) and (c <= cr.to)) {
                    return true;
                }
            },
        }
    }
    // no match triggered above
    return false;
}

/// Configuration options to modify the behaviour of `Pattern::matches_with(..)`.
pub const MatchOptions = struct {
    /// Whether or not patterns should be matched in a case-sensitive manner.
    /// This currently only considers upper/lower case relationships between
    /// ASCII characters, but in future this might be extended to work with
    /// Unicode.
    pub case_sensitive: bool,

    /// Whether or not path-component separator characters (e.g. `/` on
    /// Posix) must be matched by a literal `/`, rather than by `*` or `?` or
    /// `[...]`.
    pub require_literal_separator: bool,

    /// Whether or not paths that contain components that start with a `.`
    /// will require that `.` appears literally in the pattern; `*`, `?`, `**`,
    /// or `[...]` will not match. This is useful because such files are
    /// conventionally considered hidden on Unix systems and it might be
    /// desirable to skip them when listing files.
    pub require_literal_leading_dot: bool,

    /// Constructs a new `MatchOptions` with default field values. This is used
    /// when calling functions that do not take an explicit `MatchOptions`
    /// parameter.
    ///
    /// This function always returns this value:
    ///
    /// ```zig,ignore
    /// MatchOptions {
    ///     .case_sensitive = true,
    ///     .require_literal_separator = false,
    ///     .require_literal_leading_dot = false
    /// }
    /// ```
    pub fn new() MatchOptions {
        return MatchOptions {
            .case_sensitive = true,
            .require_literal_separator = false,
            .require_literal_leading_dot = false,
        };
    }
};

// workaround for a compiler limitation
inline fn sizeof(comptime T: type) usize {
    return usize(@sizeOf(T));
}

test "glob.MatchOptions.new" {
    const options = MatchOptions.new();
    assert(options.case_sensitive == true);
    assert(options.require_literal_separator == false);
    assert(options.require_literal_leading_dot == false);

    //warn("{}\n", options);
    //warn("sizeof MatchOptions {}, PatternToken {}\n", sizeof(MatchOptions), sizeof(PatternToken));
}

// For fixed buffer allocator...
var bytes: [4096]u8 = undefined;

test "glob.Pattern.new" {
    const allocator = &std.heap.FixedBufferAllocator.init(bytes[0..]).allocator;
    var pattern = Pattern.new(allocator, "");
    pattern = Pattern.new(allocator, "a?"[0..]);
}

test "glob.Pattern.matches" {
    const allocator = &std.heap.FixedBufferAllocator.init(bytes[0..]).allocator;
    var maybe_pattern = Pattern.new(allocator, "a");
    if (maybe_pattern) |*pattern| {
        var match = pattern.matches("aa");
        warn("Match: {}\n", match);
    } else |err| {
        warn("{}\n", err);
    }
}

test "glob.Pattern.wildcard" {
    const allocator = &std.heap.FixedBufferAllocator.init(bytes[0..]).allocator;
    if (Pattern.new(allocator, "a*b")) |*pattern| {
        assert(pattern.matches("ab") == true);
        assert(pattern.matches("ac") == false);
        assert(pattern.matches("a_b") == true);
        assert(pattern.matches("a_cdefghb") == true);
    } else |err| {
        warn("{}\n", err);
    }
    if (Pattern.new(allocator, "a*b*c")) |*pattern| {
        assert(pattern.matches("abc") == true);
        assert(pattern.matches("abcd") == false);
        assert(pattern.matches("a_b_c") == true);
        assert(pattern.matches("a___b___c") == true);
        assert(pattern.matches("abcabcabcabcabcabcabc") == true);
        assert(pattern.matches("abcabcabcabcabcabcabca") == false);
    } else |err| {
        warn("{}\n", err);
    }
    if (Pattern.new(allocator, "a*a*a*a*a*a*a*a*a")) |*pattern| {
        assert(pattern.matches("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") == true);
    } else |err| {
        warn("{}\n", err);
    }
}

test "glob.Pattern.rangewithin" {
    const allocator = &std.heap.FixedBufferAllocator.init(bytes[0..]).allocator;
    if (Pattern.new(allocator, "[a-b]")) |*pattern| {
        assert(pattern.matches("a") == true);
        assert(pattern.matches("b") == true);
        assert(pattern.matches("c") == false);
        assert(pattern.matches("abc") == false);
    } else |err| {
        warn("{}\n", err);
    }
}

test "glob.Pattern.rangeexcept" {
    const allocator = &std.heap.FixedBufferAllocator.init(bytes[0..]).allocator;
    if (Pattern.new(allocator, "[!a-f]")) |*pattern| {
        assert(pattern.matches("a") == false);
        assert(pattern.matches("c") == false);
        assert(pattern.matches("f") == false);
        assert(pattern.matches("g") == true);
    } else |err| {
        warn("{}\n", err);
    }
}

test "glob.Pattern.directory" {
    const allocator = &std.heap.FixedBufferAllocator.init(bytes[0..]).allocator;
    if (Pattern.new(allocator, "**")) |*pattern| {
        assert(pattern.matches("ggggg") == true);
        assert(pattern.matches("ggggg/hhhh/") == true);
    } else |err| {
        warn("{}\n", err);
    }
}

test "glob.Pattern.long" {
    const allocator = &std.heap.FixedBufferAllocator.init(bytes[0..]).allocator;
    if (Pattern.new(allocator, "*hello.txt")) |*pattern| {
        assert(pattern.matches("hello.txt") == true);
        assert(pattern.matches("gareth_says_hello.txt") == true);
        assert(pattern.matches("some/path/to/hello.txt") == true);
        assert(pattern.matches("some\\path\\to\\hello.txt") == true);
        assert(pattern.matches("/an/absolute/path/to/hello.txt") == true);
        assert(pattern.matches("hello.txtt") == false);
        assert(pattern.matches("hello.txt-and-then-some") == false);
        assert(pattern.matches("goodbye.txt") == false);
    } else |err| {
        warn("{}\n", err);
    }
}

test "glob.Pattern.set" {
    const allocator = &std.heap.FixedBufferAllocator.init(bytes[0..]).allocator;
    if (Pattern.new(allocator, "a[xyz]d")) |*pattern| {
        assert(pattern.matches("awd") == false);
        assert(pattern.matches("axd") == true);
        assert(pattern.matches("ayd") == true);
        assert(pattern.matches("azd") == true);
        assert(pattern.matches("aad") == false);
    } else |err| {
        warn("{}\n", err);
    }
}
