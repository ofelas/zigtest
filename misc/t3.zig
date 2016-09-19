// -*- mode:zig; -*-

// NOTE 1: remove the 5 in [5] and it works... (or do NOTE 2 or 3)
fn mixup(v: [5]u32, y: []u32) {
   var a = v[0];
   var b = v[1];
   var c = v[2];
   var d = v[3];
   var e = v[4];

   var ix = usize(0);

   // NOTE 2: ix < 4 or more fails (1,2,3 works)
   while (ix < 4; ix += 1) {
       var t = y[ix % y.len];
       y[ix % y.len] = y[(ix + 3) % y.len];
       v[ix % v.len] +%= u32(ix) <<% 3;
       e +%= d +% y[ix % y.len];
   }

   while (ix < 7; ix += 1) {
       var t = b +% 5;
       b = a +% y[ix % y.len];
       a = (t <<% 11) >> 3;
   }

   v[0] +%= a;
   v[1] +%= b;
   v[2] +%= c;
   v[3] +%= d;
   v[4] +%= e;
}

pub fn update(v: [5]u32, w:[]u32) {
    mixup(v, w);
    // NOTE 3: comment out this for loop and it works with [5] NOTE 1 and 2
    for (v) |*p, i| {
            *p +%= 1;
    }
    mixup(v, w);
}
