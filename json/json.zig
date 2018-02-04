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

fn printStrNumNum(str: []const u8, pos: usize, level: isize) void {
    print("{}: {}: {}\n", str, pos, level);
}

error JsonError;

const JasonHM = hashmap.HashMap([]u8, JsonValue, djbdHasher, jsonDataCmp);
const JasonRefHM = hashmap.HashMap([]u8, &JsonValue, djbdHasher, jsonDataCmp);

const JasonValueList = list.List(JsonValue);
const JasonValueRefList = list.List(&JsonValue);
const JsonStateStack = list.List(JsonParsingState);

fn djbdHasher(v: []u8) u32 {
    var hash: u32 = 5831;

    for (v) |c, i| {
        if (c == 0) break;
        hash <<= 5;
        hash +%= hash;
        hash +%= u32(c);
    }

    return hash;
}

fn jsonDataCmp(a: []u8, b: []u8) bool {
    var result: bool = false;

    if (a.len == b.len) {
        result = true;
        for (a) |c, i| {
           if (c != b[i]) {
               result= false;
               break;
           }
        }
    }

    return result;
}

pub const JStats = struct {
    objects: usize,
    arrays: usize,
    deepest: usize,

    pub fn print(js: &const JStats, stream: ?&io.OutStream) %void {
        if (stream) |s| {
            try s.print("<JStats>objects={}, arrays={}, deepest={}\n",
                        js.objects, js.arrays, js.deepest);
        }
    }

    pub fn addObject(js: &JStats, level: isize) void {
        js.objects += 1;
        js.deepest = max(js.deepest, usize(level));
    }

    pub fn addArray(js: &JStats, level: isize) void {
        js.arrays += 1;
        js.deepest = max(js.deepest, usize(level));
    }
};



const JsonValue = union(enum) {
    JSONNull: void,
    JSONInteger: isize,
    JSONDouble: f64,
    JSONBool: bool,
    JSONString: []u8, // a slice probably fixed size
    // these have variable size, it might not  be such a good idea
    JSONArray: usize, // number of children
    JSONObject: usize, // number of children

    fn print(jt: &JsonValue, stream: ?&io.OutStream) %void {
        if (stream) |s| {
            switch (*jt) {
                JsonValue.JSONNull    => |v| { try s.print("null"); },
                JsonValue.JSONBool    => |v| { try s.print("{}", if (v) "true" else "false"); },
                JsonValue.JSONString  => |v| { try s.print("{}", v); },
                JsonValue.JSONInteger => |v| { try s.print("{}", v); },
                JsonValue.JSONDouble  => |v| { try s.print("{}", v); },
                JsonValue.JSONArray   => |v| {
                    try s.print("array: {}", v);
                },
                JsonValue.JSONObject  => |v| {
                    try s.print("object: {}", v);
                },
            else => {},
            }
            try s.print("\n");
            }
    }
};

const JsonNode = struct {
    kind: JsonValue,
    level: usize,
    parent: usize, // index of parent in list of values

};

const JsonNodeList = list.List(JsonNode);
const JsonParentList = list.List(usize);

const JsonContainer = struct {
    vlist: JsonNodeList,
    parents: JsonParentList,
    level: isize,

    fn add(jc: &JsonContainer, jv: &JsonValue) %void {
        switch (*jv) {
            JsonValue.JSONArray => { jc.level += 1; },
            JsonValue.JSONObject => { jc.level += 1; },
            else => {},
        }
        const p = jc.parents.last() catch |_| 0;
        const what = JsonNode {.kind = *jv, .level = usize(jc.level), .parent = p};
        const where = try jc.vlist.push(&what);
        if (jc.parents.len > 0) {
            switch (jc.vlist.items[p].kind) {
            JsonValue.JSONArray => |a| {}, // njet workie, a += 1;
            JsonValue.JSONObject => {},
            else => {},
            }
        }
        switch (*jv) {
            JsonValue.JSONArray => { _ = try jc.parents.push(&where); },
            JsonValue.JSONObject => { _ = try jc.parents.push(&where); },
            else => {},
        }
        return;
    }

    fn addKV(jc: &JsonContainer, k: []u8, jv: &JsonValue) %void {
        // what do we do with the key?
        switch (*jv) {
            JsonValue.JSONArray => { jc.level += 1; },
            JsonValue.JSONObject => { jc.level += 1; },
            else => {},
        }
        const p = if (jc.parents.len > 0) try jc.parents.last() else 0;
        const where = try jc.vlist.push(JsonNode {.kind = *jv, .level = usize(jc.level), .parent = p});
        switch (*jv) {
            JsonValue.JSONArray => { _ = try jc.parents.push(&where); },
            JsonValue.JSONObject => { _ = try jc.parents.push(&where); },
            else => {},
        }
    }

    fn up(jc: &JsonContainer) void {
        jc.level -= 1;
    }

    fn print(jc: &JsonContainer, stream: ?&io.OutStream) %void {
        if (stream) |s| {
        {
            var it = usize(0);
            try s.print("parents\n");
            while (it < jc.parents.len) : (it += 1) {
                try s.print("p={} -> {}\n", it, jc.parents.items[it]);
            }
        }
        {
            var it = usize(0);
            try s.print("values\n");
            while (it < jc.vlist.len) : (it += 1) {
                try s.print("{}:l={}:p={} -> ", it, jc.vlist.items[it].level, jc.vlist.items[it].parent);
                try jc.vlist.items[it].kind.print(stream);
            }
        }
        }
    }
};

