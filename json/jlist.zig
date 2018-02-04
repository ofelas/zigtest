const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;


error IndexError;

pub fn List(comptime T: type) type {
    return struct {
    const Self = List(T);

    items: []T,
    len: usize,
    allocator: &Allocator,

    pub fn init(allocator: &Allocator) Self {
        return Self {
            .items = []align(64) T{},
            .len = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(l: &Self) void {
        return l.allocator.free(T, l.items);
    }

    pub fn toSlice(l: &Self) []T {
        return l.items[0 .. l.len];
    }

    pub fn append(l: &Self, item: &T) %void {
        const new_length = l.len + 1;
        try l.ensureCapacity(new_length);
        l.items[l.len] = item;
        l.len = new_length;
    }

    pub fn push(l: &Self, item: &const T) %usize {
        const cur = l.len;
        const new_length = l.len + 1;
        try l.ensureCapacity(new_length);
        l.items[l.len] = *item;
        l.len = new_length;
        return cur;
    }

    pub fn pop(l: &Self) %T {
        var v: T = l.items[l.len - 1];
        l.len -= 1;
        return v;
    }

    pub fn last(l: &Self) %T {
        if (l.len < 1) {
            return error.IndexError;
        }
        var v: T = l.items[l.len - 1];
        return v;
    }

    pub fn resize(l: &Self, new_len: usize) %void {
        try l.ensureCapacity(new_len);
        l.len = new_len;
    }

    pub fn ensureCapacity(l: &Self, new_capacity: usize) %void {
        var better_capacity = l.items.len;
        if (better_capacity >= new_capacity) return;
        while (true) {
            better_capacity += better_capacity / 2 + 8;
            if (better_capacity >= new_capacity) break;
        }
        l.items = try l.allocator.realloc(T, l.items, better_capacity);
    }
    };
}

test  "basicListTest" {
    var list = List(i32).init(&debug.global_allocator);
    defer list.deinit();

    {var i: usize = 0; while (i < 10) : (i += 1) {
        %%list.append(i32(i + 1));
    }}

    {var i: usize = 0; while (i < 10) : (i += 1) {
        assert(list.items[i] == i32(i + 1));
    }}
}
