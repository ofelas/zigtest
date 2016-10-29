const ioutils = @import("ioutils.zig");
const makeColor = ioutils.makeColor;
const writeString = ioutils.writeString;
const rainbow = ioutils.rainbow;
const screenClear = ioutils.screenClear;
const PVidMem = ioutils.PVidMem;
const TPos = ioutils.TPos;
const TVGAColor = ioutils.TVGAColor;
const TEntry = ioutils.TEntry;

const TMultiboot_header = &u8;
const MULTIBOOT_MAGIC = u32(0xe85250d6);

inline fn mkTPos(x: u8, y: u8) -> TPos {
   TPos{.x = x, .y = y}
}

// fn enable_nxe_bit() {
//     use x86::msr::{IA32_EFER, rdmsr, wrmsr};
//     let nxe_bit = 1 << 11;
//     unsafe {
//         let efer = rdmsr(IA32_EFER);
//         wrmsr(IA32_EFER, efer | nxe_bit);
//     }
// }

// fn enable_write_protect_bit() {
//     use x86::controlregs::{cr0, cr0_write};
//     let wp_bit = 1 << 16;
//     unsafe { cr0_write(cr0() | wp_bit) };
// }

export nakedcc fn zigmain(mb_header: TMultiboot_header) {
    var vram: []TEntry = undefined;
    vram.ptr = (&u16)(usize(0xB8000));
    vram.len = 65000;

    screenClear(vram, TVGAColor.Green);
    const attr = makeColor(TVGAColor.Black, TVGAColor.White);
    rainbow(vram, " ---=== Booted by GRUB ===--- ", mkTPos(10, 10));
    writeString(vram, " Hello from Zig ", attr, mkTPos(10, 11));
    writeString(vram, " A systems programming language ment to replace C, yay! ", attr, mkTPos(10, 12));
    writeString(vram, "Returning from Zig, you should see '", makeColor(TVGAColor.Black, TVGAColor.Green), mkTPos(0, 24));
    writeString(vram, "OS returned!", makeColor(TVGAColor.Red, TVGAColor.White), mkTPos(36, 24));
    writeString(vram, "' at top left.", makeColor(TVGAColor.Black, TVGAColor.Green), mkTPos(48, 24));

    return;
}
