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

const UMAX2S_BUFSIZE = 33;
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
    const revattr = makeColor(TVGAColor.White, TVGAColor.Black);
    var s: [17]u8 = zeroes;
    // args[1] is reserved and should be 0-zero
    var args: []u32 = undefined;
    args.ptr = (&u32)(usize(argbase));
    args.len = 1;

    const totalSize = usize(args[0]);
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
            const step = usize(*(&u32)(usize(ptr) + 4));
            vga.writeString(umax2s(n, s), attr, mkTPos(1, 4 + u8(n % 16)));
            vga.writeString(umaxx2s(tag, s), attr, mkTPos(4, 4 + u8(n % 16)));
            vga.writeString(umaxx2s(step, s), attr, mkTPos(14, 4 + u8(n % 16)));
            vga.writeString(umaxx2s(usize(ptr), s), attr, mkTPos(24, 4 + u8(n % 16)));
            if (tag == u32(1)) {
                vga.writeString("CMD line", attr, mkTPos(40, 4+ u8(n % 16)));
                var ss: [step]u8 = undefined;
                ss.ptr = (&u8)(usize(ptr) + 8);
                vga.writeString(ss, attr, mkTPos(48, 4+ u8(n % 16)));
            } else if (tag == u32(2)) {
                vga.writeString("Name:", attr, mkTPos(40, 4+ u8(n % 16)));
                var ss: [step]u8 = undefined;
                ss.ptr = (&u8)(usize(ptr) + 8);
                vga.writeString(ss, revattr, mkTPos(45, 4+ u8(n % 16)));
            } else if (tag == u32(4)) {
                vga.writeString("Basic meminfo", attr, mkTPos(40, 4+ u8(n % 16)));
                const memLower = usize(*(&u32)(usize(ptr) + 8));
                const memUpper = usize(*(&u32)(usize(ptr) + 12));
                vga.writeString(umax2s(memLower, s), revattr, mkTPos(56, 4+ u8(n % 16)));
                vga.writeString(umax2s(memUpper, s), revattr, mkTPos(66, 4+ u8(n % 16)));
            } else if (tag == u32(5)) {
                vga.writeString("Boot dev", attr, mkTPos(40, 4+ u8(n % 16)));
                const biosDev = usize(*(&u32)(usize(ptr) + 8));
                const partition = usize(*(&u32)(usize(ptr) + 12));
                vga.writeString(umaxx2s(biosDev, s), revattr, mkTPos(56, 4+ u8(n % 16)));
                vga.writeString(umaxx2s(partition, s), revattr, mkTPos(66, 4+ u8(n % 16)));
            } else if (tag == u32(6)) {
                vga.writeString("mmap", attr, mkTPos(40, 4+ u8(n % 16)));
                const entrySize = usize(*(&u32)(usize(ptr) + 8));
                const firstBase = usize(*(&u64)(usize(ptr) + 16));
                const firstLength = usize(*(&u64)(usize(ptr) + 24));
                const entries = step / entrySize;
                vga.writeString(umax2s(entries, s), revattr, mkTPos(46, 4+ u8(n % 16)));
                vga.writeString(umax2s(entrySize, s), revattr, mkTPos(56, 4+ u8(n % 16)));
                vga.writeString(umaxx2s(firstLength, s), revattr, mkTPos(66, 4+ u8(n % 16)));
                // vga.writeString(umax2s(entrySize, s), revattr, mkTPos(66, 4+ u8(n % 16)));
            } else if (tag == u32(8)) {
                vga.writeString("Alignment", attr, mkTPos(40, 4+ u8(n % 16)));
            } else if (tag == u32(9)) {
                vga.writeString("ELF sections", attr, mkTPos(40, 4+ u8(n % 16)));
                const num = usize(*(&u16)(usize(ptr) + 8));
                const entrySize = usize(*(&u16)(usize(ptr) + 10));
                vga.writeString(umax2s(num, s), revattr, mkTPos(56, 4+ u8(n % 16)));
                vga.writeString(umax2s(entrySize, s), revattr, mkTPos(66, 4+ u8(n % 16)));
            } else if (tag == u32(10)) {
                vga.writeString("APM", attr, mkTPos(40, 4 + u8(n % 16)));
            } else if (tag == u32(14)) {
                vga.writeString("ACPI (old)", attr, mkTPos(40, 4 + u8(n % 16)));
            } else if (tag == u32(0)) {
                // end tag
                vga.writeString("*End*", attr, mkTPos(40, 4 + u8(n % 16)));
                break;
            }
            i += step;
            ptr = (&u8)(usize(ptr) + step);
            ptr = (&u8)(((usize(ptr) - usize(1)) & ~usize(7)) + usize(8));
            if (i >= totalSize) {
                break;
            }
            // need interrupt handling for this (I guess)...
            //@breakpoint();
        }
        vga.writeString(umaxx2s(usize(ptr), s), attr, mkTPos(20, 3));
    }


    vga.writeString(" Hello from Zig ", attr, mkTPos(10, 18));
    vga.writeString(" A systems programming language ment to replace C, yay! ", attr, mkTPos(10, 19));
    vga.writeString("Returning from Zig, you should see '", makeColor(TVGAColor.Black, TVGAColor.Cyan), mkTPos(0, 24));
    vga.writeString("OS returned!", makeColor(TVGAColor.Red, TVGAColor.White), mkTPos(36, 24));
    vga.writeString("' at top left.", makeColor(TVGAColor.Black, TVGAColor.Cyan), mkTPos(48, 24));

    return;

}
