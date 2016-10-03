// /******************************************************************************
//  *
//  * Copyright (C) 2008 Jason Evans <jasone@FreeBSD.org>.
//  * All rights reserved.
//  *
//  * Redistribution and use in source and binary forms, with or without
//  * modification, are permitted provided that the following conditions
//  * are met:
//  * 1. Redistributions of source code must retain the above copyright
//  *    notice(s), this list of conditions and the following disclaimer
//  *    unmodified other than the allowable addition of one or more
//  *    copyright notices.
//  * 2. Redistributions in binary form must reproduce the above copyright
//  *    notice(s), this list of conditions and the following disclaimer in
//  *    the documentation and/or other materials provided with the
//  *    distribution.
//  *
//  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) ``AS IS'' AND ANY
//  * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
//  * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT HOLDER(S) BE
//  * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
//  * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
//  * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
//  * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
//  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//  *
//  ******************************************************************************
//  *
//  * cpp macro implementation of left-leaning red-black trees.  All operations
//  * are done non-recursively.  Parent pointers are not used, and color bits are
//  * stored in the least significant bit of right-child pointers, thus making
//  * node linkage as compact as is possible for red-black trees.
//  *
//  * Some macros use a comparison function pointer, which is expected to have the
//  * following prototype:
//  *
//  *   int (a_cmp *)(a_type *a_node, a_type *a_other);
//  *                         ^^^^^^
//  *                      or a_key
//  *
//  * Interpretation of comparision function return values:
//  *
//  *   -1 : a_node <  a_other
//  *    0 : a_node == a_other
//  *    1 : a_node >  a_other
//  *
//  * In all cases, the a_node or a_key macro argument is the first argument to the
//  * comparison function, which makes it possible to write comparison functions
//  * that treat the first argument specially.
//  *
//  ******************************************************************************/

const std = @import("std");
const io = std.io;
const assert = std.debug.assert;

const RIGHT_SET_MASK = usize(1);
const RIGHT_GET_MASK = usize(isize(-2));

pub struct rb_node(inline T: type)
{
    const Self = rb_node(T);
    rbn_left: T,
    rbn_right_red: T,

    /// Get the left pointer
    pub inline fn left_get(n: &Self) -> T {
        return n.rbn_left;
    }

    /// Set the left pointer
    pub inline fn left_set(n: &Self, left: T) {
        n.rbn_left = left;
    }

    pub inline fn right_get(n: &Self) -> T {
        return (T)(usize(n.rbn_right_red) & RIGHT_GET_MASK);
    }

    pub inline fn right_set(n: &Self, right: T) {
        n.rbn_right_red = (T)(usize(right) | (usize(n.rbn_right_red) & RIGHT_SET_MASK));
    }

    pub inline fn red_get(n: &Self) -> bool {
        if ((usize(n.rbn_right_red) & usize(0x1)) == 1) true else false
    }

    // Color accessors. usize(false)=0, usize(true)=1
    pub inline fn color_set(n: &Self, a_red: bool) {
        //     (a_node)->a_field.rbn_right_red = (a_type *) ((((intptr_t) \
        //       (a_node)->a_field.rbn_right_red) & ((ssize_t)-2))      \
        //       | ((ssize_t)a_red));                                   \
        n.rbn_right_red = (T)((usize(n.rbn_right_red) & RIGHT_GET_MASK) | usize(a_red));
    }

    pub inline fn red_set(n: &Self) {
        // #define rbp_red_set(a_type, a_field, a_node) do {            \
        //     (a_node)->a_field.rbn_right_red = (a_type *) (((uintptr_t) \
        //     (a_node)->a_field.rbn_right_red) | ((size_t)1));         \
        n.rbn_right_red = (T)(usize(n.rbn_right_red) | RIGHT_SET_MASK);
    }

