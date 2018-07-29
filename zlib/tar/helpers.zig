// -*- mode:zig; indent-tabs-mode:nil;  -*-
const mem = @import("std").mem;
const builtin = @import("builtin");

fn typeOfMember(comptime T: type, m: []const u8) type {
    comptime switch (@typeInfo(T)) {
        builtin.TypeId.Struct => |s| {
            for (s.fields) |f| {
                if (mem.eql(u8, f.name, m)) {
                    return f.field_type;
                }
            }
            unreachable;
        },
        else => unreachable,
    };
}
