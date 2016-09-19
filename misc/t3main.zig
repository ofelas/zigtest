// -*- mode:zig; -*-
const io = @import("std").io;

const t3 = @import("t3.zig");
const update = t3.update;

const buildtype = if (@compileVar("is_release")) "Release" else "Debug";

pub fn main(args: [][]u8) -> %void {
    var iable = []u32{1, 2, 3, 4, 5};
    var data = []u32{1,2,3,4,5,6,7,8,9,10,11};
    var names = "abcde";
    %%io.stdout.printf(buildtype ++ "\n");
    update(iable, data);
    for (iable) |v, i| {
        %%io.stdout.write("iable[");
        %%io.stdout.writeByte(names[i]);
        %%io.stdout.writeByte(',');
        %%io.stdout.printInt(usize, i);
        %%io.stdout.write("]=");
        %%io.stdout.printInt(u32, v);
        %%io.stdout.printf("\n");
    }
}
