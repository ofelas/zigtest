// -*- mode:zig; indent-tabs-mode:nil; comment-start:"// "; -*-
const std = @import("std");
const os = std.os;
var allocator = std.debug.global_allocator;
const warn = @import("std").debug.warn;
const io = std.io; // stdio lol
const mem = std.mem;
const debug = std.debug;
const assert = debug.assert;
const math = std.math;
const max = math.max;
const hashmap = std.hash_map;
const list = @import("jlist.zig");
//const printer = @import("printer.zig");
const parseUnsigned = std.fmt.parseUnsigned;
const parseInt = std.fmt.parseInt;

const fpconv_dtoa = @import("../fpconv/zfpconv.zig").zfpconv_dtoa;
const atod = @import("../fpconv/zfast_atof.zig").zatod;

/// There may be a simpler way...
var stdout_file: io.File = undefined;
var stdout_file_out_stream: io.FileOutStream = undefined;
var stdout_stream: ?&io.OutStream = null;

pub fn print(comptime fmt: []const u8, args: ...) void {
    const stream = getStdOutStream() catch |_| return;
    stream.print(fmt, args) catch |_| return;
}

inline fn getStdOutStream() %&io.OutStream {
    if (stdout_stream) |st| {
        return st;
    } else {
        stdout_file = try io.getStdOut();
        stdout_file_out_stream = io.FileOutStream.init(&stdout_file);
        const st = &stdout_file_out_stream.stream;
        stdout_stream = st;
        return st;
    }
}

fn printDouble(d: f64, stream: io.OutStream) %void {
    var buf: [24]u8 = zeroes;
    var sz = fpconv_dtoa(d, buf);
    %%stream.write(buf[0 .. sz]);
}

error JsonError;

const ZJSON_NESTING_LIMIT: usize = 64;

const ParseBuffer = struct {
    const Self = this;
    content: []const u8,
    // We actually have the length in content.len, 8)
    length: usize,
    offset: usize,
    depth: usize, // Recursion level, we impose an arbitrary limit
    // Maybe an allocator?

    fn debug(pb: &const Self) void {
        print("ParseBuffer: length={}/{}, offset={} depth={}\n",
              pb.length, pb.content.len, pb.offset, pb.depth);
    }

    inline fn canAccessAtIndex(pb: &Self, index: usize) bool {
        return (pb.offset + index) < pb.content.len;
    }

    inline fn charAtOffset(pb: &Self) u8 {
        var result: u8 = 0;
        if (pb.canAccessAtIndex(0) == true) {
            result = pb.content[pb.offset];
        }

        return result;
    }

    inline fn advanceIfLookingAt(pb: &Self, c: u8) bool {
        if (pb.canAccessAtIndex(0) == true and pb.charAtOffset() == c) {
            pb.offset += 1;
            return true;
        }

        return false;
    }

    inline fn skipUtf8Bom(pb: &Self) bool {
        var result = false;
        if (pb.offset == 0) {
            if (pb.canAccessAtIndex(4) == true) {
                //"\xEF\xBB\xBF"
                if ((pb.content[pb.offset] == 0xef)
                    and (pb.content[pb.offset + 1] == 0xbb)
                    and (pb.content[pb.offset + 2] == 0xbf)) {
                    pb.offset += 3;
                    result = true;
                }
            }
        }

        return result;
    }

    inline fn skipWhitespace(pb: &Self) void {
        while (pb.canAccessAtIndex(0) and (pb.charAtOffset() <= 32)) {
            pb.offset += 1;
        }
        // Go back if we went to far...(no comment)
        if (pb.offset == pb.length) {
            pb.offset -= 1;
        }
    }
};

/// Parse a string, we must be looking at the initial '"' (double quote)
fn parseString(pb: &ParseBuffer) bool {
    var result = false;
    if (pb.advanceIfLookingAt('"') == true) {
        const startsAt = pb.offset;
        // Now find the ending '"', ignoring utf8, escapes and what not
        var previous = pb.charAtOffset();
        while (pb.canAccessAtIndex(0)) {
            if (pb.charAtOffset() == '"' and previous != '\\') {
                result = true;
                print("STRING: '{}'\n", pb.content[startsAt .. pb.offset]);
                pb.offset += 1;
                break;
            }
            previous = pb.charAtOffset();
            pb.offset += 1;
        }
    } else {
        print("ERROR: Not looking at a STRING @ ");
        pb.debug();
    }

    return result;
}

