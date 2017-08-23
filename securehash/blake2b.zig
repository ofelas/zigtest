// -*- indent-tabs-mode:nil; -*-
const assert = @import("std").debug.assert;
const print = @import("std").io.stdout.printf;

// === blake2b ===
// See: https://bitbucket.org/mihailp/blake2
// with license CC0 1.0 Universal

comptime { assert(Blake2bIV.len == 8); }
const Blake2bIV = []u64 { 0x6a09e667f3bcc908, 0xbb67ae8584caa73b,
                          0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
                          0x510e527fade682d1, 0x9b05688c2b3e6c1f,
                          0x1f83d9abfb41bd6b, 0x5be0cd19137e2179 };

comptime { assert(Sigma.len == 12); }
const Sigma = [][16]usize {
    []usize {  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15 },
    []usize { 14, 10,  4,  8,  9, 15, 13,  6,  1, 12,  0,  2, 11,  7,  5,  3 },
    []usize { 11,  8, 12,  0,  5,  2, 15, 13, 10, 14,  3,  6,  7,  1,  9,  4 },
    []usize {  7,  9,  3,  1, 13, 12, 11, 14,  2,  6,  5, 10,  4,  0, 15,  8 },
    []usize {  9,  0,  5,  7,  2,  4, 10, 15, 14,  1, 11, 12,  6,  8,  3, 13 },
    []usize {  2, 12,  6, 10,  0, 11,  8,  3,  4, 13,  7,  5, 15, 14,  1,  9 },
    []usize { 12,  5,  1, 15, 14, 13,  4, 10,  0,  7,  6,  3,  9,  2,  8, 11 },
    []usize { 13, 11,  7, 14, 12,  1,  3,  9,  5,  0, 15,  4,  8,  6,  2, 10 },
    []usize {  6, 15, 14,  9, 11,  3,  0,  8, 12,  2, 13,  7,  1,  4, 10,  5 },
    []usize { 10,  2,  8,  4,  7,  6,  1,  5, 15, 11,  9, 14,  3, 12, 13,  0 },
    []usize {  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15 },
    []usize { 14, 10,  4,  8,  9, 15, 13,  6,  1, 12,  0,  2, 11,  7,  5,  3 }
};

/// increment 2 u64
inline fn inc64x2(a: &[2]u64, b: u64) {
    (*a)[0] +%= b;
    if ((*a)[0] < b) {
        (*a)[1] += 1;
    }
}

/// padd buffer with zeroes
inline fn padding(a: &[128]u8, b: usize) {
    for ((*a)[b..(*a).len]) |*d| {
        *d = 0;
    }
}

/// rotate right unsigned 64 bit
inline fn ror64(x: u64, n: usize) -> u64 {
    (x >> u6(n)) | (x << u6(64 - n))
}

inline fn G (v: &[16]u64, a: usize, b: usize, c: usize, d: usize, x: u64 , y: u64)  {
    (*v)[a] = (*v)[a] +% (*v)[b] +% x;
    (*v)[d] = ror64((*v)[d] ^ (*v)[a], 32);
    (*v)[c] = (*v)[c] +% (*v)[d];
    (*v)[b] = ror64((*v)[b] ^ (*v)[c], 24);
    (*v)[a] = (*v)[a] +% (*v)[b] +% y;
    (*v)[d] = ror64((*v)[d] ^ (*v)[a], 16);
    (*v)[c] = (*v)[c] +% (*v)[d];
    (*v)[b] = ror64((*v)[b] ^ (*v)[c], 63);
}

