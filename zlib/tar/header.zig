// -*- mode:zig; indent-tabs-mode:nil;  -*-

// From https://github.com/alexcrichton/tar-rs
// This project is licensed under either of
//
//     Apache License, Version 2.0, (LICENSE-APACHE or http://www.apache.org/licenses/LICENSE-2.0)
//     MIT license (LICENSE-MIT or http://opensource.org/licenses/MIT)
//
// at your option.

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const debug = std.debug;
const warn = debug.warn;
const builtin = @import("builtin");

// Fake some missing stuff
const fs = @import("fs.zig");

//#[cfg(any(unix, target_os = "redox"))]
//use std::os::unix::prelude::*;
//#[cfg(windows)]
//use std::os::windows::prelude::*;

// use std::borrow::Cow;
// use std::fmt;
// use std::fs;
// use std::io;
// use std::iter;
// use std::iter::repeat;
// use std::mem;
// use std::path::{Component, Path, PathBuf};
// use std::str;

// use other;
// use EntryType;
const EntryType = @import("entry_type.zig").EntryType;

const TAR_HEADER_SIZE = 512;
const TAR_GNU_MAGIC = "ustar ";
const TAR_USTART_MAGIC = "ustar\x00";

/// Representation of the header of an entry in an archive
// #[repr(C)]
// #[allow(missing_docs)]
pub const Header = extern struct {
    const Self = this;

    bytes: [TAR_HEADER_SIZE]u8,

    /// Creates a new blank GNU header.
    ///
    /// The GNU style header is the default for this library and allows various
    /// extensions such as long path names, long link names, and setting the
    /// atime/ctime metadata attributes of files.
    pub fn new_gnu() Header {
        var header = Header { .bytes = []u8 {0} ** 512 };
        //unsafe
        {
            const gnu = @ptrCast(*GnuHeader, &header); //cast_mut::<_, GnuHeader>(&mut header);
            gnu.*.magic = TAR_GNU_MAGIC;
            gnu.*.version = " \x00";
        }
        header.set_mtime(0);
        return header;
    }

    /// Creates a new blank UStar header.
    ///
    /// The UStar style header is an extension of the original archive header
    /// which enables some extra metadata along with storing a longer (but not
    /// too long) path name.
    ///
    /// UStar is also the basis used for pax archives.
    pub fn new_ustar() Header {
        var header = Header { .bytes = []u8 {0} ** 512 };
        //unsafe
        {
            const ustar = @ptrCast(*UstarHeader, &header); //cast_mut::<_, UstarHeader>(&mut header);
            ustar.magic = TAR_USTART_MAGIC;
            ustar.version = "00";
        }
        header.set_mtime(0);
        return header;
    }

    /// Creates a new blank old header.
    ///
    /// This header format is the original archive header format which all other
    /// versions are compatible with (e.g. they are a superset). This header
    /// format limits the path name limit and isn't able to contain extra
    /// metadata like atime/ctime.
    pub fn new_old() Header {
        var header = Header { .bytes = []u8 {0} ** 512 };
        header.set_mtime(0);
        return header;
    }

    fn hexdump(self: *const Self) void {
        for (self.bytes[0..]) |*b, ii| {
            warn("{x02}", b.*);
            if ((ii + 1) & 0xf == 0) {
                warn("\n");
            }
        }
    }
    
    fn is_ustar(self: *const Self) bool {
        const ustar = @ptrCast(*const UstarHeader, self);// unsafe { cast::<_, UstarHeader>(self) };
        return (mem.eql(u8, ustar.magic[0..], TAR_USTART_MAGIC)) and (mem.eql(u8, ustar.version, "00"));
    }

    fn is_gnu(self: *const Self) bool {
        const ustar = @ptrCast(*const UstarHeader, self); // unsafe { cast::<_, UstarHeader>(self) };
        return mem.eql(u8, ustar.magic, TAR_GNU_MAGIC) and mem.eql(u8, ustar.version, " \x00");
    }

    /// View this archive header as a raw "old" archive header.
    ///
    /// This view will always succeed as all archive header formats will fill
    /// out at least the fields specified in the old header format.
    pub fn as_old(self: *const Self) *const OldHeader {
        //unsafe { cast(self) }
        return @ptrCast(*const OldHeader, self);
    }

    /// Same as `as_old`, but the mutable version.
    pub fn as_old_mut(self: *Self) *OldHeader {
        return @ptrCast(*OldHeader, self);//unsafe { cast_mut(self) };
    }

    /// View this archive header as a raw UStar archive header.
    ///
    /// The UStar format is an extension to the tar archive format which enables
    /// longer pathnames and a few extra attributes such as the group and user
    /// name.
    ///
    /// This cast may not succeed as this function will test whether the
    /// magic/version fields of the UStar format have the appropriate values,
    /// returning `None` if they aren't correct.
    pub fn as_ustar(self: *const Self) ?*const UstarHeader {
        if (self.is_ustar()) {
            return @ptrCast(*const UstarHeader, self);
        } else {
            return null;
        }
    }

    /// Same as `as_ustar`, but the mutable version.
    pub fn as_ustar_mut(self: *Self) ?*UstarHeader {
        if (self.is_ustar()) {
            return @ptrCast(*UstarHeader, self);
        } else {
            return null;
        }
    }

    /// View this archive header as a raw GNU archive header.
    ///
    /// The GNU format is an extension to the tar archive format which enables
    /// longer pathnames and a few extra attributes such as the group and user
    /// name.
    ///
    /// This cast may not succeed as this function will test whether the
    /// magic/version fields of the GNU format have the appropriate values,
    /// returning `None` if they aren't correct.
    pub fn as_gnu(self: *const Self) ?*const GnuHeader {
        if (self.is_gnu()) {
            return @ptrCast(*const GnuHeader, self);
        } else {
            return null;
        }
    }

    /// Same as `as_gnu`, but the mutable version.
    pub fn as_gnu_mut(self: *Self) ?*GnuHeader {
        if (self.is_gnu()) {
            return @ptrCast(*GnuHeader, self);
        } else {
            return null;
        }
    }

    /// Treats the given byte slice as a header.
    ///
    /// Panics if the length of the passed slice is not equal to 512.
    pub fn from_byte_slice(bytes: *[]u8) *Header {
        debug.assert(bytes.len == @sizeOf(Header));
        //debug.assert(@alignOf(bytes.ptr) == @alignOf(Header));
        //unsafe { &*(bytes.as_ptr() as *const Header) }

        return @ptrCast(*Header, bytes.ptr);
    }

    /// Returns a view into this header as a byte array.
    pub fn as_bytes(self: *const Self) *const [512]u8 {
        return &self.bytes;
    }

    /// Returns a view into this header as a byte array.
    pub fn as_mut_bytes(self: *Self) *[512]u8 {
        return &self.bytes;
    }

    /// Blanket sets the metadata in this header from the metadata argument
    /// provided.
    ///
    /// This is useful for initializing a `Header` from the OS's metadata from a
    /// file. By default, this will use `HeaderMode::Complete` to include all
    /// metadata.
    pub fn set_metadata(self: *Self, meta: *fs.Metadata) void {
        self.fill_from(meta, HeaderMode.Complete);
    }

    /// Sets only the metadata relevant to the given HeaderMode in this header
    /// from the metadata argument provided.
    pub fn set_metadata_in_mode(self: *Self, meta: *fs.Metadata, mode_: HeaderMode) void {
        self.fill_from(meta, mode_);
    }

    /// Returns the size of entry's data this header represents.
    ///
    /// This is different from `Header::size` for sparse files, which have
    /// some longer `size()` but shorter `entry_size()`. The `entry_size()`
    /// listed here should be the number of bytes in the archive this header
    /// describes.
    ///
    /// May return an error if the field is corrupted.
    pub fn entry_size(self: *const Self) !u64 {
        return num_field_wrapper_from(self.*.as_old().size[0..]);
        // num_field_wrapper_from(&self.as_old().size).map_err(|err| {
        //     io::Error::new(
        //         err.kind(),
        //         format!("{} when getting size for {}", err, self.path_lossy()),
        //     )
        // })
    }

    /// Returns the file size this header represents.
    ///
    /// May return an error if the field is corrupted.
    pub fn size(self: *const Self) !u64 {
        if (self.entry_type().is_gnu_sparse()) {
            if (self.as_gnu()) |gnu| {
                return gnu.real_size();
            } else {
                return self.entry_size();
            }
            // self.as_gnu()
            //     .ok_or_else(or other("sparse header was not a gnu header"))
            //     .and_then(|h| h.real_size())
        } else {
            return self.entry_size();
        }
    }

    // /// Encodes the `size` argument into the size field of this header.
    pub fn set_size(self: *Self, size_: u64) void {
        num_field_wrapper_into(&self.as_old_mut().size[0..], size_);
    }

    /// Returns the raw path name stored in this header.
    ///
    /// This method may fail if the pathname is not valid unicode and this is
    /// called on a Windows platform.
    ///
    /// Note that this function will convert any `\` characters to directory
    /// separators.
    pub fn path(self: *Self, allocator: *Allocator) ![]u8 { //-> io::Result<Cow<Path>> {
        return bytes2path(self.path_bytes());
    }

    /// Returns the pathname stored in this header as a byte array.
    ///
    /// This function is guaranteed to succeed, but you may wish to call the
    /// `path` method to convert to a `Path`.
    ///
    /// Note that this function will convert any `\` characters to directory
    /// separators.
    //pub fn path_bytes(&self) -> Cow<[u8]> {
    pub fn path_bytes(self: *const Self, allocator: *Allocator) ![]u8 {
        if (self.as_ustar()) |ustar| {
            return ustar.path_bytes(allocator);
        } else {
            // alloc(allocator: *Allocator, n: usize, alignment: u29)
            const name = truncate(self.as_old().name[0..]);
            //Cow::Borrowed(name)
            const buf = try allocator.alloc(u8, name.len);
            errdefer allocator.free(buf);

            mem.copy(u8, buf, name);
            return buf[0..];
        }
    }

    // /// Gets the path in a "lossy" way, used for error reporting ONLY.
    // fn path_lossy(&self) -> String {
    //     String::from_utf8_lossy(&self.path_bytes()).to_string()
    // }

    // /// Sets the path name for this header.
    // ///
    // /// This function will set the pathname listed in this header, encoding it
    // /// in the appropriate format. May fail if the path is too long or if the
    // /// path specified is not unicode and this is a Windows platform.
    // pub fn set_path<P: AsRef<Path>>(&mut self, p: P) -> io::Result<()> {
    //     self._set_path(p.as_ref())
    // }

    // fn _set_path(&mut self, path: &Path) -> io::Result<()> {
    //     if let Some(ustar) = self.as_ustar_mut() {
    //         return ustar.set_path(path);
    //     }
    //     copy_path_into(&mut self.as_old_mut().name, path, false).map_err(|err| {
    //         io::Error::new(
    //             err.kind(),
    //             format!("{} when setting path for {}", err, self.path_lossy()),
    //         )
    //     })
    // }

    /// Returns the link name stored in this header, if any is found.
    ///
    /// This method may fail if the pathname is not valid unicode and this is
    /// called on a Windows platform. `Ok(None)` being returned, however,
    /// indicates that the link name was not present.
    ///
    /// Note that this function will convert any `\` characters to directory
    /// separators.
    // pub fn link_name(&self) -> io::Result<Option<Cow<Path>>> {
    //     match self.link_name_bytes() {
    //         Some(bytes) => bytes2path(bytes).map(Some),
    //         None => Ok(None),
    //     }
    // }

    /// Returns the link name stored in this header as a byte array, if any.
    ///
    /// This function is guaranteed to succeed, but you may wish to call the
    /// `link_name` method to convert to a `Path`.
    ///
    /// Note that this function will convert any `\` characters to directory
    /// separators.
    // pub fn link_name_bytes(&self) -> Option<Cow<[u8]>> {
    //     let old = self.as_old();
    //     if old.linkname[0] != 0 {
    //         Some(Cow::Borrowed(truncate(&old.linkname)))
    //     } else {
    //         None
    //     }
    // }

    /// Sets the path name for this header.
    ///
    /// This function will set the pathname listed in this header, encoding it
    /// in the appropriate format. May fail if the path is too long or if the
    /// path specified is not unicode and this is a Windows platform.
    // pub fn set_link_name<P: AsRef<Path>>(&mut self, p: P) -> io::Result<()> {
    //     self._set_link_name(p.as_ref())
    // }

    // fn _set_link_name(&mut self, path: &Path) -> io::Result<()> {
    //     copy_path_into(&mut self.as_old_mut().linkname, path, true).map_err(|err| {
    //         io::Error::new(
    //             err.kind(),
    //             format!("{} when setting link name for {}", err, self.path_lossy()),
    //         )
    //     })
    // }

    /// Returns the mode bits for this file
    ///
    /// May return an error if the field is corrupted.
    pub fn mode(self: *const Self) !u32 {
        if (octal_from(self.as_old().mode[0..])) |m| {
            return @truncate(u32, m);
        } else |err| {
            return err;
        }
        // octal_from(&self.as_old().mode)
        //     .map(|u| u as u32)
        //     .map_err(|err| {
        //         io::Error::new(
        //             err.kind(),
        //             format!("{} when getting mode for {}", err, self.path_lossy()),
        //         )
        //     })
    }

    /// Encodes the `mode` provided into this header.
    pub fn set_mode(self: *Self, mode_: u32) void {
        octal_into(&self.as_old_mut().mode[0..], mode_);
    }

    /// Returns the value of the owner's user ID field
    ///
    /// May return an error if the field is corrupted.
    pub fn uid(self: *const Self) !u64 {
        return num_field_wrapper_from(self.as_old().uid);
        // num_field_wrapper_from(&self.as_old().uid)
        //     .map(|u| u as u64)
        //     .map_err(|err| {
        //         io::Error::new(
        //             err.kind(),
        //             format!("{} when getting uid for {}", err, self.path_lossy()),
        //         )
        //     })
    }

    /// Encodes the `uid` provided into this header.
    pub fn set_uid(self: *Self, uid_: u64) void {
        num_field_wrapper_into(&self.as_old_mut().uid[0..], uid_);
    }

    /// Returns the value of the group's user ID field
    pub fn gid(self: *const Self) !u64 {
        return num_field_wrapper_from(self.as_old().gid);
        // num_field_wrapper_from(&self.as_old().gid)
        //     .map(|u| u as u64)
        //     .map_err(|err| {
        //         io::Error::new(
        //             err.kind(),
        //             format!("{} when getting gid for {}", err, self.path_lossy()),
        //         )
        //     })
    }

    /// Encodes the `gid` provided into this header.
    pub fn set_gid(self: *Self, gid_: u64) void {
        num_field_wrapper_into(&self.as_old_mut().gid[0..], gid_);
    }

    /// Returns the last modification time in Unix time format
    pub fn mtime(self: *const Self) !u64 {
        return num_field_wrapper_from(self.as_old().mtime);
        // num_field_wrapper_from(&self.as_old().mtime).map_err(|err| {
        //     io::Error::new(
        //         err.kind(),
        //         format!("{} when getting mtime for {}", err, self.path_lossy()),
        //     )
        // })
    }

    /// Encodes the `mtime` provided into this header.
    ///
    /// Note that this time is typically a number of seconds passed since
    /// January 1, 1970.
    // CHECK: error: redefinition of 'mtime'
    pub fn set_mtime(self: *Self, mtime_: u64) void {
        return num_field_wrapper_into(&self.as_old_mut().mtime[0..], mtime_);
    }

    /// Return the user name of the owner of this file.
    ///
    /// A return value of `Ok(Some(..))` indicates that the user name was
    /// present and was valid utf-8, `Ok(None)` indicates that the user name is
    /// not present in this archive format, and `Err` indicates that the user
    /// name was present but was not valid utf-8.
    pub fn username(self: *const Self) ?[]const u8 { // -> Result<Option<&str>, str::Utf8Error> {
        if (self.username_bytes()) |bytes| {
            return bytes;       // validate utf8
        } else {
            return null;
        }
        // switch (self.username_bytes()) {
        //     null => null,
        //     else => |bytes| return bytes,// str::from_utf8(bytes).map(Some),
        // }
    }

    /// Returns the user name of the owner of this file, if present.
    ///
    /// A return value of `None` indicates that the user name is not present in
    /// this header format.
    pub fn username_bytes(self: *const Self) ?[]const u8 {
        if (self.as_ustar()) |ustar| {
            return ustar.username_bytes();
        } else if (self.as_gnu()) |gnu| {
            return gnu.username_bytes();
        } else {
            return null;
        }
    }

    /// Sets the username inside this header.
    ///
    /// This function will return an error if this header format cannot encode a
    /// user name or the name is too long.
    pub fn set_username(self: *Self, name: []const u8) !void {
        if (self.as_ustar_mut()) |ustar| {
            return ustar.set_username(name);
        } else if (self.as_gnu_mut()) |gnu| {
            return gnu.set_username(name);
        } else {
            //Err(other("not a ustar or gnu archive, cannot set username"))
            return error.NotUstarNorGnu;
        }
    }

    /// Return the group name of the owner of this file.
    ///
    /// A return value of `Ok(Some(..))` indicates that the group name was
    /// present and was valid utf-8, `Ok(None)` indicates that the group name is
    /// not present in this archive format, and `Err` indicates that the group
    /// name was present but was not valid utf-8.
    pub fn groupname(self: *const Self) ?[]const u8 {
        if (self.groupname_bytes()) |bytes| {
            return bytes;       // validate utf8
        } else {
            return null;
        }
        // match self.groupname_bytes() {
        //     Some(bytes) => str::from_utf8(bytes).map(Some),
        //     None => Ok(None),
        // }
    }

    /// Returns the group name of the owner of this file, if present.
    ///
    /// A return value of `None` indicates that the group name is not present in
    /// this header format.
    pub fn groupname_bytes(self: *const Self) ?[]const u8 {
        if (self.as_ustar()) |ustar| {
            return ustar.groupname_bytes();
        } else if (self.as_gnu()) |gnu| {
            return gnu.groupname_bytes();
        } else {
            return null;
        }
    }

    /// Sets the group name inside this header.
    ///
    /// This function will return an error if this header format cannot encode a
    /// group name or the name is too long.
    pub fn set_groupname(self: *Self, name: []const u8) !void {
        if (self.as_ustar_mut()) |ustar| {
            return ustar.set_groupname(name);
        } else if (self.as_gnu_mut()) |gnu| {
            return gnu.set_groupname(name);
        } else {
            //Err(other("not a ustar or gnu archive, cannot set groupname"))
            return error.NotUstarNorGnu;
        }
    }

    /// Returns the device major number, if present.
    ///
    /// This field may not be present in all archives, and it may not be
    /// correctly formed in all archives. `Ok(Some(..))` means it was present
    /// and correctly decoded, `Ok(None)` indicates that this header format does
    /// not include the device major number, and `Err` indicates that it was
    /// present and failed to decode.
    pub fn device_major(self: *const Self) !?u32 {
        if (self.as_ustar()) |ustar| {
            if (ustar.device_major()) |maj| {
                return maj;
            } else |err| {
                return err;
            }
        } else if (self.as_gnu()) |gnu| {
            if (gnu.device_major()) |maj| {
                return maj;
            } else |err| {
                return err;
            }
        } else {
            return null;
        }
    }

    /// Encodes the value `major` into the dev_major field of this header.
    ///
    /// This function will return an error if this header format cannot encode a
    /// major device number.
    pub fn set_device_major(self: *Self, major: u32) !void {
        if (self.as_ustar_mut()) |ustar| {
            return ustar.set_device_major(major);
        }
        if (self.as_gnu_mut()) |gnu| {
            gnu.set_device_major(major);
        } else {
            //Err(other("not a ustar or gnu archive, cannot set dev_major"))
            return error.NotUstarNorGnu;
        }
    }

    /// Returns the device minor number, if present.
    ///
    /// This field may not be present in all archives, and it may not be
    /// correctly formed in all archives. `Ok(Some(..))` means it was present
    /// and correctly decoded, `Ok(None)` indicates that this header format does
    /// not include the device minor number, and `Err` indicates that it was
    /// present and failed to decode.
    pub fn device_minor(self: *const Self) !?u32 {
        if (self.as_ustar()) |ustar| {
            if (ustar.device_minor()) |minor| {
                return minor;
            } else |err| {
                return err;
            }
        } else if (self.as_gnu()) |gnu| {
            if (gnu.device_minor()) |minor| {
                return minor;
            } else |err| {
                return err;
            }
        } else {
            return null;
        }
    }

    /// Encodes the value `minor` into the dev_minor field of this header.
    ///
    /// This function will return an error if this header format cannot encode a
    /// minor device number.
    pub fn set_device_minor(self: *self, minor: u32) !void {
        if (self.as_ustar_mut()) |ustar| {
            return ustar.set_device_minor(minor);
        }
        if (self.as_gnu_mut()) |gnu| {
            return gnu.set_device_minor(minor);
        } else {
            //Err(other("not a ustar or gnu archive, cannot set dev_minor"))
            return error.NotUstarNorGnu;
        }
    }

    /// Returns the type of file described by this header.
    pub fn entry_type(self: *const Self) EntryType {
        return EntryType.new(self.as_old().linkflag[0]);
    }

    /// Sets the type of file that will be described by this header.
    pub fn set_entry_type(self: *Self, ty: EntryType) void {
        self.as_old_mut().linkflag[0] = ty.as_byte();
    }

    /// Returns the checksum field of this header.
    ///
    /// May return an error if the field is corrupted.
    pub fn cksum(self: *const Self) !u32 {
        if (octal_from(self.*.as_old().*.cksum[0..])) |ck| {
            return @truncate(u32, ck);
        } else |err| {
            return err;
        }
        // octal_from(&self.as_old().cksum)
        //     .map(|u| u as u32)
        //     .map_err(|err| {
        //         io::Error::new(
        //             err.kind(),
        //             format!("{} when getting cksum for {}", err, self.path_lossy()),
        //         )
        //     })
    }

    /// Sets the checksum field of this header based on the current fields in
    /// this header.
    pub fn set_cksum(self: *Self) void {
        const cksum = self.calculate_cksum();
        octal_into(&self.as_old_mut().cksum[0..], cksum);
    }

    // fn calculate_cksum(&self) -> u32 {
    //     let old = self.as_old();
    //     let start = old as *const _ as usize;
    //     let cksum_start = old.cksum.as_ptr() as *const _ as usize;
    //     let offset = cksum_start - start;
    //     let len = old.cksum.len();
    //     self.bytes[0..offset]
    //         .iter()
    //         .chain(iter::repeat(&b' ').take(len))
    //         .chain(&self.bytes[offset + len..])
    //         .fold(0, |a, b| a + (*b as u32))
    // }
    fn calculate_cksum(self: *const Self) u32 {
        const oldhdr = self.as_old();
        const cksumofs = @offsetOf(@typeOf(oldhdr.*), "cksum");
        const cksumsize = @sizeOf(@typeOf(oldhdr.cksum));
        var ck: u32 = 0x20 * cksumsize; // cksum of blank cksum
        for (self.bytes[0..cksumofs]) |b| {
            ck += b;
        }
        return for (self.bytes[cksumofs+cksumsize..]) |b| {
            ck += b;
        } else ck;

        //return ck;
    }

    fn fill_from(self: *Self, meta: *fs.Metadata, mode_: HeaderMode) void {
        self.fill_platform_from(meta, mode_);
        // Set size of directories to zero
        self.set_size(if (meta.is_dir() or meta.is_symlink()) 0 else @bitCast(u64, meta.len()));
        if (self.as_ustar_mut()) |ustar| {
            ustar.set_device_major(0);
            ustar.set_device_minor(0);
        }
        if (self.as_gnu_mut()) |gnu| {
            gnu.set_device_major(0);
            gnu.set_device_minor(0);
        }
    }

    // #[cfg(any(unix, target_os = "redox"))]
    fn fill_platform_from(self: *Self, meta: *fs.Metadata, mode_: HeaderMode) void {
        switch (mode_) {
            HeaderMode.Complete => {
                self.set_mtime(@bitCast(u64, meta.mtime()));
                self.set_uid(meta.uid());
                self.set_gid(meta.gid());
                self.set_mode(meta.mode());
            },
            HeaderMode.Deterministic => {
                self.set_mtime(0);
                self.set_uid(0);
                self.set_gid(0);
                // Use a default umask value, but propagate the (user) execute bit.
                const fs_mode: u32 = if (meta.is_dir() or (0o100 & meta.mode() == 0o100)) u32(0o755) else u32(0o644);
                self.set_mode(fs_mode);
            },
            HeaderMode.__Nonexhaustive => unreachable,
        }
        // Note that if we are a GNU header we *could* set atime/ctime, except
        // the `tar` utility doesn't do that by default and it causes problems
        // with 7-zip [1].
        //
        // It's always possible to fill them out manually, so we just don't fill
        // it out automatically here.
        //
        // [1]: https://github.com/alexcrichton/tar-rs/issues/70

        // TODO: need to bind more file types
        // self.set_entry_type(entry_type(meta.mode()));

        // TODO: Hmm, local functions of some sort...
        //     #[cfg(not(target_os = "redox"))]
        //     fn entry_type(mode: u32) -> EntryType {
        //         use libc;
        //         match mode as libc::mode_t & libc::S_IFMT {
        //             libc::S_IFREG => EntryType::file(),
        //             libc::S_IFLNK => EntryType::symlink(),
        //             libc::S_IFCHR => EntryType::character_special(),
        //             libc::S_IFBLK => EntryType::block_special(),
        //             libc::S_IFDIR => EntryType::dir(),
        //             libc::S_IFIFO => EntryType::fifo(),
        //             _ => EntryType::new(b' '),
        //         }
        //     }

        //     #[cfg(target_os = "redox")]
        //     fn entry_type(mode: u32) -> EntryType {
        //         use syscall;
        //         match mode as u16 & syscall::MODE_TYPE {
        //             syscall::MODE_FILE => EntryType::file(),
        //             syscall::MODE_SYMLINK => EntryType::symlink(),
        //             syscall::MODE_DIR => EntryType::dir(),
        //             _ => EntryType::new(b' '),
        //         }
        //     }
    }

    // #[cfg(windows)]
    // fn fill_platform_from(&mut self, meta: &fs::Metadata, mode: HeaderMode) {
    //     // There's no concept of a file mode on windows, so do a best approximation here.
    //     match mode {
    //         HeaderMode::Complete => {
    //             self.set_uid(0);
    //             self.set_gid(0);
    //             // The dates listed in tarballs are always seconds relative to
    //             // January 1, 1970. On Windows, however, the timestamps are returned as
    //             // dates relative to January 1, 1601 (in 100ns intervals), so we need to
    //             // add in some offset for those dates.
    //             let mtime = (meta.last_write_time() / (1_000_000_000 / 100)) - 11644473600;
    //             self.set_mtime(mtime);
    //             let fs_mode = {
    //                 const FILE_ATTRIBUTE_READONLY: u32 = 0x00000001;
    //                 let readonly = meta.file_attributes() & FILE_ATTRIBUTE_READONLY;
    //                 match (meta.is_dir(), readonly != 0) {
    //                     (true, false) => 0o755,
    //                     (true, true) => 0o555,
    //                     (false, false) => 0o644,
    //                     (false, true) => 0o444,
    //                 }
    //             };
    //             self.set_mode(fs_mode);
    //         }
    //         HeaderMode::Deterministic => {
    //             self.set_uid(0);
    //             self.set_gid(0);
    //             self.set_mtime(0);
    //             let fs_mode = if meta.is_dir() { 0o755 } else { 0o644 };
    //             self.set_mode(fs_mode);
    //         }
    //         HeaderMode::__Nonexhaustive => panic!(),
    //     }

    //     let ft = meta.file_type();
    //     self.set_entry_type(if ft.is_dir() {
    //         EntryType::dir()
    //     } else if ft.is_file() {
    //         EntryType::file()
    //     } else if ft.is_symlink() {
    //         EntryType::symlink()
    //     } else {
    //         EntryType::new(b' ')
    //     });
    // }

    // fn debug_fields(&self, b: &mut fmt::DebugStruct) {
    //     if let Ok(entry_size) = self.entry_size() {
    //         b.field("entry_size", &entry_size);
    //     }
    //     if let Ok(size) = self.size() {
    //         b.field("size", &size);
    //     }
    //     if let Ok(path) = self.path() {
    //         b.field("path", &path);
    //     }
    //     if let Ok(link_name) = self.link_name() {
    //         b.field("link_name", &link_name);
    //     }
    //     if let Ok(mode) = self.mode() {
    //         b.field("mode", &DebugAsOctal(mode));
    //     }
    //     if let Ok(uid) = self.uid() {
    //         b.field("uid", &uid);
    //     }
    //     if let Ok(gid) = self.gid() {
    //         b.field("gid", &gid);
    //     }
    //     if let Ok(mtime) = self.mtime() {
    //         b.field("mtime", &mtime);
    //     }
    //     if let Ok(username) = self.username() {
    //         b.field("username", &username);
    //     }
    //     if let Ok(groupname) = self.groupname() {
    //         b.field("groupname", &groupname);
    //     }
    //     if let Ok(device_major) = self.device_major() {
    //         b.field("device_major", &device_major);
    //     }
    //     if let Ok(device_minor) = self.device_minor() {
    //         b.field("device_minor", &device_minor);
    //     }
    //     if let Ok(cksum) = self.cksum() {
    //         b.field("cksum", &cksum);
    //         b.field("cksum_valid", &(cksum == self.calculate_cksum()));
    //     }
    // }

    fn clone(self: *Self) Header {
        return Header { .bytes = self.bytes };
        //mem.copy(u8, header.bytes[0..], self.bytes);
        //return header;
    }

    // impl Clone for Header {
    //     fn clone(&self) -> Header {
    //         Header { bytes: self.bytes }
    //     }
    // }

    // impl fmt::Debug for Header {
    //     fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
    //         if let Some(me) = self.as_ustar() {
    //             me.fmt(f)
    //         } else if let Some(me) = self.as_gnu() {
    //             me.fmt(f)
    //         } else {
    //             self.as_old().fmt(f)
    //         }
    //     }
    // }
};