const NumericValue = struct {
    const Self = this;
    i: i64,
    f: f64,

    fn debug(nv: &const Self) void {
        print("NumericValue: .i={}, .f={}\n", nv.i, nv.f);
    }
};

const NumericResult = union(enum) {
 NotOk: void,
 Ok: NumericValue,
};

fn parseNumeric(pb: &ParseBuffer) NumericResult {
    var result = NumericResult {.NotOk = {}};
    var must_be_int = true;
    var dots: u16 = 0;
    var exps: u16 = 0;
    var digits: u16 = 0;
    const startsAt = pb.offset;

    while (pb.canAccessAtIndex(0) and digits < 254) {
        switch (pb.charAtOffset()) {
            '0' ... '9' => {
                pb.offset += 1;
                digits += 1;
            },
            '.'  => {
                pb.offset += 1;
                must_be_int = false;
                dots += 1;
            },
            'e', 'E' => {
                pb.offset += 1;
                must_be_int = false;
            },
            '+', '-' => {
                pb.offset += 1;
            },
            else => {
                if ((digits > 0) and (dots <= 1) and (startsAt < pb.offset)) {
                    if (must_be_int == true) {
                        if (parseInt(i64, pb.content[startsAt .. pb.offset], 10)) |v| {
                           result = NumericResult { .Ok = NumericValue { .i = v, .f = f64(v)} };
                        } else |err| {
                            print("ERROR: {}, parsing '{}'\n", err, pb.content[startsAt .. pb.offset]);
                        }
                    } else {
                        // parse the float
                        if (atod(pb.content[startsAt .. pb.offset])) |v| {
                            result = NumericResult { .Ok = NumericValue { .i = i64(v), .f = v} };
                        } else |err| {
                            print("ERROR: {}, parsing '{}'\n", err, pb.content[startsAt .. pb.offset]);
                        }
                    }
                } else {
                    print("BAD NUMBER: '{}' {} {}\n", pb.content[startsAt .. pb.offset], digits, dots);
                    pb.debug();
                }
                break;
            },
        }
    }

    return result;
}

fn parseArray(pb: &ParseBuffer) bool {
    var result = false;
    if (pb.depth >= ZJSON_NESTING_LIMIT) {
        print("ERROR: Nested too deep @ ");
        pb.debug();
        return result;
    }
    pb.depth += 1;
    if (pb.advanceIfLookingAt('[') == true) {
        pb.skipWhitespace();
        if (pb.canAccessAtIndex(0)) {
            if (pb.charAtOffset() == ']') {
                // Empty ARRAY, move past the ']'...
                pb.offset += 1;
                pb.depth -= 1;
                result = true;
            } else {
                // Should be a comma separated list of "items"
                var keepgoing = true;
                var i: usize = 0;
                while (keepgoing) {
                    pb.skipWhitespace();
                    result = parseValue(pb);
                    pb.skipWhitespace();
                    if (result == true and pb.advanceIfLookingAt(',') == true) {
                        i += 1;
                    } else {
                        keepgoing = false;
                        break;
                    }
                }
                if (result == true) {
                    // Need the ending ']'
                    if (pb.advanceIfLookingAt(']') == true) {
                        pb.depth -= 1;
                        print("ARRAY of {} items at depth {}\n", i, pb.depth);
                    } else {
                        print("ERROR: ARRAY @ "); pb.debug();
                        result = false;
                    }
                }
            }
        }
    } else {
        print("ERROR: Not looking at an ARRAY {} @ ", pb.charAtOffset());
        pb.debug();
    }

    return result;
}

