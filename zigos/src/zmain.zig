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


pub const IA32_EFER: u32 = 0xc0000080;
fn rdmsr(msr: u32) -> u64 {
    var hi: u32 = 0;
    var lo: u32 = 0;
    // , [hi] "={edx}" (-> u32)
    lo = asm volatile("rdmsr" : [lo] "={eax}" (-> u32): [msr] "{ecx}" (msr) : "ecx");
    // kludge for only one output which may work
    hi = asm volatile ("movl %%edx,%[hi]" : [hi] "=r" (-> u32)); //: [high] "{edx}" (high));
    return (u64(hi) << 32) | (u64(lo));
}

fn wrmsr(msr: u32, value: u64) {
    var hi: u32 = u32(value >> 32);
    var lo: u32 = u32(value & 0xffffffff);
    // , [hi] "={edx}" (-> u32)
    asm volatile("wrmsr" :: [msr] "{ecx}" (msr), [lo] "{eax}" (lo), [hi] "{edx}" (hi));
}

fn enable_nxe_bit() {
    //use x86::msr::{IA32_EFER, rdmsr, wrmsr};

    const nxe_bit = 1 << 11;
    var msr = rdmsr(IA32_EFER);
    wrmsr(IA32_EFER, msr | nxe_bit);
}

inline fn rdtsc() -> u64 {
    var low: u32 = 0;
    var high: u32 = 0;
    // ouput in eax and edx, could probably movl edx...
    low = asm volatile ("rdtsc" : [low] "={eax}" (-> u32) : [low] "{eax}" (low));
    // high = asm volatile ("rdtsc" : [high] "={edx}" (-> u32) : [high] "{edx}" (high));
    high = asm volatile ("movl %%edx,%[high]" : [high] "=r" (-> u32)); //: [high] "{edx}" (high));
    ((u64(high) << 32) | (u64(low)))
}

inline fn cpuid(f: u32) -> u32 {
    // See: https://en.wikipedia.org/wiki/CPUID, there's a boatload of variations...
    var id: u32 = 0;
    if (f == 0) {
        return asm volatile ("cpuid" : [id] "={eax}" (-> u32): [eax] "{eax}" (f) : "ebx", "ecx", "edx");
    } else {
        return asm volatile ("cpuid" : [id] "={eax}" (-> u32): [eax] "{eax}" (f));
    }
}

// ELF 64
struct ElfSymbols {
    sectionType: u32,
    size: u32,
    num: u32,
    entsize: u32,
    shndx: u32,
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
    var cpu = cpuid(0);
    var msr = rdmsr(IA32_EFER);
    vga.init();
    vga.clearScreen(TVGAColor.Green);
    vga.writeString("cpuid:", attr, mkTPos(35, 2));
    vga.writeString("msr:", attr, mkTPos(60, 0));
    vga.writeString(umaxx2s(msr, s), attr, mkTPos(64, 0));
    vga.writeString(umaxx2s(cpu, s), attr, mkTPos(42, 2));
    if (cpu == u32(0xd)) {
        vga.writeString("IvyBridge", attr, mkTPos(62, 2));
    }
    cpu = cpuid(1);

    vga.writeString("total mbi size:", attr, mkTPos(10, 2));
    vga.writeString(umax2s(totalSize, s), attr, mkTPos(25, 2));

    //vga.writeString("cpuid:", attr, mkTPos(35, 2));
    vga.writeString(umaxx2s(cpu, s), attr, mkTPos(52, 2));
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
                var p = usize(ptr);
                var elfsyms: ElfSymbols = zeroes;
                vga.writeString("ELF", attr, mkTPos(40, 4+ u8(n % 16)));
                elfsyms.sectionType = u32(9);
                p += @sizeOf(u32);
                elfsyms.size = u32(*(&u32)(p));
                p += @sizeOf(u32);
                elfsyms.num = u32(*(&u32)(p));
                p += @sizeOf(u32);
                elfsyms.entsize = u32(*(&u32)(p));
                p += @sizeOf(u32);
                elfsyms.shndx = u32(*(&u32)(p));
                p += @sizeOf(u32);
                vga.writeString(umax2s(elfsyms.size, s), revattr, mkTPos(52, 4+ u8(n % 16)));
                vga.writeString(umax2s(elfsyms.num, s), revattr, mkTPos(57, 4+ u8(n % 16)));
                vga.writeString(umax2s(elfsyms.entsize, s), revattr, mkTPos(62, 4+ u8(n % 16)));
                vga.writeString(umax2s(elfsyms.shndx, s), revattr, mkTPos(67, 4+ u8(n % 16)));
                var shstrtab = (&SectionHeader)(p + elfsyms.shndx * @sizeOf(SectionHeader));
                var shnames: []u8 = zeroes;
                shnames.ptr = (&u8)(usize(shstrtab.addr));
                shnames.len = shstrtab.size;
                {var si = usize(0); var pi = usize(0);
                    while (si < elfsyms.num; si += 1) {
                        // Just point into the given section headers...
                        const elfsection = (&SectionHeader)(p);
                        // print the allocated sections
                        if (elfsection.flags & 0xf != 0) {
                            print(&vga, elfsection, shnames, 14 + u8(pi % 10));
                            pi += 1;
                        }
                        p += @sizeOf(SectionHeader);
                    }
                }
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