test "Header.Old" {
    var header = Header.new_old();
    debug.assert(@sizeOf(@typeOf(header)) == TAR_HEADER_SIZE);
    debug.assert(header.is_gnu() == false);
    debug.assert(header.is_ustar() == false);
}

test "Header.Gnu" {
    var header = Header.new_gnu();
    debug.assert(@sizeOf(@typeOf(header)) == TAR_HEADER_SIZE);
    debug.assert(header.is_gnu() == true);
    debug.assert(header.is_ustar() == false);
}

test "Header.Ustar" {
    var header = Header.new_ustar();
    debug.assert(@sizeOf(@typeOf(header)) == TAR_HEADER_SIZE);
    debug.assert(header.is_gnu() == false);
    debug.assert(header.is_ustar() == true);
}

test "Header.Gnu.username" {
    var header = Header.new_gnu();
    warn("username_bytes='{}'\n", header.username_bytes());
    warn("username='{}'\n", header.username());
    if (header.username_bytes()) |bytes| {
        warn("bytes.len={}\n", bytes.len);
        debug.assert(mem.eql(u8, bytes, ""));
    } else {
        debug.assert(false);
    }
    //header.hexdump();
    try header.set_username(("Bob The Builder")[0..]);
    //header.hexdump();
    warn("username_bytes='{}'\n", header.username_bytes());
    if (header.username_bytes()) |bytes| {
        warn("bytes.len={}\n", bytes.len);
        debug.assert(mem.eql(u8, bytes, "Bob The Builder"));
    } else {
        debug.assert(false);
    }
}

