const std = @import("std");
const io = std.io; // stdio lol
const debug = std.debug;
const assert = debug.assert;
const math = @import("std").math;
const max = math.max;
const hashmap = @import("std").hash_map;
const list = @import("std").list;
const printer = @import("printer.zig");

const fpconv_dtoa = @import("../fpconv/zfpconv.zig").zfpconv_dtoa;
const atod = @import("../fpconv/zfast_atof.zig").zatod;

// might come in handy, should things fail, 8)
// #static_eval_enable(false)

fn printStrNumNum(str: []const u8, pos: usize, level: isize) -> %void {
    %%io.stdout.write(str);
    %%io.stdout.write(":");
    %%io.stdout.printInt(usize, pos);
    %%io.stdout.write(":");
    %%io.stdout.printInt(isize, level);
    %%io.stdout.printf("\n");
}

pub error JsonError;

enum JsonType {
    JSONNull: void,
    JSONInteger: isize,
    JSONDouble: f64,
    JSONBool: bool,
    JSONString: []u8, // how is this memory handled?
    JSONArray, // list of things, ?&[]JsonNode depends on itself, maybe a GenNode as in the test?
    JSONObject, // key, value (the key is a string, we do them as JSONString right now)

    fn print(jt: &JsonType, stream: io.OutStream) -> %void {
        {}
    }
}

fn djbdHasher(v: []u8) -> u32 {
    var hash: u32 = 5831;
    var buf: [64]u8 = undefined;

    for (v) |c, i| {
        if (c == 0) break;
        hash <<%= 5;
        hash +%= hash;
        hash +%= u32(c);
    }
    // stumbling in the dark, debugging to see if we get called...
    // %%io.stdout.write("Hashed:");
    // %%io.stdout.write(v);
    // %%io.stdout.write(" to ");
    // %%io.stdout.printInt(u32, hash);
    // %%io.stdout.write(", ");
    // const sz = printer.hexPrintInt(u32, buf, hash);
    // for (buf) |x, i| {
    //    if (i+1 == sz) break;
    //    %%io.stdout.writeByte(x);
    // }
    // %%io.stdout.printf("\n");

    hash
}

fn jsonDataCmp(a: []u8, b: []u8) -> bool {
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

    result
}

const JasonHM = hashmap.HashMap([]u8, JsonType, djbdHasher, jsonDataCmp);
const JasonList = list.List(JsonNode);

enum JsonOA {
    JSONArray: []JsonType, // List of something? list.List(JsonNode)
    JSONObject: JasonHM, // HashMap
}

fn printDouble(d: f64, stream: io.OutStream) -> %void {
    var buf: [24]u8 = zeroes;
    var sz = fpconv_dtoa(d, buf);
    %%stream.write(buf[0...sz]);
    //%%stream.printf("\n");
}

pub struct JsonNode {
    kind: JsonType,
    jobject: ?JsonOA, // nah, this looks weird...

    pub fn print(jd: &const JsonNode, stream: io.OutStream) -> %void {
        %%stream.write("<JsonNode>::");
        // error: invalid cast from type 'JsonType' to 'isize'
        // %%stream.printInt(isize, isize(jd.kind));
        switch (jd.kind) {
        JSONNull => { %%stream.write("null"); },
        JSONInteger => |x| {
            %%stream.write("integer=");
            %%stream.printInt(isize, x);
        },
        JSONDouble => |x| {
           %%stream.write("double=");
           %%printDouble(x, stream);
        },
        JSONBool => |x| {
           %%stream.write("bool=");
           %%stream.write(if (x) "true" else "false");
        },
        JSONString => |x| {
           %%stream.write("string=");
           %%stream.write(x);
        },
        JSONObject => |x| {
           %%stream.write("object=");
           if (const o ?= jd.jobject) {
               // o should now be the unwrapped thingy
               switch (o) {
               JSONObject =>  |y| {
                   %%stream.write("JSON Object entries:");
                   %%stream.printInt(usize, y.entries.len);
                   var iter = y.entryIterator();
                   while (true) {
                       const e = iter.next() ?? break;
                       %%stream.write((e).key);
                       %%stream.printf("->");
                       switch((e).value) {
                       JSONString => |s| {
                           %%stream.write(s);
                           %%stream.printf("\n");
                       },
                       else => {},
                       }
                   }
               },
               else => @unreachable(),
               }
           }
        },
        else => { %%stream.write("no more info (yet)"); } ,
        }
        // newline and flush
        %%stream.printf("\n");
    }
}