    enable_nxe_bit();
    msr =rdmsr(IA32_EFER);
    vga.writeString(umaxx2s(msr, s), attr, mkTPos(74, 0));
    vga.centered(" Hello from Zig ", attr, 0);
    vga.centered(" A systems programming language intended to replace C ", attr, 1);
    vga.writeString("Returning from Zig, you should see '", makeColor(TVGAColor.Black, TVGAColor.Cyan), mkTPos(0, 24));
    vga.writeString("OS returned!", makeColor(TVGAColor.Red, TVGAColor.White), mkTPos(36, 24));
    vga.writeString("' at top left.", makeColor(TVGAColor.Black, TVGAColor.Cyan), mkTPos(48, 24));

    return;

}

pub struct SectionHeader {
    name: u32,
    sh_type: u32,
    flags: u64,
    addr: u64,
    offset: u64,
    size: u64,
    link: u32,
    info: u32,
    addr_align: u64,
    ent_size: u64,
}
// typedef  struct
// {
// Elf64_Word sh_name;/*  Section  name  4 */
// Elf64_Word sh_type; /*  Section  type  4 */
// Elf64_Xword sh_flags; /*  Section  attributes 8 */
// Elf64_Addr sh_addr; /*  Virtual  address  in  memory 8 */
// Elf64_Off sh_offset; /*  Offset  in  file 8  */
// Elf64_Xword sh_size; /*  Size  of  section 8 */
// Elf64_Word sh_link; /*  Link  to  other  section 4 */
// Elf64_Word sh_info; /*  Miscellaneous  information 4 */
// Elf64_Xword sh_addralign; /*  Address  alignment  boundary 8 */
// Elf64_Xword sh_entsize; /*  Size  of  entries,  if  section  has  table 8 */
// }  Elf64_Shdr;

fn readElfSectionHeader(entrypoint: usize) -> SectionHeader {
    var sh: SectionHeader = zeroes;
    var ptr = entrypoint;
    sh.name =  u32(*(&u32)(ptr));
    ptr += @sizeOf(u32);
    sh.sh_type = u32(*(&u32)(ptr));
    ptr += @sizeOf(u32);
    sh.flags = u64(*(&u64)(ptr));
    ptr += @sizeOf(u64);
    sh.addr = u64(*(&u64)(ptr));
    ptr += @sizeOf(u64);
    sh.offset = u64(*(&u64)(ptr));
    ptr += @sizeOf(u64);
    sh.size = u64(*(&u64)(ptr));
    ptr += @sizeOf(u64);
    sh.link = u32(*(&u32)(ptr));
    ptr += @sizeOf(u32);
    sh.info = u32(*(&u32)(ptr));
    ptr += @sizeOf(u32);
    sh.addr_align = u64(*(&u64)(ptr));
    ptr += @sizeOf(u64);
    sh.ent_size = u64(*(&u64)(ptr));
    ptr += @sizeOf(u64);

    return sh;
}

fn print(vga: &VGA, sh: &SectionHeader, shnames: []u8, line: u8) {
    var s: [UMAX2S_BUFSIZE]u8 = zeroes;
    const color = makeColor(TVGAColor.Black, TVGAColor.Yellow);
    vga.writeString(shnames[sh.name ...], color, mkTPos(0, line));
    // vga.writeString(umax2s(sh.name, s), color, mkTPos(2, line));
    vga.writeString(umaxx2s(sh.sh_type, s), color, mkTPos(10, line));
    vga.writeString(umaxx2s(sh.flags, s), color, mkTPos(14, line));
    vga.writeString(umaxx2s(sh.addr, s), color, mkTPos(18, line));
    vga.writeString(umaxx2s(sh.offset, s), color, mkTPos(27, line));
    vga.writeString(umaxx2s(sh.size, s), color, mkTPos(36, line));
    vga.writeString(umaxx2s(sh.link, s), color, mkTPos(45, line));
    vga.writeString(umaxx2s(sh.info, s), color, mkTPos(54, line));
    vga.writeString(umax2s(sh.addr_align, s), color, mkTPos(63, line));
    vga.writeString(umax2s(sh.ent_size, s), color, mkTPos(72, line));
}