test "Header.Gnu.groupname" {
    var header = Header.new_gnu();
    warn("grpname_bytes='{}'\n", header.groupname_bytes());
    warn("grpname='{}'\n", header.groupname());
    if (header.groupname_bytes()) |bytes| {
        warn("bytes.len={}\n", bytes.len);
        debug.assert(mem.eql(u8, bytes, ""));
    } else {
        debug.assert(false);
    }
    //header.hexdump();
    try header.set_groupname(("wheel")[0..]);
    //header.hexdump();
    warn("grpname_bytes='{}'\n", header.groupname_bytes());
    if (header.groupname_bytes()) |bytes| {
        warn("bytes.len={}\n", bytes.len);
        debug.assert(mem.eql(u8, bytes, "wheel"));
    } else {
        debug.assert(false);
    }
}

test "Header.Ustar.username" {
    var header = Header.new_ustar();
    warn("username_bytes='{}'\n", header.username_bytes());
    warn("username='{}'\n", header.username());
    // may the truncate was meant to set the length to excludes \x00 bytes?
    if (header.username_bytes()) |bytes| {
        debug.assert(mem.eql(u8, bytes, ""));
    } else {
        debug.assert(false);
    }
    try header.set_username(("Bob The Builder")[0..]);
    warn("username_bytes='{}'\n", header.username_bytes());
    if (header.username_bytes()) |bytes| {
        warn("bytes.len={}\n", bytes.len);
        debug.assert(mem.eql(u8, bytes, "Bob The Builder"));
    } else {
        debug.assert(false);
    }
}

