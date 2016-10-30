const vgaCtrl = @import("vgaController.zig");
const makeColor = vgaCtrl.makeColor;
const TPos = vgaCtrl.TPos;
const TVGAColor = vgaCtrl.TVGAColor;
const VGA = vgaCtrl.VGA;

const MultibootBaseheader = &u32;
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

const UMAX2S_BUFSIZE = 21;
fn umax2s(v: var, s: []u8) -> []u8{
    var i = s.len - 1;
    var x = v;
    s[i] = 0;
    while (true) {
        i -= 1;
        s[i] = "0123456789"[x % 10];
        x /= 10;
        if (x == 0) break;
    }
    return s[i...];
}

fn umaxx2s(v: var, s: []u8) -> []u8{
    var i = s.len - 1;
    var x = v;
    s[i] = 0;
    while (true) {
        i -= 1;
        s[i] = "0123456789abcdef"[x % 16];
        x /= 16;
        if (x == 0) break;
    }
    return s[i...];
}

var argp: usize = undefined;

// Should get pointer to multiboot header in "edi" register
export nakedcc fn zigmain() {
    argp = asm("mov %%rdi, %[argp]": [argp] "=r" (-> usize));
    zmain((&u8)(argp));
}

// We should have the multiboot information in arg
fn zmain(argbase: &u8) {
    var vga: VGA = undefined;
    const attr = makeColor(TVGAColor.Black, TVGAColor.White);
    var s: [17]u8 = zeroes;
    // args[1] is reserved and should be 0-zero
    var args: []u32 = undefined;
    args.ptr = (&u32)(usize(argbase));
    args.len = 1;

    const totalSize = args[0];
    vga.init();
    vga.clearScreen(TVGAColor.Green);

    vga.writeString("total mbi size:", attr, mkTPos(10, 2));
    vga.writeString(umax2s(totalSize, s), attr, mkTPos(25, 2));
    args.len = totalSize >> 2;
    {
        var ptr: &u8 = (&u8)(usize(argbase) + 8);
        var i = usize(0);
        var n = usize(0);
        while (i < totalSize; n += 1) {
            const tag = *(&u32)(usize(ptr));
            const step = *(&u32)(usize(ptr) + 4);
            vga.writeString(umax2s(i, s), attr, mkTPos(10, 3 + u8(n % 10)));
            vga.writeString(umaxx2s(tag, s), attr, mkTPos(20, 3 + u8(n % 10)));
            vga.writeString(umaxx2s(step, s), attr, mkTPos(30, 3 + u8(n % 10)));
            vga.writeString(umaxx2s(usize(ptr), s), attr, mkTPos(50, 3 + u8(n % 10)));
            if (tag == u32(2)) {
                vga.writeString("Bootloader name present", attr, mkTPos(10, 16));
            } else if (tag == u32(0)) {
                // end tag
                break;
            }
            i += step;
            ptr = (&u8)(usize(ptr) + usize(step));
            ptr = (&u8)(((usize(ptr) - usize(1)) & ~usize(7)) + usize(8));
            if (i >= totalSize) {
                break;
            }
            // need interrupt handling for this (I guess)...
            //@breakpoint();
        }
        vga.writeString(umax2s(i, s), attr, mkTPos(20, 3));
    }


    vga.writeString(" Hello from Zig ", attr, mkTPos(10, 18));
    vga.writeString(" A systems programming language ment to replace C, yay! ", attr, mkTPos(10, 19));
    vga.writeString("Returning from Zig, you should see '", makeColor(TVGAColor.Black, TVGAColor.Cyan), mkTPos(0, 24));
    vga.writeString("OS returned!", makeColor(TVGAColor.Red, TVGAColor.White), mkTPos(36, 24));
    vga.writeString("' at top left.", makeColor(TVGAColor.Black, TVGAColor.Cyan), mkTPos(48, 24));

    return;

}
