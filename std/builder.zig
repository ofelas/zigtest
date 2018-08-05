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

// use std::borrow::Cow;
// use std::fs;
// use std::io;
// use std::io::prelude::*;
// use std::path::Path;

const Path = @import("path.zig").Path;

const header_ = @import("header.zig");
const Header = header_.Header;
const HeaderMode = header_.HeaderMode;
const path2bytes = header_.path2bytes;

// use header::{bytes2path, path2bytes, HeaderMode};
// use {other, EntryType, Header};


/// A Write trait!?
pub const Writer = struct {
    const Self = this;
    const Error = error{OutOfSpace};

    writeAllFn: fn (self: *Self, buffer: []const u8) Error!void,
    flushFn: fn (self: *Self) Error!void,

    pub fn write_all(self: *Self, buffer: []const u8) Error!void {
        return self.writeAllFn(self, buffer);
    }

    pub fn flush(self: *Self) Error!void {
        self.flushFn(self);
    }
};

/// Implementation of Write trait for []u8
/// This is more or less like a SliceOutStream
pub const FixedWriter = struct {
    pos: usize,
    buffer: []u8,
    writer: Writer,

    pub fn init(buf: []u8) FixedWriter {
        return FixedWriter{
            .pos = 0,
            .buffer = buf,
            .writer = Writer { .writeAllFn = write_all, .flushFn = flush },
        };
    }

    fn write_all(writer: *Writer, buffer: []const u8) Writer.Error!void {
        const self = @fieldParentPtr(FixedWriter, "writer", writer);
        if ((self.pos + buffer.len) < self.buffer.len) {
            for (buffer) |b, ii| {
                self.buffer[self.pos + ii] = b;
            }
            self.pos += buffer.len;
        } else {
            return error.OutOfSpace;
        }
    }

    fn flush(writer: *Writer) Writer.Error!void {
        const self = @fieldParentPtr(FixedWriter, "writer", writer);
        if (self.pos >= self.buffer.len) {
            return error.OutOfSpace;
        }
    }
};

// W anything that implements Writer.write_all?
pub const Builder = struct {
    /// A structure for building archives
    ///
    /// This structure has methods for building up an archive from scratch into any
    /// arbitrary writer.
    /// W is a Write(r)
    const Self = this;

    mode: HeaderMode,
    follow: bool,
    finished: bool,
    obj: *Writer,
    /// Create a new archive builder with the underlying object as the
    /// destination of all data written. The builder will use
    /// `HeaderMode::Complete` by default.
    pub fn new(obj: *Writer) Self {
        return Self {
            .mode = HeaderMode.Complete,
            .follow = true,
            .finished = false,
            .obj = obj,
        };
    }

    fn inner(self: *Self) *Writer {
        return self.obj.as_mut(); // .unwrap()
    }
    /// Changes the HeaderMode that will be used when reading fs Metadata for
    /// methods that implicitly read metadata for an input Path. Notably, this
    /// does _not_ apply to `append(Header)`.
    // was mode() conflicts with other member
    pub fn set_mode(self: *Self, mode_: HeaderMode) void {
        self.mode = mode_;
    }

    /// Follow symlinks, archiving the contents of the file they point to rather
    /// than adding a symlink to the archive. Defaults to true.
    pub fn follow_symlinks(self: *Self, follow: bool) void {
        self.follow = follow;
    }

    /// Unwrap this archive, returning the underlying object.
    ///
    /// This function will finish writing the archive if the `finish` function
    /// hasn't yet been called, returning any I/O error which happens during
    /// that operation.
    pub fn into_inner(self: *Self) !*Writer {
        if (!self.finished) {
            try self.finish();
        }
        return self.obj; // take().unwrap()?
    }
    /// Adds a new entry to this archive.
    ///
    /// This function will append the header specified, followed by contents of
    /// the stream specified by `data`. To produce a valid archive the `size`
    /// field of `header` must be the same as the length of the stream that's
    /// being written. Additionally the checksum for the header should have been
    /// set via the `set_cksum` method.
    ///
    /// Note that this will not attempt to seek the archive to a valid position,
    /// so if the archive is in the middle of a read or some other similar
    /// operation then this may corrupt the archive.
    ///
    /// Also note that after all entries have been written to an archive the
    /// `finish` function needs to be called to finish writing the archive.
    ///
    /// # Errors
    ///
    /// This function will return an error for any intermittent I/O error which
    /// occurs when either reading or writing.
    ///
    /// # Examples
    ///
    /// ```
    /// use tar::{Builder, Header};
    ///
    /// let mut header = Header::new_gnu();
    /// header.set_path("foo").unwrap();
    /// header.set_size(4);
    /// header.set_cksum();
    ///
    /// let mut data: &[u8] = &[1, 2, 3, 4];
    ///
    /// let mut ar = Builder::new(Vec::new());
    /// ar.append(&header, data).unwrap();
    /// let data = ar.into_inner().unwrap();
    /// ```
    // <R: Read>, data: R, could use var?
    pub fn append(self: *Self, header: *Header, data: []const u8) !void {
        //return append(self.inner(), header, data);
        // fn append(dst: *Write, header: *Header, data: *Read) !void {
        try self.obj.write_all(header.as_bytes());
        //let len = io::copy(&mut data, &mut dst)?;
        try self.obj.write_all(data);
        // Pad with zeros if necessary.
        const buf = []u8 {0} ** 512;
        const remaining = 512 - (data.len % 512);
        if (remaining < 512) {
            try self.obj.write_all(buf[0..remaining]);
        }
        //}
    }


    /// Finish writing this archive, emitting the termination sections.
    ///
    /// This function should only be called when the archive has been written
    /// entirely and if an I/O error happens the underlying object still needs
    /// to be acquired.
    ///
    /// In most situations the `into_inner` method should be preferred.
    pub fn finish(self: *Self) !void {
        if (self.finished) {
            return;
        }
        self.finished = true;
        const buf = []u8 {0} ** 1024;
        return self.obj.write_all(buf); // &[0; 1024]
    }
    
    // impl<W: Write> Drop for Builder<W> {
    //     fn drop(&mut self) {
    //         let _ = self.finish();
    //     }
    // }
};