test "Header.as_bytes" {
    var header = Header.new_old();
    var bytes = header.as_bytes();
    debug.assert(bytes.len == TAR_HEADER_SIZE);
}

test "Header.from_byte_slice" {
    var bytes = "friend.zig\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x000000644\x000001750\x000001750\x000000" ++
        "0172503\x0013326647763\x00012422\x00 0\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00ustar  \x00hacker\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00hacker\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00";

    var header = Header.from_byte_slice(&bytes[0..]);
    var direct_allocator = std.heap.DirectAllocator.init();
    defer direct_allocator.deinit();

    const allocator = &direct_allocator.allocator;
    // we have modified the bytes so the cksum is slightly different
    const cksum = header.calculate_cksum();
    warn("username='{}', groupname='{}'\n", header.username(), header.groupname());
    warn("gnu={}, ustar={}, cksum={}/{}\n", header.is_gnu(), header.is_ustar(), header.cksum(), cksum);
    // deriveDebug for pretty enum printing?!?
    warn("entry_size={}, size={}, entry_type={}\n", header.entry_size(), header.size(), @enumToInt(header.entry_type()));
    warn("mtime={}, uid={}, gid={}, mode={o}\n", header.mtime(), header.uid(), header.gid(), header.mode());
    warn("major={}, minor={}\n", header.device_major(), header.device_minor());
    if (header.path_bytes(allocator)) |path| {
        defer allocator.free(path);
        warn("path_bytes={}\n", path);
    } else |err| {
        warn("oh crap, {}\n", err);
    }

    var oheader = header.clone();
    var obytes = oheader.as_bytes();
    // we should not hve modified anything
    debug.assert(mem.eql(u8, bytes, obytes));

    try oheader.set_device_major(1);
    warn("major={}, minor={}\n", oheader.device_major(), oheader.device_minor());
}