pub const Blake2b = struct {
    const Self = this;
    hash: [8]u64,
    offset: [2]u64,
    buffer: [128]u8,
    buffer_idx: usize,
    hash_size: usize,
    key_size: usize, // strictly not needed

    // convenience
    pub fn print(b: &Self) {
        %%print("Blake2b: hash_size={}, key_size={}\n", b.hash_size, b.key_size);
        %%print("offset: {} {}\nhash\n", b.offset[0], b.offset[1]);
        for (b.hash) |value, i| {
            %%print("[{}] = {x16}\n", i, value);
        }
        %%print("buffer\n");
        for (b.buffer) |value| {
            %%print("{x2}", value);
        }
        %%print("\n");
    }

    pub fn init(hash_size: usize, key: []u8) -> Self {
        assert((hash_size >= 1) and (hash_size <= 64));
        assert((key.len  >= 0) and (key.len  <= 64));
        var b =  Blake2b {.hash = Blake2bIV,
                          .offset = []u64 {0,0},
                          .buffer = []u8 {0} ** 128,
                          .buffer_idx = 0,
                          .hash_size = hash_size,
                          .key_size = key.len};
        b.hash[0] = b.hash[0] ^ u64(0x01010000) ^ (u64(b.key_size) << 8) ^ b.hash_size;
        if (b.key_size > 0) {
            b.update(&key[0..]);
            padding(&b.buffer, b.buffer_idx);
            b.buffer_idx = 128;
        }
        b
    }

    pub fn update(b: &Self, data: &[]const u8) {
        // %%print("data.len={}\n", (*data).len);
        var i = usize(0);
        while (i < (*data).len) {
            if (b.buffer_idx == 128) {
                inc64x2(&b.offset, b.buffer_idx);
                b.compress(false);
            }
            b.buffer[b.buffer_idx] = (*data)[i];
            // %%print("idx={}, b={x2}\n", b.buffer_idx, *d);
            b.buffer_idx += 1;
            i += 1;
        }
    }
    // can we do this in zig? maybe with a comptime var?
    //proc blake2b_update*(c: var Blake2b, data: cstring|string|seq|uint8, data_size: int) =
    //   for i in 0..<data_size:
    //      if c.buffer_idx == 128:
    //         inc(c.offset, c.buffer_idx)
    //         compress(c)
    //      when data is cstring or data is string:
    //         c.buffer[c.buffer_idx] = ord(data[i])
    //      elif data is seq:
    //         c.buffer[c.buffer_idx] = data[i]
    //      else:
    //         c.buffer[c.buffer_idx] = data
    //      inc(c.buffer_idx)

    fn compress(b: &Self, last: bool){
        var input = []u64 {0} ** 16;
        var v = []u64 {0} ** 16;
        var i: usize = 0;
        while (i < 16) {
            input[i] = *(@ptrCast(&u64, &b.buffer[i * 8]));
            i += 1;
        }
        i = 0;
        while (i < 8) {
            v[i] = b.hash[i];
            v[i + 8] = Blake2bIV[i];
            i += 1;
        }
        v[12] ^= b.offset[0];
        v[13] ^= b.offset[1];
        if (last) {
            v[14] = ~v[14];
        }
        i = 0;
        while (i < 12) {
            G(&v, 0, 4,  8, 12, input[Sigma[i][0]],  input[Sigma[i][1]]);
            G(&v, 1, 5,  9, 13, input[Sigma[i][2]],  input[Sigma[i][3]]);
            G(&v, 2, 6, 10, 14, input[Sigma[i][4]],  input[Sigma[i][5]]);
            G(&v, 3, 7, 11, 15, input[Sigma[i][6]],  input[Sigma[i][7]]);
            G(&v, 0, 5, 10, 15, input[Sigma[i][8]],  input[Sigma[i][9]]);
            G(&v, 1, 6, 11, 12, input[Sigma[i][10]], input[Sigma[i][11]]);
            G(&v, 2, 7,  8, 13, input[Sigma[i][12]], input[Sigma[i][13]]);
            G(&v, 3, 4,  9, 14, input[Sigma[i][14]], input[Sigma[i][15]]);
            i += 1;
        }
        i = 0;
        while (i < 8) {
            b.hash[i] = b.hash[i] ^ v[i] ^ v[i+8];
            i += 1;
        }
        b.buffer_idx = 0;
    }

    pub fn final(b: &Self, result: &[]u8) -> usize {
        assert((*result).len >= 64);
        inc64x2(&b.offset, b.buffer_idx);
        padding(&b.buffer, b.buffer_idx);
        b.compress(true);
        var i : usize = 0;
        while (i < b.hash_size) {
            const uv = @ptrCast(&u64, &b.hash[i / 8]);
            (*result)[i] = u8((*uv >> (8 * u6(i & 7)) & 0xFF));
            // %%print("final *uv={x} bv={x}\n", *uv, bv);
            i += 1;
        }
        // maybe if/when we get it to work...zero out some member variables
        // @memset(b, @sizeof(b));
        b.hash_size
    }
};