test "Builder" {
    var buf = []u8 {0} ** 2048;
    var fw = FixedWriter.init(buf[0..]);

    var t = Builder.new(&fw.writer);
    t.set_mode(HeaderMode.Complete);
    t.follow_symlinks(false);

    var data = "hello world";
    var header = Header.new_gnu();
    header.set_size(data.len);
    header.set_cksum();
    try t.append(&header, data);

    debug.assert(mem.eql(u8, data, buf[512..512 + data.len]));
    if (true) {
        for (buf[512..fw.pos]) |b, ii| {
            warn("{x02}", b);
            if ((ii + 1) & 0xf == 0) {
                warn(" {}\n", ii);
            }
        }
    }

    var b = t.into_inner();
    //_ = t.inner();
}


//     /// Adds a new entry to this archive with the specified path.
//     ///
//     /// This function will set the specified path in the given header, which may
//     /// require appending a GNU long-name extension entry to the archive first.
//     /// The checksum for the header will be automatically updated via the
//     /// `set_cksum` method after setting the path. No other metadata in the
//     /// header will be modified.
//     ///
//     /// Then it will append the header, followed by contents of the stream
//     /// specified by `data`. To produce a valid archive the `size` field of
//     /// `header` must be the same as the length of the stream that's being
//     /// written.
//     ///
//     /// Note that this will not attempt to seek the archive to a valid position,
//     /// so if the archive is in the middle of a read or some other similar
//     /// operation then this may corrupt the archive.
//     ///
//     /// Also note that after all entries have been written to an archive the
//     /// `finish` function needs to be called to finish writing the archive.
//     ///
//     /// # Errors
//     ///
//     /// This function will return an error for any intermittent I/O error which
//     /// occurs when either reading or writing.
//     ///
//     /// # Examples
//     ///
//     /// ```
//     /// use tar::{Builder, Header};
//     ///
//     /// let mut header = Header::new_gnu();
//     /// header.set_size(4);
//     /// header.set_cksum();
//     ///
//     /// let mut data: &[u8] = &[1, 2, 3, 4];
//     ///
//     /// let mut ar = Builder::new(Vec::new());
//     /// ar.append_data(&mut header, "really/long/path/to/foo", data).unwrap();
//     /// let data = ar.into_inner().unwrap();
//     /// ```
//     pub fn append_data<P: AsRef<Path>, R: Read>(
//         &mut self,
//         header: &mut Header,
//         path: P,
//         data: R,
//     ) -> io::Result<()> {
//         prepare_header(self.inner(), header, path.as_ref())?;
//         header.set_cksum();
//         self.append(&header, data)
//     }

//     /// Adds a file on the local filesystem to this archive.
//     ///
//     /// This function will open the file specified by `path` and insert the file
//     /// into the archive with the appropriate metadata set, returning any I/O
//     /// error which occurs while writing. The path name for the file inside of
//     /// this archive will be the same as `path`, and it is required that the
//     /// path is a relative path.
//     ///
//     /// Note that this will not attempt to seek the archive to a valid position,
//     /// so if the archive is in the middle of a read or some other similar
//     /// operation then this may corrupt the archive.
//     ///
//     /// Also note that after all files have been written to an archive the
//     /// `finish` function needs to be called to finish writing the archive.
//     ///
//     /// # Examples
//     ///
//     /// ```no_run
//     /// use tar::Builder;
//     ///
//     /// let mut ar = Builder::new(Vec::new());
//     ///
//     /// ar.append_path("foo/bar.txt").unwrap();
//     /// ```
//     pub fn append_path<P: AsRef<Path>>(&mut self, path: P) -> io::Result<()> {
//         let mode = self.mode.clone();
//         let follow = self.follow;
//         append_path(self.inner(), path.as_ref(), mode, follow)
//     }

