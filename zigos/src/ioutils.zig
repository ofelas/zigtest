// import unsigned
//type  PVIDMem* = ptr array[0..65_000, TEntry]
pub const PVidMem = []TEntry;
pub const VGAWidth = 80;
pub const VGAHeight = 25;

pub struct TPos {
    pub x: isize,
    pub y: isize,
}

// Some types
pub const TAttribute = u8;
pub const TEntry = u16;

pub enum TVGAColor {
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
}

pub fn nextColor(color: TVGAColor) -> TVGAColor {
    //proc nextColor(color: TVGAColor, skip: set[TVGAColor]): TVGAColor =
    var result = color;
    if ((color == TVGAColor.White) || (color == TVGAColor.Black)) {
        result = TVGAColor.Blue;
   } else {
        result = TVGAColor(u8(color) + 1);
    }
    // if result in skip: result = nextColor(result, skip)
    return result;
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

/// Writes a character at the specified ``pos``.
pub fn writeChar(vram: PVidMem, entry: TEntry, pos: TPos) {
    const index = usize((VGAWidth * pos.y) + pos.x);
    vram[index] = entry;
}

pub fn rainbow(vram: PVidMem, text: []u8, pos: TPos) {
//     //## Writes a string at the specified ``pos`` with varying colors which, despite
//     //## the name of this function, do not resemble a rainbow.
//     var colorBG = DarkGrey;
//     var colorFG = Blue;
    var color = TVGAColor.Blue;

//   // for i in 0 .. text.len-1:
//   //   colorFG = nextColor(colorFG, {Black, Cyan, DarkGrey, Magenta, Red,
//   //                                 Blue, LightBlue, LightMagenta})
//   //   let attr = makeColor(colorBG, colorFG)
//   //   vram.writeChar(makeEntry(text[i], attr), (pos.x+i, pos.y))
    for (text) |c, i| {
        const cc = makeColor(TVGAColor.Black, color);
        writeChar(vram, makeEntry(c, cc), TPos{.x = pos.x + isize(i), .y = pos.y});
        color = nextColor(color);
    }
}

pub fn writeString(vram: PVidMem, text: []u8, color: TAttribute, pos: TPos) {
  //## Writes a string at the specified ``pos`` with the specified ``color``.
    for (text) |c, i| {
        //for i in 0 .. text.len-1:
        writeChar(vram, makeEntry(c, color), TPos{.x = pos.x + isize(i), .y = pos.y});
    }
}

pub fn screenClear(video_mem: PVidMem, color: TVGAColor) {
    // Clears the screen with a specified ``color``.
    const space = makeEntry(' ', makeColor(color, color));

    {var i = usize(0); while (i <= (VGAWidth * VGAHeight); i += 1) {
        video_mem[i] = space;
    }}
}

fn testIOUTILS() {
    @setFnTest(this, true);

    var c = makeColor(TVGAColor.Black, TVGAColor.Red);
}