test "inc64x2" {
    var a = []u64 {0, 0};
    inc64x2(&a, 4);
    %%print("{},{}\n", a[0], a[1]);
    assert(a[0] == 4 and a[1] == 0);
    a[0] = @maxValue(u64);
    inc64x2(&a, 4);
    %%print("{},{}\n", a[0], a[1]);
    assert(a[0] == 3 and a[1] == 1);
}

test "ror64" {
    var x: u64 = 1;
    const y: u64 = ror64(x, 3);
    const z: u64 = ror64(4, 2);
    //                        1         2         3         4         5         6
    //              0123456789012345678901234567890123456789012345678901234567890123
    const a = u64(0b0010000000000000000000000000000000000000000000000000000000000000);
    assert(y == a);
    assert(x == z);
    // %%print("\nx={x016}\ny={x016}\nz={x016}\na={x016}\n", x, y, z, a);
}

test "Sigma"
{
    %%print("Sigma.len = {}\n", Sigma.len);
    assert(Sigma.len == 12);
    assert(Sigma[0].len == 16);
    assert(Sigma[0].len == Sigma[11].len);
    var ix = usize(1);
    while (ix < Sigma.len) {
        assert(Sigma[ix].len == Sigma[ix - 1].len);
        ix += 1;
    }
    for (Sigma) |value, i| {
        %%print("Sigma[{d2}].len = {} |", i, value.len);
        for (value) |vvalue| {
            %%print(" {}", vvalue);
        }
        %%print("\n");
    }
}

test "Blake2bIV"
{
    assert(Blake2bIV.len == 8);
    for (Blake2bIV) |value, i| {
        %%print("[{d}] = {x}\n", i, value);
    }
}

test "Blake2b"
{
    //assert(getBlake2b("abc", 4, "abc") == "b8f97209")
    for (Blake2bIV) |value, ii| {
        %%print("Blake2bIV 1 [{d}] = {x}\n", ii, value);
    }
    var data = "abc";
    var output: [64]u8 = undefined;
    var b = Blake2b.init(4, data[0..]);
    b.update(&data[0..]);
    b.print();
    const l = b.final(&output[0..]);
    assert(l == 4);
    %%print("output.len={}, l={}\n", output.len, l);
    assert(output[0] == 0xb8);
    assert(output[1] == 0xf9);
    assert(output[2] == 0x72);
    assert(output[3] == 0x09);
    {var i = usize(0);
        while (i < l) {
            %%print("[{d}] = 0x{x2}\n", i, output[i]);
            i += 1;
        }
    }
    b.print();
}

pub fn main() -> %void {
    var data = "abc";
    var output: [64]u8 = undefined;
    var b = Blake2b.init(4, data[0..]);
    b.update(&data[0..]);
    b.print();
    const l = b.final(&output[0..]);
    assert(l == 4);
    %%print("output.len={}, l={}\n", output.len, l);
    assert(output[0] == 0xb8);
    assert(output[1] == 0xf9);
    assert(output[2] == 0x72);
    assert(output[3] == 0x09);
    {var i = usize(0);
        while (i < l) {
            %%print("[{d}] = 0x{x2}\n", i, output[i]);
            i += 1;
        }
    }
    b.print();
}