test "Header.from_byte_slice.pax" {
    var bytes = "./PaxHeaders.15229/header.zig\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x000000644\x000000000\x000000000\x000000" ++
        "0000132\x0013326713043\x00012717\x00 x\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00ustar\x0000\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
        "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00";

    var header = Header.from_byte_slice(&bytes[0..]);
    var direct_allocator = std.heap.DirectAllocator.init();
    defer direct_allocator.deinit();

    const allocator = &direct_allocator.allocator;
    // we have modified the bytes so the cksum is slightly different
    const cksum = header.calculate_cksum();
    warn("username='{}', groupname='{}'\n", header.username(), header.groupname());
    warn("gnu={}, ustar={}, cksum={}/{}\n", header.is_gnu(), header.is_ustar(), header.cksum(), cksum);
    // deriveDebug for pretty enum printing?!?
    warn("entry_size={}, size={}, entry_type={}\n", header.entry_size(), header.size(), @enumToInt(header.entry_type()));
    warn("mtime={}, uid={}, gid={}, mode={o}\n", header.mtime(), header.uid(), header.gid(), header.mode());
    warn("major={}, minor={}\n", header.device_major(), header.device_minor());
    if (header.path_bytes(allocator)) |path| {
        defer allocator.free(path);
        warn("path_bytes={}\n", path);
    } else |err| {
        warn("oh crap, {}\n", err);
    }

    var oheader = header.clone();
    var obytes = oheader.as_bytes();
    // we should not hve modified anything
    debug.assert(mem.eql(u8, bytes, obytes));

    try oheader.set_device_major(1);
    warn("major={}, minor={}\n", oheader.device_major(), oheader.device_minor());
    var meta = try fs.metadata("./header.zig");
    oheader.fill_from(&meta, HeaderMode.Complete);
    warn("major={}, minor={}\n", oheader.device_major(), oheader.device_minor());
    oheader.hexdump();
}

/// Declares the information that should be included when filling a Header
/// from filesystem metadata.
//#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub const HeaderMode = enum {
    /// All supported metadata, including mod/access times and ownership will
    /// be included.
    Complete,

    /// Only metadata that is directly relevant to the identity of a file will
    /// be included. In particular, ownership and mod/access times are excluded.
    Deterministic,

    //#[doc(hidden)]
    __Nonexhaustive,
};

/// Representation of the header of an entry in an archive
//#[repr(C)]
//#[allow(missing_docs)]
pub const OldHeader = extern struct {
    const Self = this;

    pub name: [100]u8,
    pub mode: [8]u8,
    pub uid: [8]u8,
    pub gid: [8]u8,
    pub size: [12]u8,
    pub mtime: [12]u8,
    pub cksum: [8]u8,
    pub linkflag: [1]u8,
    pub linkname: [100]u8,
    pub pad: [255]u8,

    /// Views this as a normal `Header`
    pub fn as_header(self: *const Self) *const Header {
        return @ptrCast(*const Header, self);
    }

    /// Views this as a normal `Header`
    pub fn as_header_mut(self: *Self) *Header {
        return @ptrCast(*Header, self);
    }

    // fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
    //     let mut f = f.debug_struct("OldHeader");
    //     self.as_header().debug_fields(&mut f);
    //     f.finish()
    // }

};

