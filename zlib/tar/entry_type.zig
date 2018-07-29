// See https://en.wikipedia.org/wiki/Tar_%28computing%29#UStar_format
/// Indicate for the type of file described by a header.
///
/// Each `Header` has an `entry_type` method returning an instance of this type
/// which can be used to inspect what the header is describing.

/// A non-exhaustive enum representing the possible entry types
//#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub const EntryType = enum {
    const Self = this;

    /// Regular file
    Regular,
    /// Hard link
    Link,
    /// Symbolic link
    Symlink,
    /// Character device
    Char,
    /// Block device
    Block,
    /// Directory
    Directory,
    /// Named pipe (fifo)
    Fifo,
    /// Implementation-defined 'high-performance' type, treated as regular file
    Continuous,
    /// GNU extension - long file name
    GNULongName,
    /// GNU extension - long link name (link target)
    GNULongLink,
    /// GNU extension - sparse file
    GNUSparse,
    /// Global extended header
    XGlobalHeader,
    /// Extended Header
    XHeader,
    /// Hints that destructuring should not be exhaustive.
    ///
    /// This enum may grow additional variants, so this makes sure clients
    /// don't count on exhaustive matching. (Otherwise, adding a new variant
    /// could break existing code.)
    //#[doc(hidden)]
    //__Nonexhaustive (u8),
    __Nonexhaustive,

    /// Creates a new entry type from a raw byte.
    ///
    /// Note that the other named constructors of entry type may be more
    /// appropriate to create a file type from.
    pub fn new(byte: u8) EntryType {
        return switch (byte) {
            '\x00', '0' => EntryType.Regular,
            '1' => EntryType.Link,
            '2' => EntryType.Symlink,
            '3' => EntryType.Char,
            '4' => EntryType.Block,
            '5' => EntryType.Directory,
            '6' => EntryType.Fifo,
            '7' => EntryType.Continuous,
            'x' => EntryType.XHeader,
            'g' => EntryType.XGlobalHeader,
            'L' => EntryType.GNULongName,
            'K' => EntryType.GNULongLink,
            'S' => EntryType.GNUSparse,
            else => EntryType.__Nonexhaustive, //(b),
        };
    }

    /// Returns the raw underlying byte that this entry type represents.
    pub fn as_byte(self: *const Self) u8 {
        const b: u8 = switch(self.*) {
            EntryType.Regular => '0',
            EntryType.Link => '1',
            EntryType.Symlink => '2',
            EntryType.Char => '3',
            EntryType.Block => '4',
            EntryType.Directory => '5',
            EntryType.Fifo => '6',
            EntryType.Continuous => '7',
            EntryType.XHeader => 'x',
            EntryType.XGlobalHeader => 'g',
            EntryType.GNULongName => 'L',
            EntryType.GNULongLink => 'K',
            EntryType.GNUSparse => 'S',
            // whoops: we lost this one, union(enum)?
            EntryType.__Nonexhaustive => '0', //(b)
            else => '0',
        };

        return b;
    }

    /// Creates a new entry type representing a regular file.
    pub fn file() EntryType {
        return EntryType.Regular;
    }

    /// Creates a new entry type representing a hard link.
    pub fn hard_link() EntryType {
        return EntryType.Link;
    }

    /// Creates a new entry type representing a symlink.
    pub fn symlink() EntryType {
        return EntryType.Symlink;
    }

    /// Creates a new entry type representing a character special device.
    pub fn character_special() EntryType {
        return EntryType.Char;
    }

    /// Creates a new entry type representing a block special device.
    pub fn block_special() EntryType {
        return EntryType.Block;
    }

    /// Creates a new entry type representing a directory.
    pub fn dir() EntryType {
        return EntryType.Directory;
    }

    /// Creates a new entry type representing a FIFO.
    pub fn fifo() EntryType {
        return EntryType.Fifo;
    }

    /// Creates a new entry type representing a contiguous file.
    pub fn contiguous() EntryType {
        return EntryType.Continuous;
    }

    /// Returns whether this type represents a regular file.
    pub fn is_file(self: *const Self) bool {
        return self.* == EntryType.Regular;
    }

    /// Returns whether this type represents a hard link.
    pub fn is_hard_link(self: *const Self) bool {
        return self.* == EntryType.Link;
    }

    /// Returns whether this type represents a symlink.
    pub fn is_symlink(self: *const Self)  bool {
        return self.* == EntryType.Symlink;
    }

    /// Returns whether this type represents a character special device.
    pub fn is_character_special(self: *const Self) bool {
        return self.* == EntryType.Char;
    }

    /// Returns whether this type represents a block special device.
    pub fn is_block_special(self: *const Self)  bool {
        return self.* == EntryType.Block;
    }

    /// Returns whether this type represents a directory.
    pub fn is_dir(self: *const Self)  bool {
        return self.* == EntryType.Directory;
    }

    /// Returns whether this type represents a FIFO.
    pub fn is_fifo(self: *const Self) bool {
        return self.* == EntryType.Fifo;
    }

    /// Returns whether this type represents a contiguous file.
    pub fn is_contiguous(self: *const Self) bool {
        return self.* == EntryType.Continuous;
    }

    /// Returns whether this type represents a GNU long name header.
    pub fn is_gnu_longname(self: *const Self) bool {
        return self.* == EntryType.GNULongName;
    }

    /// Returns whether this type represents a GNU sparse header.
    pub fn is_gnu_sparse(self: *const Self) bool {
        return self.* == EntryType.GNUSparse;
    }

    /// Returns whether this type represents a GNU long link header.
    pub fn is_gnu_longlink(self: *const Self) bool {
        return self.* == EntryType.GNULongLink;
    }

    /// Returns whether this type represents a GNU long name header.
    pub fn is_pax_global_extensions(self: *const Self) bool {
        return self.* == EntryType.XGlobalHeader;
    }

    /// Returns whether this type represents a GNU long link header.
    pub fn is_pax_local_extensions(self: *const Self) bool {
        return self.* == EntryType.XHeader;
    }
};
