// -*- mode:zig; indent-tabs-mode:nil;  -*-
const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const debug = std.debug;
const warn = debug.warn;
const builtin = @import("builtin");

const posix = std.os.posix;
const PosixOpenError = std.os.PosixOpenError;

const typeOfMember = @import("helpers.zig").typeOfMember;

// Fake some Rust stuff
const stat64 = posix.Stat;

pub fn stat(p: []const u8) PosixOpenError!FileAttr {
    var stat_: posix.Stat = undefined;
    var result = std.os.linux.stat(p[0..].ptr, &stat_);
    const err = posix.getErrno(result);
    if (err != 0) {
        return switch (err) {
            posix.EFAULT => unreachable,
            posix.EINVAL => unreachable,
            posix.EACCES => PosixOpenError.AccessDenied,
            posix.EFBIG, posix.EOVERFLOW => return PosixOpenError.FileTooBig,
            posix.EISDIR => PosixOpenError.IsDir,
            posix.ELOOP => PosixOpenError.SymLinkLoop,
            posix.EMFILE => PosixOpenError.ProcessFdQuotaExceeded,
            posix.ENAMETOOLONG => PosixOpenError.NameTooLong,
            posix.ENFILE => PosixOpenError.SystemFdQuotaExceeded,
            posix.ENODEV => PosixOpenError.NoDevice,
            posix.ENOENT => PosixOpenError.PathNotFound,
            posix.ENOMEM => PosixOpenError.SystemResources,
            posix.ENOSPC => PosixOpenError.NoSpaceLeft,
            posix.ENOTDIR => PosixOpenError.NotDir,
            posix.EPERM => PosixOpenError.AccessDenied,
            posix.EEXIST => PosixOpenError.PathAlreadyExists,
            else => std.os.unexpectedErrorPosix(err),
        };
    }
    return FileAttr{.inner = stat_};
}

//const mode_t = @typeOf(stat64.mode); // does not work
pub const mode_t = @typeOf(@intToPtr(*stat64, 0).mode);

pub const FileAttr = struct {
    const Self = this;

    // Linux stat
    inner: stat64,

    fn as_inner(self: *const Self) &stat64 {
        return &self.*.inner;
    }

    // FilePermissions
    pub fn perm(self: *const Self) FilePermissions {
        return FilePermissions { .inner = self.inner.mode };
    }

    // FileType
    pub fn file_type(self: *const Self) FileType {
        return FileType { .inner = self.inner.mode };
    }

    // access functions
    pub inline fn dev(self: *const Self) u64 { return self.inner.dev; }
    pub inline fn ino(self: *const Self) u64 { return self.inner.ino; }
    pub inline fn nlink(self: *const Self) usize { return self.inner.nlink; }
    pub inline fn mode(self: *const Self) u32 { return self.inner.mode; }
    pub inline fn uid(self: *const Self) u32 { return self.inner.uid; }
    pub inline fn gid(self: *const Self) u32 { return self.inner.gid; }
    pub inline fn rdev(self: *const Self) u64 { return self.inner.rdev; }
    pub inline fn size(self: *const Self) i64 { return self.inner.size; }
    pub inline fn blksize(self: *const Self) u64 { return self.inner.blksize; }
    pub inline fn blocks(self: *const Self) u64 { return self.inner.blocks; }
    pub inline fn atime(self: *const Self) i64 { return self.inner.atim.tv_sec; }
    pub inline fn atime_nsec(self: *const Self) i64 { return self.inner.atim.tv_nsec; }
    pub inline fn mtime(self: *const Self) i64 { return self.inner.mtim.tv_sec; }
    pub inline fn mtime_nsec(self: *const Self) i64 { return self.inner.mtim.tv_nsec; }
    pub inline fn ctime(self: *const Self) i64 { return self.inner.ctim.tv_sec; }
    pub inline fn ctime_nsec(self: *const Self) i64 { return self.inner.ctim.tv_nsec; }
};

pub const FilePermissions = struct {
    const Self = this;

    inner: mode_t,

    pub fn readonly(self: *const Self) bool {
        return (self.inner & 0x3) == posix.O_RDONLY;
    }

    pub fn mode(self: *const Self) u32 {
        return self.inner;
    }

    // set_mode
    fn set_mode(self: *Self, mode_: u32) void {
        self.inner = mode_;
    }
    // from_mode
    fn from_inner(mode_: u32) FilePermissions {
        return FilePermissions { .inner = mode_ };
    }
};

pub const FileType = struct {
    const Self = this;

    inner: mode_t,

    pub fn is_file(self: *const Self) bool {
        return posix.S_ISREG(self.inner);
    }

    pub fn is_dir(self: *const Self) bool {
        return posix.S_ISDIR(self.inner);
    }

    pub fn is_symlink(self: *const Self) bool {
        return posix.S_ISLNK(self.inner);
    }

    // #[stable(feature = "file_type_ext", since = "1.5.0")]
    // impl FileTypeExt for fs::FileType {
    pub fn is_block_device(self: *const Self) bool { return posix.S_ISLNK(self.inner); }
    pub fn is_char_device(self: *const Self) bool { return posix.S_ISCHR(self.inner); }
    pub fn is_fifo(self: *const Self) bool { return posix.S_ISFIFO(self.inner); }
    pub fn is_socket(self: *const Self) bool { return posix.S_ISSOCK(self.inner); }
    // }
};