    pub inline fn black_set(n: &Self) {
        //     (a_node)->a_field.rbn_right_red = (a_type *) (((intptr_t) \
        //       (a_node)->a_field.rbn_right_red) & ((ssize_t)-2));     \
        n.rbn_right_red = (T)(usize(n.rbn_right_red) & RIGHT_GET_MASK);
    }

    // #define rbp_first(a_type, a_field, a_tree, a_root, r_node) do {		\
    //     for ((r_node) = (a_root);                                    \
    //       rbp_left_get(a_type, a_field, (r_node)) != &(a_tree)->rbt_nil; \
    //       (r_node) = rbp_left_get(a_type, a_field, (r_node))) {      \
    //     }                                                            \
    pub fn first(n: &Self, root: T, nilnode: T) -> T {
        var it = root;
        if (it == nilnode) return it;
        while (it.link.left_get() != nilnode) {
            it = it.link.left_get();
        }
        return it;
    }

    pub inline fn init(n: &Self, nilnode: T) {
        n.left_set(nilnode);
        n.right_set(nilnode);
        n.red_set();
    }
}

// #define rbp_rotate_left(a_type, a_field, a_node, r_node) do {		\
//     (r_node) = rbp_right_get(a_type, a_field, (a_node));		\
//     rbp_right_set(a_type, a_field, (a_node),	rbp_left_get(a_type, a_field, (r_node)));				\
//     rbp_left_set(a_type, a_field, (r_node), (a_node));			\
// } while (0)
pub inline fn rotate_left(n: var) -> @typeOf(n) {
    // %%io.stdout.printf("rotate_left\n");
    var rn = n.link.right_get();
    n.link.right_set(rn.link.left_get());
    rn.link.left_set(n);

    return rn;
}

// #define rbp_lean_left(a_type, a_field, a_node, r_node) do {		\
//     bool rbp_ll_red;                                                 \
//     rbp_rotate_left(a_type, a_field, (a_node), (r_node));            \
//     rbp_ll_red = rbp_red_get(a_type, a_field, (a_node));		\
//     rbp_color_set(a_type, a_field, (r_node), rbp_ll_red);            \
//     rbp_red_set(a_type, a_field, (a_node));                          \
// } while (0)
pub inline fn lean_left(n: var, rnode: var) -> @typeOf(rnode) {
    // %%io.stdout.printf("lean_left\n");
    var rr = rotate_left(n, rnode);
    rr.link.color_set(n.link.red_get());
    n.link.red_set();

    return rr;
}

// #define rbp_rotate_right(a_type, a_field, a_node, r_node) do {       \
//     (r_node) = rbp_left_get(a_type, a_field, (a_node));              \
//     rbp_left_set(a_type, a_field, (a_node), rbp_right_get(a_type, a_field, (r_node))); \
//     rbp_right_set(a_type, a_field, (r_node), (a_node));              \
// } while (0)
pub inline fn rotate_right(n: var) -> @typeOf(n) {
    // %%io.stdout.printf("rotate_right\n");
    var rn = n.link.left_get();
    n.link.left_set(rn.link.right_get());
    rn.link.right_set(n);

    return rn;
}

// Root structure.
pub struct rb_tree(inline T: type, inline eql: fn(a: &T, b: &T)->isize) {
    const Self = this;

    rbt_root: &T,

    struct path_node {
        node: &T,
        cmp: isize,
    }

    inline fn NULL_PTR(ptr: var) -> @typeOf(ptr) {
        return (@typeOf(ptr))(usize(0));
    }

    pub fn black_height(t: &Self) -> usize {
        var it = t.rbt_root;
        var sz = usize(0);
        while(it != NULL_PTR(it)) {
            if (it.link.red_get() == false) {
                sz += 1;
            }
            it = it.link.left_get();
        }

        return sz;
    }

    pub fn dump(t: &Self, n: &T) -> %void {
        if (n == NULL_PTR(n)) return;
        %%io.stdout.printInt(usize, n.example);
        %%io.stdout.printf("\n");
        var nn = n.link.left_get();
        if (nn != NULL_PTR(nn)) {
            %%t.dump(nn);
        }
        nn = n.link.right_get();
        if (nn != NULL_PTR(nn)) {
            %%t.dump(nn);
        }
    }

