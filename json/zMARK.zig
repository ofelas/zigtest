// -*- mode:zig; indent-tabs-mode:nil; comment-start:"// "; -*-
// Extend JSON to JSON5 (and possibly MARK)
// The biggest problem with these are the lack of proper numbers (hex, int signed/unsigned)
// Maybe it should be something more like Amazon ION or libucl?!?
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

var localmemory: [16 << 20]u8 = undefined;
var fballoc = std.mem.FixedBufferAllocator.init(localmemory[0..]);

/// There may be a simpler way...
var stdout_file: std.os.File = undefined;
var stdout_file_out_stream: io.FileOutStream = undefined;
var stdout_stream: ?&io.OutStream(io.FileOutStream.Error) = null;

pub fn print(comptime fmt: []const u8, args: ...) void {
    const stream = getStdOutStream() catch |_| return;
    stream.print(fmt, args) catch |_| return;
}

inline fn getStdOutStream() !&io.OutStream(io.FileOutStream.Error) {
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

fn printDouble(d: f64, stream: io.OutStream) !void {
    var buf: [24]u8 = zeroes;
    var sz = fpconv_dtoa(d, buf);
    !stream.write(buf[0 .. sz]);
}

fn formatDouble(d: f64, buf: &[24]u8) void {
    var sz = fpconv_dtoa(d, buf);
}

pub const JsonError = error {
    WouldBlock,
};

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
        const nextOffset = pb.offset +% index;
        return (nextOffset >= pb.offset) and (nextOffset < pb.content.len);
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
        // this would need to handle single and multiline comments
        while (true) {
            while (pb.canAccessAtIndex(0) and (pb.charAtOffset() <= 32)) {
                pb.offset += 1;
            }
            // Go back if we went to far...(no comment)
            if (pb.offset == pb.length) {
                pb.offset -= 1;
            }
            if (pb.canAccessAtIndex(1) and (pb.charAtOffset() == '/')) {
                const startsAt = pb.offset;
                if (pb.content[pb.offset + 1] == '/') {
                    // consume until end of line
                    while (pb.canAccessAtIndex(0) and (pb.charAtOffset() != '\n')) {
                        pb.offset += 1;
                    }
                    if (pb.charAtOffset() == '\n') {
                        print("COMMENT: '{}'\n", pb.content[startsAt .. pb.offset]);
                        pb.offset += 1;
                    }
                }
            } else {
                break;
            }
        }
    }
};


/// Parse a string, we must be looking at the initial '"' (double quote)
/// a single quote or a char in 'a' ... 'z', 'A' ... 'Z'
fn parseString(pb: &ParseBuffer) bool {
    var rv = false;
    const ch = pb.charAtOffset();
    switch (ch) {
        '\'', '"' => {
            var previous = ch;
            pb.offset += 1;
            const startsAt = pb.offset;
            // Now find the ending '"', ignoring utf8, escapes and what not
            while (pb.canAccessAtIndex(0)) {
                if (pb.charAtOffset() == ch and previous != '\\') {
                    rv = true;
                    print("STRING: '{}'\n", pb.content[startsAt .. pb.offset]);
                    pb.offset += 1;
                    break;
                }
                previous = pb.charAtOffset();
                pb.offset += 1;
            }
        },
        'a' ... 'z', 'A' ... 'Z', '0' ... '9', '_' => {
            // consume a ... z, A ... Z, 0 ... 9 and _
            const startsAt = pb.offset;
            pb.offset += 1;
            while (pb.canAccessAtIndex(0)) {
                switch (pb.charAtOffset()) {
                    'a' ... 'z', 'A' ... 'Z', '0' ... '9', '_' => {
                        pb.offset += 1;
                    },
                    else => {
                        break;
                    }
                }
            }
            print("STRING: '{}'\n", pb.content[startsAt .. pb.offset]);
            rv = true;
        },
        else => {
            print("ERROR: Not looking at a STRING {c} @ ", pb.charAtOffset());
            pb.debug();
        }
    }

    return rv;
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
                    if (pb.charAtOffset() == ']') {
                        // this should cover trailing comma at end of list/array
                        result = true;
                        break;
                    }
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
                    if (pb.charAtOffset() == '}') {
                        // this should cover trailing comma at end of object
                        break;
                    }
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
            '[' => { rv = parseArray(pb); },
            '{' => { rv = parseObject(pb); },
            // ', single/double quoted string
            '"', '\'' => { rv = parseString(pb); },
            // NOTE: false, true, null are handled below
                '_', 'a' ... 'e', 'g' ... 'm', 'o' ... 's', 'u' ... 'z', 'A' ... 'Z' => {
                rv = parseString(pb);
            },
            'f' => {
                if (pb.canAccessAtIndex(5) == true) {
                    if (pb.content[pb.offset + 1] == 'a'
                        and (pb.content[pb.offset + 2] == 'l')
                        and (pb.content[pb.offset + 3] == 's')
                        and (pb.content[pb.offset + 4] == 'e')) {
                        pb.offset += 5;
                        rv = true;
                    }
                } else {
                    rv = parseString(pb);
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
                } else {
                    rv = parseString(pb);
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
                } else {
                    rv = parseString(pb);
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
fn parseJson(buf: []u8) bool {
   var pb = ParseBuffer {.content = buf, .length = buf.len, .offset = 0, .depth = 0};
   pb.debug();
   if (pb.skipUtf8Bom() == true) {
       print("Skipped UTF-8 BOM\n");
   } else {
       print("No UTF-8 BOM\n");
   }
   pb.skipWhitespace();
   pb.debug();
   const rv = parseValue(&pb);
   print("rv = {}\n", rv);
   pb.debug();

   return rv;
}

pub fn main() !void {
    var args = os.args();
    print("{} a test program\n", args.nextPosix());
    var i: u16 = 0;
    _ = try getStdOutStream();
    while (args.nextPosix()) |arg| {
        print("arg[{}] = '{}'\n", i, arg);
        var file = try std.os.File.openRead(allocator, arg);
        defer file.close();
        const file_size = try file.getEndPos();
        var file_in_stream = io.FileInStream.init(&file);
        var buf_stream = io.BufferedInStream(io.FileInStream.Error).init(&file_in_stream.stream);
        print("{} bytes\n", file_size);
        //var buf_stream = io.BufferedInStream.init(&file_in_stream.stream);
        const st = &buf_stream.stream;
        const contents = try st.readAllAlloc(&fballoc.allocator, file_size + 1);
        defer fballoc.allocator.free(contents);
        const rv = parseJson(contents);
        i += 1;
    }
}
