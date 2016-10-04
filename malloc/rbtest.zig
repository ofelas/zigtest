const std = @import("std");
const io = std.io;

const rb = @import("redblack.zig");

const prt = @import("printer.zig");
const printNamedHex = prt.printNamedHex;

// Tree of extents
// typedef struct extent_node_s extent_node_t;
pub struct extent_node {
    link: rb.rb_node(&extent_node),
    // Pointer to the extent that this tree node is responsible for
    addr: usize,
    // Total region size
    size: usize,
}

pub struct example_node {
    // Linkage for the size/address-ordered tree.
    link: rb.rb_node(&example_node),
    example: usize,

    pub fn dump(n: &example_node, level: usize, w: u8) -> %void {
        if (level > 10) return;
        var b: [level + 1]u8 = zeroes;
        for (b) |*d| {
            *d = ' ';
        }
        %%io.stdout.write(b);
        %%io.stdout.writeByte(w);
        %%printNamedHex("-> level:", level, io.stdout);
        const NULL = (@typeOf(n))(usize(0));
        if (n == NULL) {
            %%io.stdout.printf("null\n");
            return;
        }
        %%io.stdout.write(b);
        %%printNamedHex("node:", usize(n), io.stdout);
        %%io.stdout.write(b);
        %%printNamedHex("example:", n.example, io.stdout);
        %%io.stdout.write(b);
        %%printNamedHex("left:", usize(n.link.rbn_left), io.stdout);
        %%io.stdout.write(b);
        %%printNamedHex("right:", usize(n.link.rbn_right_red), io.stdout);
        if (n.link.left_get() != NULL) {
            %%n.link.left_get().dump(level + 1, 'L');
        }
        if (n.link.right_get() != NULL) {
            %%n.link.right_get().dump(level + 1, 'R');
        }
    }
}

const example_tree = rb.rb_tree(example_node, ncmp);
//const extent_tree = rb.rb_tree(extent_node);

fn ncmp(a: &example_node, b: &example_node) -> isize {
    // %%std.io.stdout.printInt(usize, a.example);
    // %%std.io.stdout.write(" vs ");
    // %%std.io.stdout.printInt(usize, b.example);
    // %%std.io.stdout.printf("\n");
    if (a.example == b.example) {
        return 0;
    } else if (a.example < b.example) {
        return -1;
    } else {
        return 1;
    }
}


fn testMe() {
    @setFnTest(this, true);
    const stream = std.io.stdout;
    const assert = std.debug.assert;
    // a bit optimistic
    var x: [10000]example_node = zeroes;
    // In [3]: math.log(250000, 2)
    // Out[3]: 17.931568569324174

    var t: example_tree = zeroes;
    var it = usize(0);
    t.init();
    const upper = x.len;
    //n.link.init(&t.rbt_nil);
    //m.link.init(&t.rbt_nil);
    var sz = t.black_height();
    assert(sz == 0);
    if (var tn ?= t.first()) {
        %%stream.printf("have a first\n");
    } else {
        %%stream.printf("no first\n");
    }
    it = usize(0);
    while (it < upper; it += 1) {
        if (it & 1 == 1) {
            x[it].example = usize(@maxValue(isize)) - it;
        } else {
            x[it].example = usize(@maxValue(isize)) + it;
        }
        // add them in sequence (ascending or decending) or else it fails, spot the bug..
        x[it].example = (x.len - it);
        t.insert(&x[it]);
        if (var tn ?= t.search(&x[it])) {
            //%%stream.printf("potential match\n");
            assert(tn.example == x[it].example);
        } else {
            %%stream.printf("not found, ERROR\n");
        }
        sz = t.black_height();
        // %%stream.write("black_height:");
        // %%stream.printInt(usize, sz);
        // %%stream.printf("\n");
        //@breakpoint();
    }
    // %%t.rbt_root.dump(0, 'T');
    %%stream.printInt(usize, @sizeOf(@typeOf(t)));
    %%stream.printf("\n");
    sz = t.black_height();
    %%stream.write("black_height:");
    %%stream.printInt(usize, sz);
    %%stream.printf("\n");

    // Now try to remove the nodes
    it = usize(0);
    while (it < upper; it += 1) {
        var ii = it + usize(1);
        //%%t.rbt_root.dump(0, 'T');
        %%printNamedHex("Removing node: ", usize(&x[it]), io.stdout);
        var rn = t.search(&x[it]) ?? {
            (&example_node)(usize(0))
        };
        %%printNamedHex("Searched node: ", usize(rn), io.stdout);
        //@fence();
        %%io.stdout.printf("\n");
        assert(rn == &x[it]);
        assert(!t.empty());
        t.remove(&x[it]);
        //%%t.rbt_root.dump(0, 'T');
        //var rn = ??t.search(&x[it]);
        while (ii < upper; ii += 1) {
            rn = ??t.search(&x[ii]);
            assert(rn == &x[ii]);
        }
    }
    sz = t.black_height();
    %%stream.write("black_height:");
    %%stream.printInt(usize, sz);
    %%stream.printf("\n");
    %%t.rbt_root.dump(0, 'T');
    assert(t.empty());
}
