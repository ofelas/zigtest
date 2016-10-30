// import unsigned
//type  PVIDMem* = ptr array[0..65_000, TEntry]
pub const PVidMem = []TEntry;
pub const VGAWidth = 80;
pub const VGAHeight = 25;
pub const VGA_VIDEO_BASEADDRESS = 0xB8000;

pub struct VGA {
    const Self = this;
    width: usize,
    heigth: usize,
    baseAddress: usize,
    vram: PVidMem,

    pub fn init(vga: &Self) {
        vga.width = VGAWidth;
        vga.heigth = VGAHeight;
        vga.baseAddress = usize(VGA_VIDEO_BASEADDRESS);
        vga.vram.ptr = (&u16)(vga.baseAddress);
        vga.vram.len = 65000;
    }

    /// Writes a character at the specified ``pos``.
    inline fn writeChar(vga: &Self, entry: TEntry, pos: TPos) {
        const index = usize((vga.width * pos.y) + pos.x);
        // assert(index < vga.vram.len);
        vga.vram[index] = entry;
    }

    /// Clear the screen given the background color
    pub fn clearScreen(vga: &Self, color: TVGAColor) {
        const space = makeEntry(' ', makeColor(color, color));
        {
            var i = usize(0);
            while (i <= (vga.width * vga.heigth); i += 1) {
                vga.vram[i] = space;
            }
        }
    }

    /// Writes a string at the specified ``pos`` with varying colors which, despite
    /// the name of this function, do not resemble a rainbow.
    pub fn rainbow(vga: &Self, text: []u8, pos: TPos) {
        const colorBG = TVGAColor.Black;
        var colorFG = TVGAColor.Blue;

        for (text) |c, i| {
            const cc = makeColor(colorBG, colorFG);
            writeChar(vga, makeEntry(c, cc), TPos{.x = pos.x + i, .y = pos.y});
            colorFG = colorFG.nextColor();
        }
    }

    /// Writes a string at the specified ``pos`` with the specified ``color``.
    pub fn writeString(vga: &Self, text: []u8, color: TAttribute, pos: TPos) {
        for (text) |c, i| {
            writeChar(vga, makeEntry(c, color), TPos{.x = pos.x + i, .y = pos.y});
       }
    }

}

pub struct TPos {
    pub x: usize,
    pub y: usize,
}

// Some types
pub const TAttribute = u8;
pub const TEntry = u16;

pub enum TVGAColor {
    const Self = this;
    Black,
    Blue,
    Green,
    Cyan,
    Red,
    Magenta,
    Brown,
    LightGrey,
    DarkGrey,
    LightBlue,
    LightGreen,
    LightCyan,
    LightRed,
    LightMagenta,
    Yellow,
    White,

    pub fn nextColor(color: Self) -> TVGAColor {
        var result = color;
        if ((color == TVGAColor.White) || (color == TVGAColor.Black)) {
            result = TVGAColor.Blue;
        } else {
            result = TVGAColor(u8(color) + 1);
        }
        return result;
    }
}

/// Combines a foreground and background color into a ``TAttribute``.
pub fn makeColor(bg: TVGAColor, fg: TVGAColor) -> TAttribute {
    return TAttribute(u8(fg) | (u8(bg) << 4));
}

/// Combines a char and a TAttribute into a format which can be
/// directly written to the Video memory.
pub fn makeEntry(c: u8, color: TAttribute) -> TEntry {
    const c16 = u16(c);
    const color16 = u16(color);
    return TEntry(c16 | (color16 << 8));
}

fn testIOUTILS() {
    @setFnTest(this, true);

    var c = makeColor(TVGAColor.Black, TVGAColor.Red);
}