/// Representation of the header of an entry in an archive
//#[repr(C)]
//#[allow(missing_docs)]
pub const UstarHeader = extern struct {
    const Self = this;

    pub name: [100]u8,
    pub mode: [8]u8,
    pub uid: [8]u8,
    pub gid: [8]u8,
    pub size: [12]u8,
    pub mtime: [12]u8,
    pub cksum: [8]u8,
    pub typeflag: [1]u8,
    pub linkname: [100]u8,

    // UStar format
    pub magic: [6]u8,
    pub version: [2]u8,
    pub uname: [32]u8,
    pub gname: [32]u8,
    pub dev_major: [8]u8,
    pub dev_minor: [8]u8,
    pub prefix: [155]u8,
    pub pad: [12]u8,

    /// See `Header.username_bytes`
    pub fn username_bytes(self: *const Self) []const u8 {
        return truncate(self.uname[0..]);
    }

    /// See `Header.set_username`
    pub fn set_username(self: *Self, name: []const u8) !void {
        //warn("{}: set_username '{}'\n", self, name);
        debug.assert(name.len <= self.*.uname.len);
        if (name.len > @sizeOf(@typeOf(self.*.uname))) {
            return error.UsernameTooLong;
        }
        for (name) |b, ii| {
            self.*.uname[ii] = b;
            //warn("uname[{}]={x02} {x02}\n", ii, self.*.uname[ii], b);
        }
    }

    // CHECK: Probably some copy on write mechanism...
    //pub fn path_bytes(&self) -> Cow<[u8]> {
    /// See `Header.path_bytes`
    pub fn path_bytes(self: *const Self, allocator: *Allocator) ![]u8 {
        if ((self.prefix[0] == 0) and (!contains(self.name, '\\'))) {
            //Cow::Borrowed(truncate(&self.name))
            const name = truncate(self.name[0..]);
            const buf = try allocator.alloc(u8, name.len);
            errdefer allocator.free(buf);

            mem.copy(u8, buf, name);
            return buf[0..];
        } else {
            //             let mut bytes = Vec::new();
            //             let prefix = truncate(&self.prefix);
            //             if prefix.len() > 0 {
            //                 bytes.extend_from_slice(prefix);
            //                 bytes.push(b'/');
            //             }
            //             bytes.extend_from_slice(truncate(&self.name));
            //             Cow::Owned(bytes)
            return error.NotImplemented;
        }
    }

//     /// Gets the path in a "lossy" way, used for error reporting ONLY.
//     fn path_lossy(&self) -> String {
//         String::from_utf8_lossy(&self.path_bytes()).to_string()
//     }

//     /// See `Header::set_path`
//     pub fn set_path<P: AsRef<Path>>(&mut self, p: P) -> io::Result<()> {
//         self._set_path(p.as_ref())
//     }

//     fn _set_path(&mut self, path: &Path) -> io::Result<()> {
//         // This can probably be optimized quite a bit more, but for now just do
//         // something that's relatively easy and readable.
//         //
//         // First up, if the path fits within `self.name` then we just shove it
//         // in there. If not then we try to split it between some existing path
//         // components where it can fit in name/prefix. To do that we peel off
//         // enough until the path fits in `prefix`, then we try to put both
//         // halves into their destination.
//         let bytes = path2bytes(path)?;
//         let (maxnamelen, maxprefixlen) = (self.name.len(), self.prefix.len());
//         if bytes.len() <= maxnamelen {
//             copy_path_into(&mut self.name, path, false).map_err(|err| {
//                 io::Error::new(
//                     err.kind(),
//                     format!("{} when setting path for {}", err, self.path_lossy()),
//                 )
//             })?;
//         } else {
//             let mut prefix = path;
//             let mut prefixlen;
//             loop {
//                 match prefix.parent() {
//                     Some(parent) => prefix = parent,
//                     None => {
//                         return Err(other(&format!(
//                             "path cannot be split to be inserted into archive: {}",
//                             path.display()
//                         )))
//                     }
//                 }
//                 prefixlen = path2bytes(prefix)?.len();
//                 if prefixlen <= maxprefixlen {
//                     break;
//                 }
//             }
//             copy_path_into(&mut self.prefix, prefix, false).map_err(|err| {
//                 io::Error::new(
//                     err.kind(),
//                     format!("{} when setting path for {}", err, self.path_lossy()),
//                 )
//             })?;
//             let path = bytes2path(Cow::Borrowed(&bytes[prefixlen + 1..]))?;
//             copy_path_into(&mut self.name, &path, false).map_err(|err| {
//                 io::Error::new(
//                     err.kind(),
//                     format!("{} when setting path for {}", err, self.path_lossy()),
//                 )
//             })?;
//         }
//         Ok(())
//     }

    /// See `Header.groupname_bytes`
    pub fn groupname_bytes(self: *const Self) []const u8 {
        return truncate(self.gname[0..]);
    }

    //     /// See `Header::set_groupname`
    //     pub fn set_groupname(&mut self, name: &str) -> io::Result<()> {
    //         copy_into(&mut self.gname, name.as_bytes()).map_err(|err| {
    //             io::Error::new(
    //                 err.kind(),
    //                 format!("{} when setting groupname for {}", err, self.path_lossy()),
    //             )
    //         })
    //     }
    pub fn set_groupname(self: *Self, name: []const u8) !void {
        debug.assert(name.len <= self.*.gname.len);
        if (name.len > @sizeOf(@typeOf(self.*.gname))) {
            return error.GroupnameTooLong;
        }
        for (name) |b, ii| {
            self.*.gname[ii] = b;
        }
        // copy_into(&mut self.uname, name.as_bytes()).map_err(|err| {
        //     io::Error::new(
        //         err.kind(),
        //         format!(
        //             "{} when setting username for {}",
        //             err,
        //             self.fullname_lossy()
        //         ),
        //     )
        // })
    }


    /// See `Header.device_major`
    pub fn device_major(self: *const Self) !u32 {
        if (octal_from(self.dev_major[0..])) |maj| {
            return @truncate(u32, maj);
        } else |err| {
            return err;
        }
        // octal_from(&self.dev_major)
        //     .map(|u| u as u32)
        //     .map_err(|err| {
        //         io::Error::new(
        //             err.kind(),
        //             format!(
        //                 "{} when getting device_major for {}",
        //                 err,
        //                 self.path_lossy()
        //             ),
        //         )
        //     })
    }

    /// See `Header::set_device_major`
    pub fn set_device_major(self: *Self, major: u32) void {
        octal_into(&self.dev_major[0..], major);
    }

    /// See `Header::device_minor`
    pub fn device_minor(self: *const Self) !?u32 {
        if (octal_from(self.dev_minor[0..])) |minor| {
            return @truncate(u32, minor);
        } else |err| {
            return err;
        }
        // octal_from(&self.dev_minor)
        //     .map(|u| u as u32)
        //     .map_err(|err| {
        //         io::Error::new(
        //             err.kind(),
        //             format!(
        //                 "{} when getting device_minor for {}",
        //                 err,
        //                 self.path_lossy()
        //             ),
        //         )
        //     })
    }

    /// See `Header::set_device_minor`
    pub fn set_device_minor(self: *Self, minor: u32) void {
        octal_into(&self.dev_minor[0..], minor);
    }

    /// Views this as a normal `Header`
    pub fn as_header(self: *const Self) *const Header {
        return @ptrCast(*const Header, self); //unsafe { cast(self) }
    }

    /// Views this as a normal `Header`
    pub fn as_header_mut(self: *Self) *Header {
        return @ptrCast(*Header, self); //unsafe { cast(self) }
    }

// impl fmt::Debug for UstarHeader {
//     fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
//         let mut f = f.debug_struct("UstarHeader");
//         self.as_header().debug_fields(&mut f);
//         f.finish()
//     }
// }
};

/// Representation of the header of an entry in an archive
//#[repr(C)]
//#[allow(missing_docs)]
pub const GnuHeader = extern struct {
    const Self = this;

    pub name: [100]u8,
    pub mode: [8]u8,
    pub uid: [8]u8,
    pub gid: [8]u8,
    pub size: [12]u8,
    pub mtime: [12]u8,
    pub cksum: [8]u8,
    pub typeflag: [1]u8,
    pub linkname: [100]u8,

    // GNU format
    pub magic: [6]u8,
    pub version: [2]u8,
    pub uname: [32]u8,
    pub gname: [32]u8,
    pub dev_major: [8]u8,
    pub dev_minor: [8]u8,
    pub atime: [12]u8,
    pub ctime: [12]u8,
    pub offset: [12]u8,
    pub longnames: [4]u8,
    pub unused: [1]u8,
    pub sparse: [4]GnuSparseHeader,
    pub isextended: [1]u8,
    pub realsize: [12]u8,
    pub pad: [17]u8,

    /// See `Header.username_bytes`
    pub fn username_bytes(self: *const Self) []const u8 {
        return truncate(self.*.uname[0..]);
    }

    /// See `Header.set_username`
    pub fn set_username(self: *Self, name: []const u8) !void {
        warn("{}: set_username '{}'\n", self, name);
        debug.assert(name.len <= self.*.uname.len);
        if (name.len > @sizeOf(@typeOf(self.*.uname))) {
            return error.UsernameTooLong;
        }
        return copy_into(&self.uname, name);
        // copy_into(&mut self.uname, name.as_bytes()).map_err(|err| {
        //     io::Error::new(
        //         err.kind(),
        //         format!(
        //             "{} when setting username for {}",
        //             err,
        //             self.fullname_lossy()
        //         ),
        //     )
        // })
    }

    // /// Gets the fullname (group:user) in a "lossy" way, used for error reporting ONLY.
    // fn fullname_lossy(&self) -> String {
    //     format!(
    //         "{}:{}",
    //         String::from_utf8_lossy(&self.groupname_bytes()),
    //         String::from_utf8_lossy(&self.username_bytes()),
    //     )
    // }

    /// See `Header.groupname_bytes`
    pub fn groupname_bytes(self: *const Self) []const u8 {
        return truncate(self.gname[0..]);
    }

    /// See `Header.set_groupname`
    pub fn set_groupname(self: *Self, name: []const u8) !void {
        debug.assert(name.len <= self.*.gname.len);
        if (name.len > @sizeOf(@typeOf(self.*.gname))) {
            return error.GroupnameTooLong;
        }
        return copy_into(&self.*.gname, name);
    }

    /// See `Header::device_major`
    pub fn device_major(self: *const Self) !u32 {
        if (octal_from(self.dev_major[0..])) |major| {
            return @truncate(u32, major);
        } else |err| {
            return err;
        }
        // octal_from(&self.dev_major)
        //     .map(|u| u as u32)
        //     .map_err(|err| {
        //         io::Error::new(
        //             err.kind(),
        //             format!(
        //                 "{} when getting device_major for {}",
        //                 err,
        //                 self.fullname_lossy()
        //             ),
        //         )
        //     })
    }

    /// See `Header::set_device_major`
    pub fn set_device_major(self: *Self, major: u32) void {
        octal_into(&self.dev_major[0..], major);
    }

    /// See `Header.device_minor`
    pub fn device_minor(self: *const Self) !u32 {
        if (octal_from(self.dev_minor[0..])) |minor| {
            return @truncate(u32, minor);
        } else |err| {
            return err;
        }
        // octal_from(&self.dev_minor)
        //     .map(|u| u as u32)
        //     .map_err(|err| {
        //         io::Error::new(
        //             err.kind(),
        //             format!(
        //                 "{} when getting device_minor for {}",
        //                 err,
        //                 self.fullname_lossy()
        //             ),
        //         )
        //     })
    }

    /// See `Header::set_device_minor`
    pub fn set_device_minor(self: *Self, minor: u32) void {
        octal_into(&self.dev_minor[0..], minor);
    }

    /// Returns the last modification time in Unix time format
    pub fn atime(self: *const Self) !u64 {
        return num_field_wrapper_from(self.atime);
        // num_field_wrapper_from(&self.atime).map_err(|err| {
        //     io::Error::new(
        //         err.kind(),
        //         format!("{} when getting atime for {}", err, self.fullname_lossy()),
        //     )
        // })
    }

    /// Encodes the `atime` provided into this header.
    ///
    /// Note that this time is typically a number of seconds passed since
    /// January 1, 1970.
    pub fn set_atime(self: *Self, atime_: u64) void {
        num_field_wrapper_into(&self.atime[0..], atime_);
    }

    /// Returns the last modification time in Unix time format
    pub fn ctime(self: *const Self) !u64 {
        return num_field_wrapper_from(self.ctime);
        // num_field_wrapper_from(&self.ctime).map_err(|err| {
        //     io::Error::new(
        //         err.kind(),
        //         format!("{} when getting ctime for {}", err, self.fullname_lossy()),
        //     )
        // })
    }

    /// Encodes the `ctime` provided into this header.
    ///
    /// Note that this time is typically a number of seconds passed since
    /// January 1, 1970.
    pub fn set_ctime(self: *Self, ctime_: u64) void {
        num_field_wrapper_into(&self.ctime[0..], ctime_);
    }

    /// Returns the "real size" of the file this header represents.
    ///
    /// This is applicable for sparse files where the returned size here is the
    /// size of the entire file after the sparse regions have been filled in.
    pub fn real_size(self: *const Self) !u64 {
        return octal_from(self.realsize);
        // octal_from(&self.realsize).map_err(|err| {
        //     io::Error::new(
        //         err.kind(),
        //         format!(
        //             "{} when getting real_size for {}",
        //             err,
        //             self.fullname_lossy()
        //         ),
        //     )
        // })
    }

    /// Indicates whether this header will be followed by additional
    /// sparse-header records.
    ///
    /// Note that this is handled internally by this library, and is likely only
    /// interesting if a `raw` iterator is being used.
    pub fn is_extended(self: *const Self)  bool {
        return self.isextended[0] == 1;
    }

    /// Views this as a normal `Header`
    pub fn as_header(self: *const Self) *const Header {
        return @ptrCast(*const Header, self);
    }

    /// Views this as a normal `Header`
    pub fn as_header_mut(self: *Self) *Header {
        return @ptrCast(*Header, self);
    }

    // fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
    //     let mut f = f.debug_struct("GnuHeader");
    //     self.as_header().debug_fields(&mut f);
    //     if let Ok(atime) = self.atime() {
    //         f.field("atime", &atime);
    //     }
    //     if let Ok(ctime) = self.ctime() {
    //         f.field("ctime", &ctime);
    //     }
    //     f.field("is_extended", &self.is_extended())
    //         .field("sparse", &DebugSparseHeaders(&self.sparse))
    //         .finish()
    // }
};

