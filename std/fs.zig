// -*- mode:zig; indent-tabs-mode:nil;  -*-
const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const debug = std.debug;
const warn = debug.warn;
const builtin = @import("builtin");

const posix = std.os.posix;

const fs_impl = @import("fs_impl.zig");
const Path = @import("path.zig").Path;

const ConstPath = []const u8;

// Rust tuple struct
// pub struct Permissions(fs_impl::FilePermissions);
pub fn tuplestruct(v: var) type {
    return struct {
        @"0": v,
    };
}
  
pub const Permissions = struct {
    const Self = this;

    inner: fs_impl.FilePermissions,

    pub fn readonly(self: *const Self) bool {
        return self.inner.readonly();
    }

    pub fn set_readonly(self: *Self, readonly: bool) void {
        self.inner.set_read_only(readonly);
    }

    pub fn from_inner(f: FilePermissions) Permissions {
        return Permissions {.inner = f};
    }

    pub fn as_inner(self: *const Self) *const fs_impl.FilePermissions {
        return &self.inner;
    }
};

pub const FileType = struct {
    const Self = this;

    inner: fs_impl.FileType,

    pub fn is_file(self: *const Self) bool {
        return self.inner.is_file();
    }

    pub fn is_dir(self: *const Self) bool {
        return self.inner.is_dir();
    }

    pub fn is_symlink(self: *const Self) bool {
        return self.inner.is_symlink();
    }

    pub fn as_inner(self: *const Self) &fs_impl.FileType {
        return &self.inner;
    }

    // #[stable(feature = "file_type_ext", since = "1.5.0")]
    // impl FileTypeExt for fs::FileType {
    pub fn is_block_device(self: *const Self) bool { return self.inner.is_block_device(); }
    pub fn is_char_device(self: *const Self) bool { return self.inner.is_char_device(); }
    pub fn is_fifo(self: *const Self) bool { return self.inner.is_fifo(); }
    pub fn is_socket(self: *const Self) bool { return self.inner.is_socket(); }
    // }
};

pub fn metadata(path: [*]const u8) !Metadata {
    return Metadata.init(path);
}

pub const Metadata = struct {
    const Self = this;

    inner: fs_impl.FileAttr,

    pub fn init(path: [*]const u8) !Metadata {
        if (fs_impl.stat(path)) |attr| {
            return Metadata { .inner = attr };
        } else |err| {
            return err;
        }
    }

    pub fn initPath(path: *const Path) !Metadata {
        if (fs_impl.stat(path.cptr())) |attr| {
            return Metadata { .inner = attr };
        } else |err| {
            return err;
        }
    }

    pub fn len(self: *const Self) i64 {
        return self.inner.size(); // FIX, u64
    }

    pub fn is_file(self: *const Self) bool {
        return self.file_type().is_file();
    }

    pub fn is_dir(self: *const Self) bool {
        return self.file_type().is_dir();
    }

    pub fn is_symlink(self: *const Self) bool {
        return self.file_type().is_symlink();
    }

    pub fn permissions(self: *const Self) Permissions {
        return Permissions { .inner = self.inner.perm() };
    }

    pub fn file_type(self: *const Self) FileType {
        return FileType { .inner = self.inner.file_type() };
    }

    // trait MetaDataExt (Unix-specific)
    // This appears to be living in FileAttr
    // impl MetadataExt for fs::Metadata {
    pub inline fn dev(self: *const Self) u64 { return self.inner.dev(); }
    pub inline fn ino(self: *const Self) u64 { return self.inner.ino(); }
    pub inline fn mode(self: *const Self) u32 { return self.inner.mode(); }
    pub inline fn nlink(self: *const Self) u64 { return self.inner.nlink(); }
    pub inline fn uid(self: *const Self) u32 { return self.inner.uid(); }
    pub inline fn gid(self: *const Self) u32 { return self.inner.gid(); }
    pub inline fn rdev(self: *const Self) u64 { return self.inner.rdev(); }
    pub inline fn size(self: *const Self) u64 { return self.inner.size(); }
    pub inline fn atime(self: *const Self) i64 { return self.inner.atime(); }
    pub inline fn atime_nsec(self: *const Self) i64 { return self.inner.atime_nsec(); }
    pub inline fn mtime(self: *const Self) i64 { return self.inner.mtime(); }
    pub inline fn mtime_nsec(self: *const Self) i64 { return self.inner.mtime_nsec(); }
    pub inline fn ctime(self: *const Self) i64 { return self.inner.ctime(); }
    pub inline fn ctime_nsec(self: *const Self) i64 { return self.inner.ctime_nsec(); }
    pub inline fn blksize(self: *const Self) u64 { return self.inner.blksize(); }
    pub inline fn blocks(self: *const Self) u64 { return self.inner.blocks(); }
    //}
};

test "stat.metadata.filetype.permissions" {
    // nul terminate the filename so that this can work
    var meta = try metadata(c"./fs_impl.zig");
    warn("mode={o}, size={}\n", meta.mode(), meta.len());
    var ft = meta.file_type();
    var perm = meta.permissions();

    warn("ft:{}: is_dir={}, is_file={}, is_symlink={}\n",
         @typeName(@typeOf(ft)), ft.is_dir(), ft.is_file(), ft.is_symlink());
    warn("\tis_block_device={}, is_char_device={}, is_fifo={}, is_socket={}\n",
         ft.is_block_device(), ft.is_char_device(), ft.is_fifo(), ft.is_socket());
    warn("perm:{}: readonly={}, mode={x}\n",
         @typeName(@typeOf(perm)), perm.readonly(), perm.as_inner().mode());

}

test "Dir Builder" {
    var direct_allocator = std.heap.DirectAllocator.init();
    defer direct_allocator.deinit();
    const allocator = &direct_allocator.allocator;
    var db = fs_impl.DirBuilder.new(allocator);

    try db.mkdir("__test_dir__"[0..]);
    var meta = try metadata(c"__test_dir__");
    debug.assert(meta.file_type().is_dir() == true);
}