//     /// Adds a file to this archive with the given path as the name of the file
//     /// in the archive.
//     ///
//     /// This will use the metadata of `file` to populate a `Header`, and it will
//     /// then append the file to the archive with the name `path`.
//     ///
//     /// Note that this will not attempt to seek the archive to a valid position,
//     /// so if the archive is in the middle of a read or some other similar
//     /// operation then this may corrupt the archive.
//     ///
//     /// Also note that after all files have been written to an archive the
//     /// `finish` function needs to be called to finish writing the archive.
//     ///
//     /// # Examples
//     ///
//     /// ```no_run
//     /// use std::fs::File;
//     /// use tar::Builder;
//     ///
//     /// let mut ar = Builder::new(Vec::new());
//     ///
//     /// // Open the file at one location, but insert it into the archive with a
//     /// // different name.
//     /// let mut f = File::open("foo/bar/baz.txt").unwrap();
//     /// ar.append_file("bar/baz.txt", &mut f).unwrap();
//     /// ```
//     pub fn append_file<P: AsRef<Path>>(&mut self, path: P, file: &mut fs::File) -> io::Result<()> {
//         let mode = self.mode.clone();
//         append_file(self.inner(), path.as_ref(), file, mode)
//     }

//     /// Adds a directory to this archive with the given path as the name of the
//     /// directory in the archive.
//     ///
//     /// This will use `stat` to populate a `Header`, and it will then append the
//     /// directory to the archive with the name `path`.
//     ///
//     /// Note that this will not attempt to seek the archive to a valid position,
//     /// so if the archive is in the middle of a read or some other similar
//     /// operation then this may corrupt the archive.
//     ///
//     /// Also note that after all files have been written to an archive the
//     /// `finish` function needs to be called to finish writing the archive.
//     ///
//     /// # Examples
//     ///
//     /// ```
//     /// use std::fs;
//     /// use tar::Builder;
//     ///
//     /// let mut ar = Builder::new(Vec::new());
//     ///
//     /// // Use the directory at one location, but insert it into the archive
//     /// // with a different name.
//     /// ar.append_dir("bardir", ".").unwrap();
//     /// ```
//     pub fn append_dir<P, Q>(&mut self, path: P, src_path: Q) -> io::Result<()>
//     where
//         P: AsRef<Path>,
//         Q: AsRef<Path>,
//     {
//         let mode = self.mode.clone();
//         append_dir(self.inner(), path.as_ref(), src_path.as_ref(), mode)
//     }

//     /// Adds a directory and all of its contents (recursively) to this archive
//     /// with the given path as the name of the directory in the archive.
//     ///
//     /// Note that this will not attempt to seek the archive to a valid position,
//     /// so if the archive is in the middle of a read or some other similar
//     /// operation then this may corrupt the archive.
//     ///
//     /// Also note that after all files have been written to an archive the
//     /// `finish` function needs to be called to finish writing the archive.
//     ///
//     /// # Examples
//     ///
//     /// ```
//     /// use std::fs;
//     /// use tar::Builder;
//     ///
//     /// let mut ar = Builder::new(Vec::new());
//     ///
//     /// // Use the directory at one location, but insert it into the archive
//     /// // with a different name.
//     /// ar.append_dir_all("bardir", ".").unwrap();
//     /// ```
//     pub fn append_dir_all<P, Q>(&mut self, path: P, src_path: Q) -> io::Result<()>
//     where
//         P: AsRef<Path>,
//         Q: AsRef<Path>,
//     {
//         let mode = self.mode.clone();
//         let follow = self.follow;
//         append_dir_all(self.inner(), path.as_ref(), src_path.as_ref(), mode, follow)
//     }


// fn append(dst: *Write, header: *Header, data: *Read) !void {
//     try dst.write_all(header.as_bytes());
//     let len = io::copy(&mut data, &mut dst)?;
//     // Pad with zeros if necessary.
//     const buf = []u8 {0} ** 512;
//     let remaining = 512 - (len % 512);
//     if (remaining < 512) {
//         try dst.write_all(buf[0..remaining]);
//     }
// }

