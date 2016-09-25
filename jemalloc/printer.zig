// -*- indent-tabs-mode: nil; -*-
pub fn hexPrintInt(inline T: type, out_buf: []u8, x: T) -> usize {
    if (T.is_signed) hexPrintSigned(T, out_buf, x) else hexPrintUnsigned(T, out_buf, x)
}

fn hexPrintSigned(inline T: type, out_buf: []u8, x: T) -> usize {
    const uint = @intType(false, T.bit_count);
    if (x < 0) {
        out_buf[0] = '-';
        return 1 + hexPrintUnsigned(uint, out_buf[1...], uint(-(x + 1)) + 1);
    } else {
        return hexPrintUnsigned(uint, out_buf, uint(x));
    }
}

const HexChars = "0123456789abcdef";

fn hexPrintUnsigned(inline T: type, out_buf: []u8, x: T) -> usize {
    var buf: [64]u8 = zeroes;
    var a = x;
    var index: usize = buf.len - 1;
    buf[index] = 0;

    while (true) {
        var val = a & 0xff;
        var nibble = val & 0x0f;
        index -= 1;
        buf[index] = HexChars[nibble];
        nibble = (val >> 4) & 0x0f;
        index -= 1;
        buf[index] = HexChars[nibble];
        a >>= 8;
        if (a == 0)
            break;
    }

    const len = buf.len - index;

    @memcpy(&out_buf[0], &buf[index], len);

    return len;
}
