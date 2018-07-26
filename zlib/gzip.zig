// -*- mode:zig; indent-tabs-mode:nil;  -*-
const std = @import("std");

pub const ID1: u8 = 0x1f;
pub const ID2: u8 = 0x8b;
pub const CM: u8 = 0x08;

// FLG
pub const FTEXT:     u8 = 0b00000001;
pub const FHCRC:     u8 = 0b00000010;
pub const FEXTRA:    u8 = 0b00000100;
pub const FNAME:     u8 = 0b00001000;
pub const FCOMMENT:  u8 = 0b00010000;
pub const FRESERVED: u8 = 0b11100000;
pub const FNONE:     u8 = 0b00000000;

pub const XFL_SLOW: u8 = 2;
pub const XFL_MAX = XFL_SLOW;
pub const XFL_FAST: u8 = 4;

pub const DEFAULT_HEADER: [10]u8 = []const u8 {ID1, ID2, CM, 0, 0, 0, 0, 0, 0, @enumToInt(OS.Unknown)};

inline fn typeNameOf(v: var) []const u8 {
    return @typeName(@typeOf(v));
}

pub const HeaderBuffer = [10]u8;
pub const GzipHeader = struct {
    const Self = this;

    b: HeaderBuffer,

    fn init() GzipHeader {
        return GzipHeader {.b = DEFAULT_HEADER};
    }

    fn as_slice(self: *Self) []u8 {
        return self.b[0..];
    }

    fn set_flag(self: *Self, flags: u8) void {
        // index 3 = flg
        self.b[3] |= (flags & ~FRESERVED);
    }

    fn flag_set(self: *const Self, flags: u8) bool {
        const f = flags & ~FRESERVED;
        return (self.b[3] & f) == f;
    }

    fn set_time(self: *Self, seconds: u32) void {
        // index 4, 5, 6 , 7 = mtime
        self.b[4] = @truncate(u8, seconds);
        self.b[5] = @truncate(u8, seconds >> 8);
        self.b[6] = @truncate(u8, seconds >> 16);
        self.b[7] = @truncate(u8, seconds >> 24);
    }

    fn set_xfl(self: *Self, xfl: u8) void {
        // index 8 = xfl
        self.b[8] = xfl;         // TODO: check value?
    }

    fn set_os(self: *Self, operating_system: OS) void {
        // index 9 = OS, maybe this sould come from builtin?
        self.b[9] = @enumToInt(operating_system);
    }

    // add format()?!?
    //#[derive(Debug)]
    pub fn format(
        self: *const Self,
        comptime fmt: []const u8,
        context: var,
        comptime Errors: type,
        output: fn (@typeOf(context), []const u8) Errors!void,
    ) Errors!void {
        // We ignore the actual format char for now
        if (fmt.len > 0) {
            return std.fmt.format(context, Errors, output, "{}@{x}: ",
                                  typeNameOf(self.*), @ptrToInt(self));
        } else {
            return std.fmt.format(context, Errors, output, "{}: ID1={x02}, ID2={x02}, CM={x02}, OS={}",
                                  typeNameOf(self.*), self.b[0], self.b[1], self.b[2], &(@intToEnum(OS, self.b[9])));
        }
    }
};


pub const OS = enum(u8) {
    const Self = this;

    FAT = 0, // 0 - FAT filesystem (MS-DOS, OS/2, NT/Win32)
    Amiga, // 1 - Amiga
    VMS, // 2 - VMS (or OpenVMS)
    Unix, // 3 - Unix
    VMCMS, // 4 - VM/CMS
    AtariTOS, // 5 - Atari TOS
    HPFS, // 6 - HPFS filesystem (OS/2, NT)
    Macintosh, // 7 - Macintosh
    ZSystem, //8 - Z-System
    CPM, //9 - CP/M
    TOPS20, // 10 - TOPS-20
    NTFS, // 11 - NTFS filesystem (NT)
    QDOS, // 12 - QDOS
    AcornRISCOS, // 13 - Acorn RISCOS
    Unknown = 255, //  - unknown

    pub fn format(
        self: *const Self,
        comptime fmt: []const u8,
        context: var,
        comptime Errors: type,
        output: fn (@typeOf(context), []const u8) Errors!void,
    ) Errors!void {
        // We ignore the actual format char for now
        if (fmt.len > 0) {
            return std.fmt.format(context, Errors, output, "{}.{}@{x}",
                                  typeNameOf(self.*), @ptrToInt(self), @tagName(self.*));
        } else {
            return std.fmt.format(context, Errors, output, "{}.{}",
                                  typeNameOf(self.*), @tagName(self.*));
        }
    }
};
// CRC16
// CRC32
// ISIZE

// SI1 and SI2
