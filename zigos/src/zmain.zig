const vgaCtrl = @import("vgaController.zig");
const makeColor = vgaCtrl.makeColor;
const TPos = vgaCtrl.TPos;
const TVGAColor = vgaCtrl.TVGAColor;
const VGA = vgaCtrl.VGA;

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
    var vga: VGA = undefined;
    const attr = makeColor(TVGAColor.Black, TVGAColor.White);

    vga.init();

    vga.clearScreen(TVGAColor.Green);

    vga.rainbow(" ---=== Booted by GRUB ===--- ", mkTPos(10, 10));
    vga.writeString(" Hello from Zig ", attr, mkTPos(10, 11));
    vga.writeString(" A systems programming language ment to replace C, yay! ", attr, mkTPos(10, 12));
    vga.writeString("Returning from Zig, you should see '", makeColor(TVGAColor.Black, TVGAColor.Cyan), mkTPos(0, 24));
    vga.writeString("OS returned!", makeColor(TVGAColor.Red, TVGAColor.White), mkTPos(36, 24));
    vga.writeString("' at top left.", makeColor(TVGAColor.Black, TVGAColor.Cyan), mkTPos(48, 24));

    return;
}
