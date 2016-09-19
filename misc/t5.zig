// -*- mode: zig; indent-tabs-mode: nil; -*-
const io = @import("std").io;

const buildtype = if (@compileVar("is_release")) "Release" else "Debug";

// Debug
// after upd  3: 12,5,2,
// after upd  3: 39,15,6,
// final iable : 39,15,6,
// final data  : 2,1,1,
// rc=0
// after upd  3: 12,5,2,
// after upd  3: 15,7,4,
// iable[0]? 2 != 39
// iable[1]? 2 != 15
// iable[2]? 2 != 6
// final iable : 2,7,4,
// final data  : 2,1,1,


// BUG?
// remove    3 and all is well in this test!
//           |
fn mixup(v: [3]u32, y: []u32) {
    // we will only change 2 of these
    var a = v[0];
    var b = v[1];
    const c = v[2];

    var ix = usize(0);

    while (ix < 2; ix += 1) {
        var t1 = y[y.len - 1] +% b; // t = 1
        y[0] = y[y.len - 1] +% 1; // y[0] should be 2
        v[0] +%= t1; // add 1 to v[0]
    }

    // if (y[0] != 2) { @breakpoint(); }

    // need this second loop (1 iteration or more)
    while (ix < 4; ix += 1) {
        var t2 = c + 1; // 1 + 1
        t2 +%= (b ^ c) +% c +% y[y.len - 1];
        // update a, b
        b +%= y[ix % y.len];
        a = (t2 <<% 1) >> 1; // a = t
    }

    v[0] +%= a;
    v[1] +%= b;
    v[2] +%= c; // c should be unchanged

    // BUG?
    // comment out this and it works with [3]u32 in the function signature?
    // with []u32 this seem to have no effect, i.e. works
    // getting a bit dizzy with all the tested permutations...
    %%io.stdout.write("after upd  3: ");
    for (v) |vv, i| {
        %%io.stdout.printInt(u32, vv);
        %%io.stdout.write(",");
    } %%io.stdout.printf("\n");
}


fn update(v: [3]u32, w:[]u32) {
    mixup(v, w);
    for (v) |*p, i| {
        *p +%= 1; // add 1 to all
    }
    mixup(v, w);
}

#static_eval_enable(false)
fn check_that(inline T: type, x: T, y: T, msg: []u8) -> %void {
    if (x != y) {
        %%io.stderr.write(msg);
        %%io.stderr.printInt(T, x);
        %%io.stderr.write(" != ");
        %%io.stderr.printInt(T, y);
        %%io.stderr.printf("\n");
    }
}

pub fn main(args: [][]u8) -> %void {
    // TODO array container init, e.g. [3]u32
    var data =  []u32{1, 1, 1};
    var iable = []u32{1, 1, 1};

    %%io.stdout.write(buildtype ++ "\n");
    update(iable, data);

    // BUG? when it fails, check_that always reports 2 != (for release)
    %%check_that(u32, iable[0], 39, "iable[0]? ");
    %%check_that(u32, iable[1], 15, "iable[1]? ");
    %%check_that(u32, iable[2], 6, "iable[2]? ");

    %%io.stdout.write("final iable : ");
    for (iable) |v, i| {
        %%io.stdout.printInt(u32, v);
        %%io.stdout.write(",");
    }
    %%io.stdout.printf("\n");
    %%io.stdout.write("final data  : ");
    for (data) |v, i| {
        %%io.stdout.printInt(u32, v);
        %%io.stdout.write(",");
    }
    %%io.stdout.printf("\n");
}