// fn funcname (arguments) returntype {}
fn mkJsonContainer() JsonContainer {
    return JsonContainer { .vlist = JsonNodeList.init(allocator),
            .parents = JsonParentList.init(allocator),
            .level = 0 };
}

const JsonParsingState = enum(u16) {
    NONE,                       // 0
    OBJECT,                     // 1
    OBJECT_KEY,                 // 2
    OBJECT_COLON,               // 3
    OBJECT_VALUE,               // 4
    OBJECT_COMMA,               // 5
    ARRAY,                      // 6

    fn print(jps: &JsonParsingState, stream: ?&io.OutStream) %void {
        if (stream) {
            try st.print("JsonParsingState.{}", @memberName(JsonParsingState, jps));
        }
    }
};

//can_access_at_index(buffer, index) ((buffer != NULL) && (((buffer)->offset + index) < (buffer)->length))

const ZJSON_NESTING_LIMIT: usize = 64;

const ParseBuffer = struct {
    const Self = this;
    content: []const u8,
    // We actually have the length in content.len, 8)
    length: usize,
    offset: usize,
    depth: usize, // Recursion level, we impose an arbitrary limit
    // Maybe an allocator?

    fn debug(pb: &Self) void {
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
    if (pb.charAtOffset() == '"') {
        pb.offset += 1;
        const startsAt = pb.offset;
        // Now find the ending '"', ignoring utf8
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
    i: i64,
    f: f64,
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
            // zig TODO: '0' ... '9'
            '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
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
                    print("NUMBER: '{}' {} {}\n", pb.content[startsAt .. pb.offset], digits, dots);
                    if (must_be_int == true) {
                        if (parseInt(i64, pb.content[startsAt .. pb.offset], 10)) |v| {
                           result = NumericResult { .Ok = NumericValue { .i = v, .f = f64(v)} };
                        } else |err| {
                        }
                    } else {
                        // parse the float
                        if (atod(pb.content[startsAt .. pb.offset])) |v| {
                            result = NumericResult { .Ok = NumericValue { .i = i64(v), .f = v} };
                        } else |err| {
                            print("ERROR: {}\n", err);
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
    if (pb.charAtOffset() == '[') {
        // Move past the '['
        pb.offset += 1;
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
                    if (pb.canAccessAtIndex(0) and pb.charAtOffset() == ',') {
                        pb.offset += 1;
                        i += 1;
                    } else {
                        keepgoing = false;
                        break;
                    }
                }
                if (pb.canAccessAtIndex(0) and pb.charAtOffset() == ']') {
                    pb.offset += 1;
                    pb.depth -= 1;
                    print("ARRAY of {} items at depth {}\n", i, pb.depth);
                    result = true;
                } else {
                    print("ERROR: ARRAY @ "); pb.debug();
                    result = false;
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
    if (pb.charAtOffset() == '{') {
        // Move past the '{'
        pb.offset += 1;
        pb.skipWhitespace();
        pb.debug();
        if (pb.canAccessAtIndex(0)) {
            if (pb.charAtOffset() == '}') {
                // Empty OBJECT, move past the '}'...
                pb.offset += 1;
                pb.depth -= 1;
                result = true;
            } else {
                // Should be a comma separated list of "items" (key: value)
                var keepgoing = true;
                while (keepgoing) {
                    pb.skipWhitespace();
                    result = parseString(pb);
                    pb.skipWhitespace();
                    if (pb.charAtOffset() == ':') {
                        pb.offset += 1;
                    } else {
                        keepgoing = false;
                        break;
                    }
                    pb.skipWhitespace();
                    result = parseValue(pb);
                    pb.skipWhitespace();
                    if (pb.canAccessAtIndex(0) and pb.charAtOffset() == ',') {
                        pb.offset += 1;
                    } else {
                        keepgoing = false;
                        break;
                    }
                }
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
    } else {
        print("ERROR: Not looking at an OBJECT {} @ ", pb.charAtOffset());
        pb.debug();
    }

    return result;
}

fn parseValue(pb: &ParseBuffer) bool {
    var result = false;
    pb.skipWhitespace();
    if (pb.canAccessAtIndex(0) == true) {
        const ch = pb.charAtOffset();
        switch (ch) {
            '"' => { result = parseString(pb); },
            '[' => { result = parseArray(pb); },
            '{' => { result = parseObject(pb); },
            'f' => {
                if (pb.canAccessAtIndex(5) == true) {
                    if (pb.content[pb.offset + 1] == 'a'
                        and (pb.content[pb.offset + 2] == 'l')
                        and (pb.content[pb.offset + 3] == 's')
                        and (pb.content[pb.offset + 4] == 'e')) {
                        pb.offset += 5;
                        result = true;
                    }
                }
            },
            't' => {
                if (pb.canAccessAtIndex(4) == true) {
                    if (pb.content[pb.offset + 1] == 'r'
                        and (pb.content[pb.offset + 2] == 'u')
                        and (pb.content[pb.offset + 3] == 'e')) {
                        pb.offset += 4;
                        result = true;
                    }
                }
            },
            'n' => {
                if (pb.canAccessAtIndex(4) == true) {
                    if (pb.content[pb.offset + 1] == 'u'
                        and (pb.content[pb.offset + 2] == 'l')
                        and (pb.content[pb.offset + 3] == 'l')) {
                        pb.offset += 4;
                        result = true;
                    }
                }
            },
            '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' =>  { // numeric
                var r: NumericResult = parseNumeric(pb);
                switch (r) {
                    NumericResult.Ok => |v|{
                        result = true;
                        // Don't use {.<n>} for float as it fails...
                        // std/fmt/index.zig:151:43
                        // Unable to dump stack trace: OutOfMemory
                        print("r.i={}, r.f={}\n", v.i, v.f);
                    },
                    else => {},
                }
            },
            else => {
                print("UNHANDLED @"); pb.debug();
                result = false;
            },
        }
    } else {
        print("DONE... @ ");
        pb.debug();
    }

    return result;
}

// a not so validating JSON parser...
fn parseJson(buf: []u8) %void {
    //var allocator = debug.global_allocator;
   var jstats = JStats { .objects = 0, .arrays = 0, .deepest = 0 };
   var pos = usize(0);
   var level = isize(0);
   var js = JsonParsingState.NONE;
   var key: []u8 = undefined; // ???
   var state_stack = JsonStateStack.init(allocator);
   var jv: JsonValue = undefined; // value
   var jsidx = try state_stack.push(js);
   var storage = mkJsonContainer();

   if (true) {
   var pb = ParseBuffer {.content = buf, .length = buf.len, .offset = 0, .depth = 0};
   pb.debug();
   _ = pb.skipUtf8Bom();
   pb.skipWhitespace();
   pb.debug();
   const result = parseValue(&pb);
   print("result = {}\n", result);
   pb.debug();
   } else {
   while (pos < buf.len) {
       const cpos = pos;
       const ch = buf[cpos];
       pos += 1;
       switch (ch) {
       '\x00' => break,
       ' ', '\t', '\n', '\r' => continue, // one way to do it
       ',' => continue, // another %%printStrNumNum("COMMA", cpos, level); 
       ':' => {
           if (js != JsonParsingState.OBJECT_COLON) {
               print("COLON in WRONG parsing state\n");
               // u16(js) so that print can handle it
               print("STATE {} {}\n", cpos, u16(js));
               {var it = usize(0);
                   while (it < state_stack.len) : (it += 1) {
                       print("{} -> {}\n", it, u16(state_stack.items[it]));
                   }
               }
           }
           js = JsonParsingState.OBJECT_VALUE;
       },
       '/' => {
           // it could be a comment that we will ignore...
           if (buf[pos] == '/') {
               var epos = pos;
               while (epos < buf.len) : (epos += 1) {
                   if (buf[epos] == '\n') {
                       print("{}\n", buf[pos-1 .. epos]);
                       pos = epos;
                       break;
                   }
               }
           } else {
               return error.JsonError;
           }
       },
       '[' => {
           jsidx = try state_stack.push(JsonParsingState.ARRAY);
           print("ARRAY Start {} {}\n", cpos, level);
           jstats.addArray(level);
           // does not work anymore
           // jll.init(&debug.global_allocator);
           jv = JsonValue { .JSONArray = 0 };
           try storage.add(&jv);

           level += 1;
           if (js == JsonParsingState.OBJECT_VALUE) {
               js = JsonParsingState.OBJECT_KEY;
           } else {
               js = JsonParsingState.ARRAY;
           }

       },
       ']' => {
           print("STACK Last {} {}\n", cpos, u16(state_stack.last() catch |_| JsonParsingState.NONE));
           print("ARRAY End {} {}\n", cpos, level);
           level -= 1;
           js = try state_stack.pop(); // pop of ARRAY
           storage.up();
       },
       '{' => {
                  js = JsonParsingState.OBJECT_KEY; // what we expect next
                  jsidx = try state_stack.push(JsonParsingState.OBJECT_KEY);
                  level += 1;
                  print("OBJECT Start {} {}\n", cpos, level);
                  jstats.addObject(level);
                  jv = JsonValue { .JSONObject = 0 };
                  try storage.add(&jv);
              },
       '}' => {
                  print("STACK Last {} {}\n", cpos, u16(state_stack.last() catch |_| JsonParsingState.NONE));
                  print("OBJECT End {} {}\n", cpos, level);
                  level -= 1;
                  js = try state_stack.pop();
                  storage.up();
              },
       // zig TODO: '0' ... '9', '-' =>
       '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' =>  { // numeric
                  var epos = pos;
                  var must_be_int = true;
                  while (epos < buf.len) : (epos += 1) {
                      switch (buf[epos]) {
                      // zig TODO: '0' ... '9'
                      '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {}, // or continue
                      '.', 'e', 'E', '+', '-' => { must_be_int = false; }, // continue
                      else => break,
                      }
                  }
                  pos = epos;
                  if (must_be_int) {
                      const  v: isize = try parseUnsigned(isize, buf[cpos .. epos], 10);
                      //%% |err| {
                      //    @unreachable();
                      //};
                      jv = JsonValue{.JSONInteger = v};
                      print("key='{}'\n", key);
                      try jv.print(stdout_stream);
                      try storage.addKV(key, &jv);
                  } else {
                      const v = try atod(buf[cpos .. epos]);
                      jv = JsonValue{.JSONDouble = v};
                      try jv.print(stdout_stream);
                      try storage.addKV(key, &jv);
                  }
                  if (js == JsonParsingState.OBJECT_VALUE) {
                      js = JsonParsingState.OBJECT_KEY;
                  }
              },
       '"', '\'' => { // must be a string (accept ', borrowed from LaxJson)
                const echar = ch;
                var epos = pos;
                if (buf[epos] == echar) {
                   pos += 1;
                   print("EMPTY STRING {} {}\n", cpos, level);
                } else {
                   // must track the result
                   var esc = usize(0);
                   while (epos < buf.len) : (epos += 1) {
                      const sch = buf[epos];
                      // well, it could be escaped and unicode
                      if (sch > 127) {
                          const v = sch & 0xfc;
                          var uclen: usize = 0;
                          switch (u8(v)) {
                              0xfc => uclen = 6,
                              0xf8 => uclen = 5,
                              0xf0 => uclen = 4,
                              0xe0 => uclen = 3,
                              0xc0, 0xc1 => uclen = 2,
                              else => uclen = 1,
                           }
                          print("UNICODE {} {}\n", uclen, isize(epos));
                          print("{} {} {}\n", buf[cpos .. epos+uclen], esc, isize(epos));
                      }
                      if (esc == 0)
                      {
                          if (sch == echar) break; // good
                          if (sch == '\\') esc += 1;
                          continue;
                      } else if (esc == 1) {
                          if (sch == echar) { esc = 0; continue; }
                          switch (sch) {
                          '\\', '/',
                          'b', 'n', 'r', 'f', 't' => {esc = 0; continue; },
                          'u' => { esc += 1; continue; },
                          else => return error.JsonError,
                          }
                      } else if (esc < 6) { // unicode escape \uXXXX (esc -> 123456)
                          switch (sch) {
                          // zig TODO: '0' ... '9' => { esc += 1; continue; },
                          '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
                          'a', 'b', 'c', 'd', 'e', 'f',
                          'A', 'B', 'C', 'D', 'E', 'F' => esc += 1,
                          else => return error.JsonError,
                          }
                          if (esc == 6) {
                              // consume the unicode escape
                              esc = 0;
                          }
                      } else {
                          print("ERROR STRING {} {}\n", esc, isize(epos));
                          print("{} {} {}\n", buf[cpos .. epos], esc, isize(epos));
                          return error.JsonError;
                      }
                   }
                   pos = epos + 1;
                   if (esc > 0) print("ESC {} {}\n", esc, level);
                   jv = JsonValue{.JSONString = buf[cpos .. pos]};
                   try jv.print(stdout_stream);
                   if (js == JsonParsingState.OBJECT_KEY) {
                       key = buf[cpos .. pos];
                       js = JsonParsingState.OBJECT_COLON;
                   } else if (js == JsonParsingState.OBJECT_VALUE) {
                       js = JsonParsingState.OBJECT_KEY;
                       try storage.addKV(key, &jv);
                   } else if ((js == JsonParsingState.ARRAY) or (js == JsonParsingState.OBJECT_COLON)) {
                       try storage.addKV(key, &jv);
                   } else {
                       print("{} hmm\n", u16(js));
                   }
              }
       },
       'n' => {   // null?
                  if (cpos + 3 < buf.len) {
                     var r = true;
                     for ("ull") |c,i| {
                         if (c != buf[pos + i]) {
                             r = false;
                             break;
                         }
                     }
                     if (r == true)
                     {
                         jv = JsonValue{.JSONNull = {}};
                         try jv.print(stdout_stream);
                         try storage.addKV(key, &jv);
                         pos += 3;
                         if (js == JsonParsingState.OBJECT_VALUE) {
                             js = JsonParsingState.OBJECT_KEY;
                         }
                     }
                  } else {
                     return error.JsonError;
                  }
              },
       'f' => {   // false?
                  if (cpos + 4 < buf.len) {
                     var r = true;
                     // if ()
                     for ("alse") |c,i| {
                         if (c != buf[pos + i]) {
                             r = false;
                             break;
                         }
                     }
                     if (r == true)
                     {
                         jv = JsonValue{.JSONBool = false};
                         try jv.print(stdout_stream);
                         pos += 4;
                         try storage.addKV(key, &jv);
                     }
                  } else {
                     return error.JsonError;
                  }
                  if (js == JsonParsingState.OBJECT_VALUE) {
                      js = JsonParsingState.OBJECT_KEY;
                  }
              },
       't' => {   // true?
                  if (cpos + 3 < buf.len) {
                     var r = true;
                     for ("rue") |c,i| {
                         if (c != buf[pos + i]) {
                             r = false;
                             break;
                         }
                     }
                     if (r == true)
                     {
                         jv = JsonValue{.JSONBool = true};
                         print("{}:\n", level);
                         try jv.print(stdout_stream);
                         pos += 3;
                         try storage.addKV(key, &jv);
                     }
                  } else {
                      return error.JsonError;
                  }
                  if (js == JsonParsingState.OBJECT_VALUE) {
                      js = JsonParsingState.OBJECT_KEY;
                  }
              },
       else => {
                   print("??? {} {}\n", cpos, level);
                   return error.JsonError;
               },
       }
   }

   if (level == 0) {
       print("JSON may be ok\n");
   } else {
       print("Possibly bad JSON\n");
   }
   try jstats.print(stdout_stream);
   print("state_stack: level={}\n", level);
   {var it = usize(0);
       while (it < state_stack.len) : (it += 1) {
               print("{} -> {}\n", it, u16(state_stack.items[it]));
       }
   }

   try storage.print(stdout_stream);
   }
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