fn parseObject(pb: &ParseBuffer) bool {
    var result = false;
    if (pb.depth >= ZJSON_NESTING_LIMIT) {
        print("ERROR: Nested too deep @ ");
        pb.debug();
        return result;
    }
    pb.depth += 1;
    if (pb.advanceIfLookingAt('{') == true) {
        pb.skipWhitespace();
        // pb.debug();
        if (pb.canAccessAtIndex(0)) {
            if (pb.advanceIfLookingAt('}') == true) {
                // Empty OBJECT
                pb.depth -= 1;
                result = true;
            } else {
                // Should be a comma separated list of "items" (key: value)
                var keepgoing = true;
                while (keepgoing) {
                    pb.skipWhitespace();
                    result = parseString(pb);
                    if (result == false) {
                        break;
                    }
                    pb.skipWhitespace();
                    if (pb.advanceIfLookingAt(':') == false) {
                        result = false;
                        keepgoing = false;
                        break;
                    }
                    pb.skipWhitespace();
                    result = parseValue(pb);
                    if (result == false) {
                        break;
                    }
                    pb.skipWhitespace();
                    if (pb.canAccessAtIndex(0) and pb.charAtOffset() == ',') {
                        pb.offset += 1;
                    } else {
                        keepgoing = false;
                        break;
                    }
                }
                if (result == true) {
                    if (pb.canAccessAtIndex(0) and pb.charAtOffset() == '}') {
                        pb.offset += 1;
                        pb.depth -= 1;
                        result = true;
                    } else {
                        print("ERROR: OBJECT @ "); pb.debug();
                        result = false;
                    }
                }
            }
        }
    } else {
        print("ERROR: Not looking at an OBJECT {} @ ", pb.charAtOffset());
        pb.debug();
    }

    return result;
}

fn parseValue(pb: &ParseBuffer) bool {
    var rv = false;
    pb.skipWhitespace();
    if (pb.canAccessAtIndex(0) == true) {
        const ch = pb.charAtOffset();
        switch (ch) {
            '"' => { rv = parseString(pb); },
            '[' => { rv = parseArray(pb); },
            '{' => { rv = parseObject(pb); },
            'f' => {
                if (pb.canAccessAtIndex(5) == true) {
                    if (pb.content[pb.offset + 1] == 'a'
                        and (pb.content[pb.offset + 2] == 'l')
                        and (pb.content[pb.offset + 3] == 's')
                        and (pb.content[pb.offset + 4] == 'e')) {
                        pb.offset += 5;
                        rv = true;
                    }
                }
            },
            't' => {
                if (pb.canAccessAtIndex(4) == true) {
                    if (pb.content[pb.offset + 1] == 'r'
                        and (pb.content[pb.offset + 2] == 'u')
                        and (pb.content[pb.offset + 3] == 'e')) {
                        pb.offset += 4;
                        rv = true;
                    }
                }
            },
            'n' => {
                if (pb.canAccessAtIndex(4) == true) {
                    if (pb.content[pb.offset + 1] == 'u'
                        and (pb.content[pb.offset + 2] == 'l')
                        and (pb.content[pb.offset + 3] == 'l')) {
                        pb.offset += 4;
                        rv = true;
                    }
                }
            },
            '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' =>  { // numeric
                var r: NumericResult = parseNumeric(pb);
                switch (r) {
                    NumericResult.Ok => |v| {
                        rv = true;
                        v.debug();
                    },
                    else => {
                        rv = false;
                    },
                }
            },
            else => {
                print("UNHANDLED @"); pb.debug();
                rv = false;
            },
        }
    } else {
        print("DONE... @ ");
        pb.debug();
    }

    return rv;
}

// a not so validating JSON parser...
fn parseJson(buf: []u8) %void {
   var pb = ParseBuffer {.content = buf, .length = buf.len, .offset = 0, .depth = 0};
   pb.debug();
   if (pb.skipUtf8Bom() == true) {
       print("Skipped UTF-8 BOM\n");
   } else {
       print("No UTF-8 BOM\n");
   }
   pb.skipWhitespace();
   pb.debug();
   const result = parseValue(&pb);
   print("result = {}\n", result);
   pb.debug();
}

pub fn main() %void {
    var args = os.args();
    print("{} a test program\n", args.nextPosix());
    var i: u16 = 0;
    _ = try getStdOutStream();
    while (args.nextPosix()) |arg| {
        print("arg[{}] = '{}'\n", i, arg);
        var file = try io.File.openRead(arg, allocator);
        defer file.close();
        const file_size = try file.getEndPos();
        print("{} bytes\n", file_size);
        var file_in_stream = io.FileInStream.init(&file);
        var buf_stream = io.BufferedInStream.init(&file_in_stream.stream);
        const st = &buf_stream.stream;
        const contents = try st.readAllAlloc(allocator, file_size + 1);
        defer allocator.free(contents);
        try parseJson(contents);
        i += 1;
    }
}