// Fn append_path(dst: &mut Write, path: &Path, mode: HeaderMode, follow: bool) -> io::Result<()> {
//     let stat = if follow {
//         fs::metadata(path).map_err(|err| {
//             io::Error::new(
//                 err.kind(),
//                 format!("{} when getting metadata for {}", err, path.display()),
//             )
//         })?
//     } else {
//         fs::symlink_metadata(path).map_err(|err| {
//             io::Error::new(
//                 err.kind(),
//                 format!("{} when getting metadata for {}", err, path.display()),
//             )
//         })?
//     };
//     if stat.is_file() {
//         append_fs(dst, path, &stat, &mut fs::File::open(path)?, mode, None)
//     } else if stat.is_dir() {
//         append_fs(dst, path, &stat, &mut io::empty(), mode, None)
//     } else if stat.file_type().is_symlink() {
//         let link_name = fs::read_link(path)?;
//         append_fs(dst, path, &stat, &mut io::empty(), mode, Some(&link_name))
//     } else {
//         Err(other(&format!("{} has unknown file type", path.display())))
//     }
// }

// fn append_file(
//     dst: &mut Write,
//     path: &Path,
//     file: &mut fs::File,
//     mode: HeaderMode,
// ) -> io::Result<()> {
//     let stat = file.metadata()?;
//     append_fs(dst, path, &stat, file, mode, None)
// }

// fn append_dir(dst: &mut Write, path: &Path, src_path: &Path, mode: HeaderMode) -> io::Result<()> {
//     let stat = fs::metadata(src_path)?;
//     append_fs(dst, path, &stat, &mut io::empty(), mode, None)
// }

//fn prepare_header(dst: &mut Write, header: &mut Header, path: &Path) -> io::Result<()> {
fn prepare_header(comptime W: type, comptime R: type,
                  dst: *W, header: *Header, path: *const Path) !void {
    // Try to encode the path directly in the header, but if it ends up not
    // working (e.g. it's too long) then use the GNU-specific long name
    // extension by emitting an entry which indicates that it's the filename
    //if let Err(e) = header.set_path(path) {
    if (header.set_path(path)) |_| {
        return;
    } else |err| {
        const data = try path2bytes(path);
        const max = header.as_old().name.len();
        if (data.len < max) {
            return err;
        }
        var header2 = Header.new_gnu();
        //header2.as_gnu_mut().unwrap().name[..13].clone_from_slice(b"././@LongLink");
        header2.set_mode(0o644);
        header2.set_uid(0);
        header2.set_gid(0);
        header2.set_mtime(0);
        header2.set_size((data.len + 1));
        header2.set_entry_type(EntryType.new('L'));
        header2.set_cksum();
        //let mut data2 = data.chain(io::repeat(0).take(0));
        //append(dst, &header2, &mut data2)?;
        // Truncate the path to store in the header we're about to emit to
        // ensure we've got something at least mentioned.
        //let path = bytes2path(Cow::Borrowed(&data[..max]))?;
        //header.set_path(&path)?;
    }
}

// fn append_fs(
//     dst: &mut Write,
//     path: &Path,
//     meta: &fs::Metadata,
//     read: &mut Read,
//     mode: HeaderMode,
//     link_name: Option<&Path>,
// ) -> io::Result<()> {
//     let mut header = Header::new_gnu();

//     prepare_header(dst, &mut header, path)?;
//     header.set_metadata_in_mode(meta, mode);
//     if let Some(link_name) = link_name {
//         header.set_link_name(link_name)?;
//     }
//     header.set_cksum();
//     append(dst, &header, read)
// }

// fn append_dir_all(
//     dst: &mut Write,
//     path: &Path,
//     src_path: &Path,
//     mode: HeaderMode,
//     follow: bool,
// ) -> io::Result<()> {
//     let mut stack = vec![(src_path.to_path_buf(), true, false)];
//     while let Some((src, is_dir, is_symlink)) = stack.pop() {
//         let dest = path.join(src.strip_prefix(&src_path).unwrap());
//         if is_dir {
//             for entry in fs::read_dir(&src)? {
//                 let entry = entry?;
//                 let file_type = entry.file_type()?;
//                 stack.push((entry.path(), file_type.is_dir(), file_type.is_symlink()));
//             }
//             if dest != Path::new("") {
//                 append_dir(dst, &dest, &src, mode)?;
//             }
//         } else if !follow && is_symlink {
//             let stat = fs::symlink_metadata(&src)?;
//             let link_name = fs::read_link(&src)?;
//             append_fs(dst, &dest, &stat, &mut io::empty(), mode, Some(&link_name))?;
//         } else {
//             append_file(dst, &dest, &mut fs::File::open(src)?, mode)?;
//         }
//     }
//     Ok(())
// }