pub struct JStats {
    objects: usize,
    arrays: usize,
    deepest: usize,

    pub fn print(js: &const JStats, stream: io.OutStream) -> %void {
        %%stream.write("<JStats>objects=");
        %%stream.printInt(usize, js.objects);
        %%stream.write(",arrays=");
        %%stream.printInt(usize, js.arrays);
        %%stream.write(",deepest=");
        %%stream.printInt(usize, js.deepest);
        %%stream.printf(".\n");
    }
}

enum JsonParsingState {
   NONE,
   OBJECT,
   OBJECT_COLON,
   OBJECT_VALUE,
   OBJECT_COMMA,
   ARRAY,
}

// a not so validating JSON parser...
fn parseJson(buf: []u8) -> %void {
   var jstats = JStats { .objects = 0, .arrays = 0, .deepest = 0 };
   var pos = usize(0);
   var level = isize(0);
   var js = JsonParsingState.NONE;
   var current_object: ?&JsonNode = null;
   var x: usize = 0;
   var key: []u8 = undefined; // ???
   var jl: JasonList = undefined;
   jl.init(&debug.global_allocator);
   while (pos < buf.len) {
       const cpos = pos;
       const ch = buf[cpos];
       pos += 1;
       switch (ch) {
       '\x00' => break,
       ' ', '\t', '\n', '\r' => continue, // one way to do it
       ',' => {%%printStrNumNum("COMMA", cpos, level); continue; }, // another
       ':' => %%printStrNumNum("COLON", cpos, level), // and a third
       '[' => { 
                  js = JsonParsingState.ARRAY;
                  x = 0;
                  level += 1;
                  %%printStrNumNum("ARRAY Start", cpos, level);
                  jstats.arrays += 1;
                  jstats.deepest = max(jstats.deepest, usize(level));
                  var jll: JasonList = undefined;
                  jll.init(&debug.global_allocator);
                  //var jd = JsonNode {.kind = JsonType.JSONArray, .jobject = JsonOA.JSONArray {jll} };
                  //%%jl.append(jd);
              },
       ']' => {
                  js = JsonParsingState.NONE;
                  x = 0;
                  %%printStrNumNum("ARRAY End", cpos, level);
                  level -= 1;
              },
       '{' => {
                  js = JsonParsingState.OBJECT;
                  x = 0;
                  level += 1;
                  %%printStrNumNum("OBJECT Start", cpos, level);
                  jstats.objects += 1;
                  jstats.deepest = max(jstats.deepest, usize(level));
                  var jhm: JasonHM = undefined;
                  jhm.init(&debug.global_allocator);
                  var jd = JsonNode {.kind = JsonType.JSONObject, .jobject = JsonOA.JSONObject {jhm} };
                  %%jd.print(io.stdout);
                  %%jl.append(jd);
                  current_object = &jd;
              },
       '}' => {
                  js = JsonParsingState.NONE;
                  x = 0;
                  %%printStrNumNum("OBJECT End", cpos, level);
                  if (const co ?= current_object) {
                      %%co.print(io.stdout);
                  }
                  level -= 1;
              },
       // zig TODO: '0' ... '9', '-' =>
       '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' =>  { // numeric
                  var epos = pos;
                  var must_be_int = true;
                  while (epos < buf.len; epos += 1) {
                      switch (buf[epos]) {
                      // zig TODO: '0' ... '9'
                      '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {}, // or continue
                      '.', 'e', 'E', '+', '-' => { must_be_int = false; }, // continue
                      else => break,
                      }
                  }
                  pos = epos;
                  if (must_be_int) {
                      const  v: isize = io.parseUnsigned(isize, buf[cpos...epos], 10) %% |err| {
                          @unreachable();
                      };
                      var jd = JsonNode {.kind = JsonType.JSONInteger {v},
                          .jobject = undefined};
                      %%jd.print(io.stdout);
                      %%jl.append(jd);
                  } else {
                      const v = %%atod(buf[cpos...epos]);
                      const jd = JsonNode {.kind = JsonType.JSONDouble {v},
                          .jobject = undefined};
                      %%printStrNumNum(buf[cpos...epos], cpos, isize(pos));
                      %%jd.print(io.stdout);
                      %%jl.append(jd);
                  }
              },
       '"' => { // must be a string
                var epos = pos;
                if (buf[epos] == '"') {
                   pos += 1;
                   %%printStrNumNum("EMPTY STRING", cpos, level);
                } else {
                   // must track the result
                   var esc = usize(0);
                   while (epos < buf.len; epos += 1) {
                      const sch = buf[epos];
                      // well, it could be escaped and unicode
                      if (sch > 127) {
                         var uclen = usize(0);
                         switch (sch & 0xfc) {
                         0xfc => uclen = 6,
                         0xf8 => uclen = 5,
                         0xf0 => uclen = 4,
                         0xe0 => uclen = 3,
                         0xc0, 0xc1 => uclen = 2,
                         else => uclen = 1,
                         }
                         %%printStrNumNum("UNICODE", uclen, isize(epos));
                         %%printStrNumNum(buf[cpos...epos+uclen], esc, isize(epos));
                      }
                      // %%printStrNumNum(buf[cpos...epos+1], esc, isize(epos));
                      if (esc == 0)
                      {
                          if (sch == '"') break; // good
                          if (sch == '\\') esc += 1;
                          continue;
                      } else if (esc == 1) {
                          switch (sch) {
                          '\\', '/', '"',
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
                          %%printStrNumNum("ERROR STRING", esc, isize(epos));
                          %%printStrNumNum(buf[cpos...epos], esc, isize(epos));
                          return error.JsonError;
                      }
                   }
                   pos = epos + 1;
                   if (esc > 0) %%printStrNumNum("ESC", esc, level);
                   //%%printStrNumNum(buf[cpos...pos], cpos, isize(pos));
                   const jd = JsonNode {.kind = JsonType.JSONString {buf[cpos...pos]}, .jobject = undefined };
                   %%jd.print(io.stdout);
                   %%jl.append(jd);
                   if (js == JsonParsingState.OBJECT) {
                      if (x == 0) {
                          key = buf[cpos...pos];
                          // for (buf[cpos...pos]) |*d, i| {
                          //     key[i] = *d;
                          // }
                          // key[pos - cpos] = 0;
                          x = 1;
                      } else if (x == 1) {
                          if (const co ?= current_object) {
                              if (const jo ?= co.jobject) {
                                  // jo should now be the unwrapped thingy
                                  // we putting stuff from unknown location
                                  %%io.stdout.write("Putting -> ");
                                  %%io.stdout.write(key);
                                  %%jd.print(io.stdout);
                                  // switch (jo) {
                                  // JSONObject =>  |y| {
                                  //     y.put(key, jd.kind) %% |err| {
                                  //         %%io.stdout.printf(", failed.");
                                  //         @unreachable();
                                  //     };
                                  //  },
                                  // else => @unreachable(),
                                  // }
                                  // %%io.stdout.printf("\n");
                              }
                          }
                          x = 0;
                      }
                   }
                }
       },
       'n' => {   // null?
                  if (cpos + 3 < buf.len) {
                     const wanted = "ull";
                     var r = true;
                     for (wanted) |c,i| {
                         if (c != buf[pos + i]) {
                             r = false;
                             break;
                         }
                     }
                     if (r == true)
                     {
                        const jd = JsonNode {.kind = JsonType.JSONNull {}, .jobject = undefined };
                        %%jd.print(io.stdout);
                        %%jl.append(jd);
                        //%%printStrNumNum("NULL", cpos, level);
                        pos += 3;
                     }
                  } else {
                     return error.JsonError;
                  }
              },
       'f' => {   // false?
                  if (cpos + 4 < buf.len) {
                     const value = "alse";
                     var r = true;
                     // if ()
                     for (value) |c,i| {
                         if (c != buf[pos + i]) {
                             r = false;
                             break;
                         }
                     }
                     if (r == true)
                     {
                        //%%printStrNumNum("FALSE", cpos, level);
                        const jd = JsonNode {.kind = JsonType.JSONBool {true}, .jobject = undefined };
                        %%jd.print(io.stdout);
                        %%jl.append(jd);
                        pos += 4;
                     }
                  } else {
                     return error.JsonError;
                  }
              },
       't' => {   // true?
                  if (cpos + 3 < buf.len) {
                     const wanted = "rue";
                     var r = true;
                     for (wanted) |c,i| {
                         if (c != buf[pos + i]) {
                             r = false;
                             break;
                         }
                     }
                     if (r == true)
                     {
                        // %%printStrNumNum("TRUE", cpos, level);
                        // until unions work but we have enums with payload, hurray!!
                        const jd = JsonNode {.kind = JsonType.JSONBool {true}, .jobject = undefined };
                        %%jd.print(io.stdout);
                        %%jl.append(jd);
                        pos += 3;
                     }
                  } else {
                     return error.JsonError;
                  }
              },
       else => {
                   %%printStrNumNum("???", cpos, level);
                   return error.JsonError;
                   //continue;
               },
       }
       // %%printStrNumNum("JSON level", cpos, level);
   }

   if (level == 0) {
       %%io.stdout.printf("JSON may be ok\n");
   } else {
       %%io.stdout.printf("Possibly bad JSON\n");
   }
   if (const co ?= current_object) {
       %%co.print(io.stdout);
   }
   %%jstats.print(io.stdout);
   {var it = usize(0);
       while (it < jl.len; it += 1) {
           %%jl.items[it].print(io.stdout);
       }
   }
}

// cannot have noalias on non-pointer but const
fn printNumberAndArg(arg_num: usize, arg_str: []const u8) -> %void {
    %%io.stdout.printInt(usize, arg_num);
    %%io.stdout.write(": ");
    // these are possible: arg_str.len *= 20, arg_str.len = 0;
    // how can I move that pointer? arg_str.ptr = u8(&arg_num);
    %%io.stdout.write(arg_str);
    %%io.stdout.write(", ");
    %%io.stdout.printInt(usize, arg_str.len);
    // finally newline and flush (not format)
    %%io.stdout.printf(" bytes?\n");
    // failed, my bad probably
    //%%debug.printStackTrace();
}

pub fn main(args: [][] u8) -> %void {
    // var bstring = BString {.str = zeroes, .pos = 0,};
    // How do I make a BString with a larger string buffer?
    var buf: [16 * 1024]u8 = zeroes; // undefined?
    %%io.stdout.printf(args[0]);
    %%io.stdout.printf(" a test program\n");
    // var pargs = args[1...2];
    for (args[1...]) |arg, i| {
        %%printNumberAndArg(i, arg);
        var is: io.InStream = undefined;
        is.open(arg) %% |err| {
            %%io.stderr.printf("Unable to open file: ");
            %%io.stderr.printf(@errorName(err));
            %%io.stderr.printf("\n");
            return err;
        }; //else {
        //defer %%is.close();
        const sz = is.read(buf) %% |err| {
            %%io.stderr.write("Unable to read file: ");
            %%io.stderr.write(@errorName(err));
            %%io.stderr.printf("\n");
            return err;
        };
        %%printNumberAndArg(sz, " bytes read");
        %%printNumberAndArg(%%is.getPos(), "getPos");
        %%parseJson(buf[0...sz]);
        is.close() %% |err| {
            %%io.stderr.write("Unable to close file: ");
            %%io.stderr.write(@errorName(err));
            %%io.stderr.printf("\n");
            return err;
        };
    }
}