    pub fn first(t: &Self) -> ?&T {
        const n = t.rbt_root.link.first(t.rbt_root, NULL_PTR(t.rbt_root));
        if (n == NULL_PTR(n)) {
            return null;
        }
        return n;
    }

    pub fn init(t: &Self) {
        t.rbt_root = NULL_PTR(t.rbt_root);
    }

    pub fn insert(t: &Self, n: &T) {
        const NULL = NULL_PTR(n);
        var path: [@sizeOf(usize) << 4]path_node = zeroes;
        n.link.init(NULL);
        // Wind
        path[0].node = t.rbt_root;
        var ix = usize(0);
        while ((path[ix].node != NULL) && (ix < (path.len - 1)); ix +%= 1) {
            const cmp = eql(n, path[ix].node);
            assert(cmp != 0);
            // %%io.stdout.printInt(usize, ix);
            // %%io.stdout.printf(" <- wind, ");
            // %%io.stdout.printInt(isize, cmp);
            // %%io.stdout.printf(" cmp, ");
            path[ix].cmp = cmp;
            if (cmp < 0) {
                // %%io.stdout.printf(" left\n");
                path[ix + 1].node = path[ix].node.link.left_get();
            } else {
                // %%io.stdout.printf(" right\n");
                path[ix + 1].node = path[ix].node.link.right_get();
            }
        }
        path[ix].node = n;
        // Unwind
        // %%io.stdout.printInt(usize, ix);
        // %%io.stdout.printf(" <- before unwind\n");
        ix -%= 1;
        while (ix >= 0 && ix < path.len; ix -%= 1) {
            var cnode = path[ix].node;
            const cmp = path[ix].cmp;
            // %%io.stdout.printInt(usize, ix);
            // %%io.stdout.printf(" <- unwind, ");
            // %%io.stdout.printInt(isize, cmp);
            // %%io.stdout.printf(" cmp\n");
            if (cmp < 0) {
                var left = path[ix + 1].node;
                cnode.link.left_set(left);
                if (left.link.red_get()) {
                    var leftleft = left.link.left_get();
                    if ((leftleft != NULL) && leftleft.link.red_get()) {
                        // Fix up 4-node
                        leftleft.link.black_set();
                        var tnode = rotate_right(cnode);
                        cnode = tnode;
                    }
                } else {
                    return;
                }
            } else {
                var right = path[ix + 1].node;
                cnode.link.right_set(right);
                if (right.link.red_get()) {
                    var left = cnode.link.left_get();
                    if ((left != NULL) && left.link.red_get()) {
                        // Split 4-node.
                        left.link.black_set();
                        right.link.black_set();
                        cnode.link.red_set();
                    } else {
                        // Lean left.
                        const tred = cnode.link.red_get();
                        var tnode = rotate_left(cnode);
                        tnode.link.color_set(tred);
                        cnode.link.red_set();
                        cnode = tnode;
                    }
                } else {
                    return;
                }
            }
            path[ix].node = cnode;
        }
        // %%io.stdout.printInt(usize, ix);
        // %%io.stdout.printf(" <- after unwind");
        // %%io.stdout.printf("\n");
        if (ix >= path.len) ix +%= 1;
        t.rbt_root = path[ix].node;
        t.rbt_root.link.black_set();
    }

    pub fn search(t: &Self, n: &T) -> ?&T {
        const NULL = (&T)(usize(0));
        var ret = t.rbt_root;
        while (ret != NULL) {
            const cmp = eql(n, ret);
            if (cmp < 0) {
                ret = ret.link.left_get();
            } else if (cmp > 0) {
                ret = ret.link.right_get();
            } else {
                // we have a match
                break;
            }
        }
        return (ret);
    }
}