/// Description of the header of a spare entry.
///
/// Specifies the offset/number of bytes of a chunk of data in octal.
//#[repr(C)]
//#[allow(missing_docs)]
pub const GnuSparseHeader = extern struct {
    pub offset: [12]u8,
    pub numbytes: [12]u8,

    // impl GnuSparseHeader {
        /// Returns true if block is empty
        pub fn is_empty(self: *const Self) bool {
            return (self.offset[0] == 0) or (self.numbytes[0] == 0);
        }

    /// Offset of the block from the start of the file
    ///
    /// Returns `Err` for a malformed `offset` field.
    pub fn offset(self: *const Self) !u64 {
        return octal_from(self.offset[0..]);
        // octal_from(&self.offset).map_err(|err| {
        //     io::Error::new(
        //         err.kind(),
        //         format!("{} when getting offset from sparce header", err),
        //     )
        // })
    }

    /// Length of the block
    ///
    /// Returns `Err` for a malformed `numbytes` field.
    pub fn length(self: *const Self) !u64 {
        return octal_from(self.numbytes[0..]);
        // octal_from(&self.numbytes).map_err(|err| {
        //     io::Error::new(
        //         err.kind(),
        //         format!("{} when getting length from sparse header", err),
        //     )
        // })
    }

    // fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
    //     let mut f = f.debug_struct("GnuSparseHeader");
    //     if let Ok(offset) = self.offset() {
    //         f.field("offset", &offset);
    //     }
    //     if let Ok(length) = self.length() {
    //         f.field("length", &length);
    //     }
    //     f.finish()
    // }

};

/// Representation of the entry found to represent extended GNU sparse files.
///
/// When a `GnuHeader` has the `isextended` flag set to `1` then the contents of
/// the next entry will be one of these headers.
//#[repr(C)]
//#[allow(missing_docs)]
pub const GnuExtSparseHeader = extern struct {
    pub sparse: [21]GnuSparseHeader,
    pub isextended: [1]u8,
    pub padding: [7]u8,
// impl GnuExtSparseHeader {
//     /// Crates a new zero'd out sparse header entry.
//     pub fn new() -> GnuExtSparseHeader {
//         unsafe { mem::zeroed() }
//     }

//     /// Returns a view into this header as a byte array.
//     pub fn as_bytes(&self) -> &[u8; 512] {
//         debug_assert_eq!(mem::size_of_val(self), 512);
//         unsafe { mem::transmute(self) }
//     }

//     /// Returns a view into this header as a byte array.
//     pub fn as_mut_bytes(&mut self) -> &mut [u8; 512] {
//         debug_assert_eq!(mem::size_of_val(self), 512);
//         unsafe { mem::transmute(self) }
//     }

//     /// Returns a slice of the underlying sparse headers.
//     ///
//     /// Some headers may represent empty chunks of both the offset and numbytes
//     /// fields are 0.
//     pub fn sparse(&self) -> &[GnuSparseHeader; 21] {
//         &self.sparse
//     }

//     /// Indicates if another sparse header should be following this one.
//     pub fn is_extended(&self) -> bool {
//         self.isextended[0] == 1
//     }
// }

// impl Default for GnuExtSparseHeader {
//     fn default() -> Self {
//         Self::new()
//     }
// }

};


// struct DebugAsOctal<T>(T);

// impl<T: fmt::Octal> fmt::Debug for DebugAsOctal<T> {
//     fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
//         fmt::Octal::fmt(&self.0, f)
//     }
// }

// struct DebugSparseHeaders<'a>(&'a [GnuSparseHeader]);

// impl<'a> fmt::Debug for DebugSparseHeaders<'a> {
//     fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
//         let mut f = f.debug_list();
//         for header in self.0 {
//             if !header.is_empty() {
//                 f.entry(header);
//             }
//         }
//         f.finish()
//     }
// }

fn octal_from(slice: []const u8) !u64 {
    var trun = truncate(slice);
    //     let num = match str::from_utf8(trun) {
    //         Ok(n) => n,
    //         Err(_) => {
    //             return Err(other(&format!(
    //                 "numeric field did not have utf-8 text: {}",
    //                 String::from_utf8_lossy(trun)
    //             )))
    //         }
    //     };
    const n = try std.fmt.parseInt(comptime u64: type, trun, 8);
    //     match u64::from_str_radix(num.trim(), 8) {
    //         Ok(n) => Ok(n),
    //         Err(_) => Err(other(&format!("numeric field was not a number: {}", num))),
    //     }
    return n;
}

// fn octal_into<T: fmt::Octal>(dst: &mut [u8], val: T) {
//     let o = format!("{:o}", val);
//     let value = o.bytes().rev().chain(repeat(b'0'));
//     for (slot, value) in dst.iter_mut().rev().skip(1).zip(value) {
//         *slot = value;
//     }
// }
fn octal_into(dest: *[]u8, val: var) void {
    var buf: [32]u8 = undefined;
    debug.assert(dest.len <= buf.len);
    const n = std.fmt.formatIntBuf(buf[0..], val, 8, false, 0);
    for (dest.*) |*b| {
        b.* = '0';
    }
    for (dest.*[dest.len - n - 1..]) |*b, ii| {
        b.* = buf[ii];
    }
}

test "octal.into.from" {
    var s = []u8 {0} ** 6;
    octal_into(&s[0..], usize(8));
    //warn("s={}\n", s);
    debug.assert(mem.eql(u8, s[0..s.len - 1], "00010"));

    const n = try octal_from(s[0..s.len - 1]);
    debug.assert(n == 8);
}

// Wrapper to figure out if we should fill the header field using tar's numeric
// extension (binary) or not (octal).
fn num_field_wrapper_into(dst: *[]u8, src: u64) void {
    if ((src >= 8589934592) or ((src >= 2097152) and (dst.len == 8))) {
        numeric_extended_into(dst, src);
    } else {
        octal_into(dst, src);
    }
}

test "numeric_field_wrapper" {
    debug.assert(false == false);
}

// Wrapper to figure out if we should read the header field in binary (numeric
// extension) or octal (standard encoding).
fn num_field_wrapper_from(src: []const u8) !u64 {
    //warn("num_field_wrapper_from: {}\n", src);
    if ((src[0] & 0x80) != 0) {
        return numeric_extended_from(src);
    } else {
        return octal_from(src[0..]);
    }
}

