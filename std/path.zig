// -*- mode:zig; indent-tabs-mode:nil;  -*-
const std = @import("std");
const mem = std.mem;
const cstr = std.cstr;
const Allocator = mem.Allocator;
const debug = std.debug;
const warn = debug.warn;
const builtin = @import("builtin");

const fs = @import("fs.zig");

pub const Path = struct {
    const Self = this;

    allocator: *Allocator,
    inner: std.Buffer,

    pub fn init(allocator: *Allocator, path: []const u8) !Path {
        if (std.Buffer.init(allocator, path)) |buf| {
            return Self { .allocator = allocator,
                           .inner = buf };
        } else |err| {
            return err;
        }
    }


    pub fn deinit(self: *Self) void {
        // leave allocator alone
        self.inner.deinit();
    }

    pub fn initSize(allocator: *Allocator, size: usize) !Path {
        if (std.Buffer.initSize(allocator, size)) |buf| {
            return Self { .allocator = allocator,
                           .inner = buf };
        } else |err| {
            return err;
        }
    }

    pub fn cptr(self: *const Self) [*]const u8 {
        return self.inner.ptr();
    }

    pub fn append(self: *Self, buf: []const u8) !void {
        return self.inner.append(buf);
    }

    pub fn metadata(self: *const Self) !fs.Metadata {
        return fs.Metadata.init(self.cptr());
    }

    pub fn exists(self: *const Self) bool {
        if (self.metadata()) |_| {
            return true;
        } else |err| {
            return false;
        }
    }

    pub fn is_file(self: *const Self) bool {
        if (self.metadata()) |meta| {
            return meta.is_file();
        } else |err| {
            return false;
        }
    }

    pub fn is_dir(self: *const Self) bool {
        if (self.metadata()) |meta| {
            return meta.is_dir();
        } else |err| {
            return false;
        }
    }
};


test "Path" {
    var direct_allocator = std.heap.DirectAllocator.init();
    defer direct_allocator.deinit();
    const allocator = &direct_allocator.allocator;

    var p = try Path.initSize(allocator, 0);
    try p.append("testfile.");
    try p.append("txt");
    debug.assert(p.exists() == true);
    debug.assert(p.is_file() == true);
    debug.assert(p.is_dir() == false);
    p.deinit();

    var pp = try Path.init(allocator, "testfile.txt");
    debug.assert(pp.exists() == true);
    debug.assert(pp.is_file() == true);
    debug.assert(pp.is_dir() == false);

    var meta = try fs.Metadata.initPath(&pp);
    debug.assert(meta.is_file() == true);
    debug.assert(meta.is_dir() == false);
}