// When writing numeric fields with is the extended form, the high bit of the
// first byte is set to 1 and the remainder of the field is treated as binary
// instead of octal ascii.
// This handles writing u64 to 8 (uid, gid) or 12 (size, *time) bytes array.
fn numeric_extended_into(dest: *[]u8, src: u64) void {
    // let len: usize = dst.len();
    // for (slot, val) in dst.iter_mut().zip(
    //     repeat(0).take(len - 8) // to zero init extra bytes
    //         .chain((0..8).map(|x| ((src.to_be() >> (8 * x)) & 0xff) as u8)),
    // ) {
    //     *slot = val;
    // }
    dest.*[0] |= 0x80;
}

fn numeric_extended_from(src: []const u8) u64 {
    var dst: u64 = 0;
    var b_to_skip: usize = 1;
    if (src.len == 8) {
        // read first byte without extension flag bit
        dst = u64(src[0] ^ 0x80);
    } else {
        // only read last 8 bytes
        b_to_skip = src.len - 8;
    }
    for (src[b_to_skip..]) |*byte| {
        dst <<= 8;
        dst |= (byte.*);
    }
    return dst;
}

// a bit close to @truncate!?!
fn truncate(slice: var) @typeOf(slice) {
    return slice[0..for (slice) |b, ii| {
        if (b == 0) {
            break ii;
        }
    } else slice.len];
}

// /// Copies `bytes` into the `slot` provided, returning an error if the `bytes`
// /// array is too long or if it contains any nul bytes.
// fn copy_into(slot: &mut [u8], bytes: &[u8]) -> io::Result<()> {
//     if bytes.len() > slot.len() {
//         Err(other("provided value is too long"))
//     } else if bytes.iter().any(|b| *b == 0) {
//         Err(other("provided value contains a nul byte"))
//     } else {
//         for (slot, val) in slot.iter_mut().zip(bytes.iter().chain(Some(&0))) {
//             *slot = *val;
//         }
//         Ok(())
//     }
// }
fn copy_into(dest: []u8, src: []const u8) !void {
    debug.assert(dest.len >= src.len);
    for (src) |b, ii| {
        if (b == 0) {
            return error.EmbeddedNul;
        }
        dest[ii] = b;
    }
}

// /// Copies `path` into the `slot` provided
// ///
// /// Returns an error if:
// ///
// /// * the path is too long to fit
// /// * a nul byte was found
// /// * an invalid path component is encountered (e.g. a root path or parent dir)
// /// * the path itself is empty
// fn copy_path_into(mut slot: &mut [u8], path: &Path, is_link_name: bool) -> io::Result<()> {
//     let mut emitted = false;
//     let mut needs_slash = false;
//     for component in path.components() {
//         let bytes = path2bytes(Path::new(component.as_os_str()))?;
//         match (component, is_link_name) {
//             (Component::Prefix(..), false) | (Component::RootDir, false) => {
//                 return Err(other("paths in archives must be relative"))
//             }
//             (Component::ParentDir, false) => {
//                 return Err(other("paths in archives must not have `..`"))
//             }
//             // Allow "./" as the path
//             (Component::CurDir, false) if path.components().count() == 1 => {}
//             (Component::CurDir, false) => continue,
//             (Component::Normal(_), _) | (_, true) => {}
//         };
//         if needs_slash {
//             copy(&mut slot, b"/")?;
//         }
//         if bytes.contains(&b'/') {
//             if let Component::Normal(..) = component {
//                 return Err(other("path component in archive cannot contain `/`"));
//             }
//         }
//         copy(&mut slot, &*bytes)?;
//         if &*bytes != b"/" {
//             needs_slash = true;
//         }
//         emitted = true;
//     }
//     if !emitted {
//         return Err(other("paths in archives must have at least one component"));
//     }
//     if ends_with_slash(path) {
//         copy(&mut slot, &[b'/'])?;
//     }
//     return Ok(());

//     fn copy(slot: &mut &mut [u8], bytes: &[u8]) -> io::Result<()> {
//         copy_into(*slot, bytes)?;
//         let tmp = mem::replace(slot, &mut []);
//         *slot = &mut tmp[bytes.len()..];
//         Ok(())
//     }
// }

// #[cfg(windows)]
// fn ends_with_slash(p: &Path) -> bool {
//     let last = p.as_os_str().encode_wide().last();
//     last == Some(b'/' as u16) or last == Some(b'\\' as u16)
// }

// #[cfg(any(unix, target_os = "redox"))]
// fn ends_with_slash(p: &Path) -> bool {
//     p.as_os_str().as_bytes().ends_with(&[b'/'])
// }

fn contains(str: []const u8, byte: u8) bool {
    return for (str) |b| {
        if (b == byte) {
            break true;
        }
    } else false;
}

fn ends_with_slash(path: []const u8) bool {
    //debug.assert(path[0] != 0);
    if (path.len == 0) return false;
    return path[for (path) |b, ii| {
        if (b == 0) {
            break ii - 1;
        }
    } else path.len - 1] == '/';
}

test "ends_with_slash or contains" {
    const x = "/hello zig";
    const y = "hello/ zig";
    const z = "hello zig/";

    debug.assert(ends_with_slash(x) == false);
    debug.assert(ends_with_slash(y) == false);
    debug.assert(ends_with_slash(z) == true);
    debug.assert(contains("", 'x') == false);
    debug.assert(contains(x, 'x') == false);
    debug.assert(contains(z, '/') == true);
    if (false) {
        warn("'{}' ends with slash = {}\n", x, ends_with_slash(x));
        warn("'{}' ends with slash = {}\n", y, ends_with_slash(y));
        warn("'{}' ends with slash = {}\n", z, ends_with_slash(z));
    }
}

// #[cfg(windows)]
// pub fn path2bytes(p: &Path) -> io::Result<Cow<[u8]>> {
//     p.as_os_str()
//         .to_str()
//         .map(|s| s.as_bytes())
//         .ok_or_else(or other(&format!("path {} was not valid unicode", p.display())))
//         .map(|bytes| {
//             if bytes.contains(&b'\\') {
//                 // Normalize to Unix-style path separators
//                 let mut bytes = bytes.to_owned();
//                 for b in &mut bytes {
//                     if *b == b'\\' {
//                         *b = b'/';
//                     }
//                 }
//                 Cow::Owned(bytes)
//             } else {
//                 Cow::Borrowed(bytes)
//             }
//         })
// }

// #[cfg(any(unix, target_os = "redox"))]
// /// On unix this will never fail
// pub fn path2bytes(p: &Path) -> io::Result<Cow<[u8]>> {
//     Ok(p.as_os_str().as_bytes()).map(Cow::Borrowed)
// }

/// Make sure you free the result when done...
pub fn path2bytes(path: []const u8, allocator: Allocator) ![]u8{
    // We alloc so we may fail
    const pathname = truncate(path);
    const buf = try allocator.alloc(u8, pathname.len);
    errdefer allocator.free(buf);

    mem.copy(u8, buf, pathname);
    return buf[0..];
}

// #[cfg(windows)]
// /// On windows we cannot accept non-unicode bytes because it
// /// is impossible to convert it to UTF-16.
// pub fn bytes2path(bytes: Cow<[u8]>) -> io::Result<Cow<Path>> {
//     return match bytes {
//         Cow::Borrowed(bytes) => {
//             let s = try!(str::from_utf8(bytes).map_err(|_| not_unicode(bytes)));
//             Ok(Cow::Borrowed(Path::new(s)))
//         }
//         Cow::Owned(bytes) => {
//             let s = try!(String::from_utf8(bytes).map_err(|uerr| not_unicode(&uerr.into_bytes())));
//             Ok(Cow::Owned(PathBuf::from(s)))
//         }
//     };

//     fn not_unicode(v: &[u8]) -> io::Error {
//         other(&format!(
//             "only unicode paths are supported on windows: {}",
//             String::from_utf8_lossy(v)
//         ))
//     }
// }

// #[cfg(any(unix, target_os = "redox"))]
// /// On unix this operation can never fail.
// pub fn bytes2path(bytes: Cow<[u8]>) -> io::Result<Cow<Path>> {
//     use std::ffi::{OsStr, OsString};

//     Ok(match bytes {
//         Cow::Borrowed(bytes) => Cow::Borrowed({ Path::new(OsStr::from_bytes(bytes)) }),
//         Cow::Owned(bytes) => Cow::Owned({ PathBuf::from(OsString::from_vec(bytes)) }),
//     })
// }

