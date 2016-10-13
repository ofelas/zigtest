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

const prt = @import("printer.zig");
const printNamedHex = prt.printNamedHex;

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

    pub inline fn init(n: &Self) {
        assert(usize(n) & 0x1 == 0);
        n.left_set((T)(usize(0)));
        n.right_set((T)(usize(0)));
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
    pub s: stats,

    struct path_node {
        node: &T,
        cmp: isize,
    }

    struct stats {
        remne: usize,
        remeq: usize,
        nofix: usize,
        reend: usize,
        single: usize,
        eqleft: usize,
        eqsingle: usize,
        loop: usize,
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

    pub fn dumpstats(t: &Self, stream: io.OutStream) -> %void {
        %%printNamedHex("remeq=", t.s.remeq, stream);
        %%printNamedHex("remne=", t.s.remne, stream);
        %%printNamedHex("nofix=", t.s.nofix, stream);
        %%printNamedHex("reend=", t.s.reend, stream);
        %%printNamedHex("single=", t.s.single, stream);
        %%printNamedHex("eqleft=", t.s.eqleft, stream);
        %%printNamedHex("eqsingle=", t.s.eqsingle, stream);
        %%printNamedHex("loop=", t.s.loop, stream);
    }

    pub fn dump(t: &Self, n: &T) -> %void {
        if (n == NULL_PTR(n)) return;
        //%%io.stdout.printInt(usize, n.example);
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

    pub fn last(t: &Self) -> ?&T {
        return null;            // TODO
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
        t.s = stats{.remne = 0, .remeq = 0, .nofix = 0, .single = 0, .reend = 0,
                    .eqleft = 0, .eqsingle = 0, .loop = 0};
    }

    pub inline fn empty(t: &Self) -> bool {
        if (t.rbt_root == (&T)(usize(0))) true else false
    }

    pub fn insert(t: &Self, n: &T) {
        const NULL = NULL_PTR(n);
        var path: [@sizeOf(usize) << 4]path_node = zeroes;
        n.link.init();
        // Wind
        path[0].node = t.rbt_root;
        var ix = usize(0);
        //  && (ix < (path.len - 1))
        while ((path[ix].node != NULL)) {
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
            ix += 1
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
        return ret;
    }

    pub fn nsearch(t: &Self, key: &T) -> ?&T {
        const NULL = (&T)(usize(0));
        var ret = NULL;
        var tnode = t.rbt_root;
        while (tnode != NULL) {
            const cmp = eql(key, tnode);
            if (cmp < 0) {
                ret = tnode;
                tnode = tnode.link.left_get();
            } else if (cmp > 0) {
                tnode = tnode.link.right_get();
            } else {
                ret = tnode;
                break;
            }
        }
        return ret;
    }

    pub fn psearch(t: &Self, key: &T) -> ?&T {
        const NULL = (&T)(usize(0));
        var ret = NULL;
        var tnode = t.rbt_root;
        while (tnode != NULL) {
            const cmp = eql(key, tnode);
            if (cmp < 0) {
                tnode = tnode.link.left_get();
            } else if (cmp > 0) {
                ret = tnode;
                tnode = tnode.link.right_get();
            } else {
                ret = tnode;
                break;
            }
        }
        return ret;
    }

    pub fn remove(t: &Self, node: &T) {
        const NULL = (&T)(usize(0));
        var path: [@sizeOf(usize) << 4]path_node = zeroes; // this should set all to zero/null
        var nodep = (&path_node)(usize(0));
        var pathp = &path[0];
        // *pathp, *nodep
        // Wind.
        //nodep = NULL; Silence compiler warning.
        var ix = usize(0);
        var nix = usize(0);
        if (t.rbt_root == NULL) return; // we get the root messed up...
        path[ix].node = t.rbt_root;
        //%%printNamedHex("root=", usize(t.rbt_root), io.stdout);
        // for (pathp = path; pathp->node != NULL; pathp++)
        // (ix < (path.len - 1)) && 
        while ((path[ix].node != NULL)) {
            const cmp = eql(node, path[ix].node);
            path[ix].cmp = cmp;
            if (cmp < 0) {
                path[ix + 1].node = path[ix].node.link.left_get();
            } else {
                path[ix + 1].node = path[ix].node.link.right_get();
                if (cmp == 0) {
                    // Find node's successor, in preparation for swap.
                    path[ix].cmp = 1;
                    nodep = &path[ix];
                    nix = ix;
                    ix += 1;
                    // for (pathp++; pathp->node != NULL; pathp++)
                    //  && (ix < (path.len - 1))
                    pathp = &path[ix];
                    while ((path[ix].node != NULL)) {
                        // %%printNamedHex("ix=", ix, io.stdout);
                        // %%printNamedHex("path=", usize(path[ix].node), io.stdout);
                        path[ix].cmp = -1;
                        path[ix + 1].node = path[ix].node.link.left_get();
                        ix += 1;
                        pathp = &path[ix];
                    }
                    break;
                }
            }
            ix += 1;
            pathp = &path[ix];
        }
        // %%printNamedHex("path.len=", usize(path.len), io.stdout);
        // %%printNamedHex("ix=", ix, io.stdout);
        // %%printNamedHex("nodep=", usize(nodep), io.stdout);
        // %%printNamedHex("path=", usize(&path[0]), io.stdout);
        // %%printNamedHex("nodep.node=", usize(nodep.node), io.stdout);
        // %%printNamedHex("node=", usize(node), io.stdout);

        // it must have been found
        //%%printNamedHex("ix=", ix, io.stdout);
        assert(nodep.node == node);

        // pathp--;
        ix -%= 1;
        // %%printNamedHex("ix=", ix, io.stdout);
        if (path[ix].node != node) {
            // %%io.stdout.printf("path[ix].node != node\n");
            // %%printNamedHex("nodep=", usize(nodep.node), io.stdout);
            t.s.remne += 1;
            // Swap node with its successor.
            //     bool tred = rbtn_red_get(a_type, a_field, pathp->node);
            const tred = path[ix].node.link.red_get();
            //     rbtn_color_set(a_type, a_field, pathp->node, rbtn_red_get(a_type, a_field, node));
            //     rbtn_left_set(a_type, a_field, pathp->node, rbtn_left_get(a_type, a_field, node));
            path[ix].node.link.color_set(node.link.red_get());
            path[ix].node.link.left_set(node.link.left_get());
            // If node's successor is its right child, the following code
            // will do the wrong thing for the right child pointer.
            // However, it doesn't matter, because the pointer will be
            // properly set when the successor is pruned.
            //     rbtn_right_set(a_type, a_field, pathp->node, rbtn_right_get(a_type, a_field, node));
            //     rbtn_color_set(a_type, a_field, node, tred);
            path[ix].node.link.right_set(node.link.right_get());
            node.link.color_set(tred);
            // The pruned leaf node's child pointers are never accessed
            // again, so don't bother setting them to nil.
            //     nodep->node = pathp->node;
            //     pathp->node = node;
            nodep.node = path[ix].node;
            path[ix].node = node;
            if (nodep == &path[0]) {
                //%%io.stdout.printf("nodep == &path[ix]\n");
                t.rbt_root = nodep.node;
            } else {
                // need to track index of nodep
                if (path[ix - 1].cmp < 0) {
                    // rbtn_left_set(a_type, a_field, nodep[-1].node, nodep.node);
                    path[ix - 1].node.link.left_set(nodep.node);
                } else {
                    // rbtn_right_set(a_type, a_field, nodep[-1].node, nodep.node);
                    path[ix - 1].node.link.right_set(nodep.node);
                }
            }
        } else {
            //%%io.stdout.printf("path[ix].node == node\n");
            t.s.remeq += 1;
            //     a_type *left = rbtn_left_get(a_type, a_field, node);
            var left = node.link.left_get();
            if (left != NULL) {
                // node has no successor, but it has a left child.
                // Splice node out, without losing the left child.
                //         assert(!rbtn_red_get(a_type, a_field, node));
                //         assert(rbtn_red_get(a_type, a_field, left));
                assert(!node.link.red_get());
                assert(left.link.red_get());
                left.link.black_set();
                if (ix == 0) {
                    t.rbt_root = left;
                } else {
                    if (path[ix - 1].cmp < 0) {
                        path[ix - 1].node.link.left_set(left);
                    } else {
                        path[ix - 1].node.link.right_set(left);
                    }
                }
                t.s.eqleft += 1;
                return;
            } else if (ix == 0) {
                // The tree only contained one node.
                t.rbt_root = NULL;
                t.s.eqsingle += 1;
                return;
            }
        }
        if (path[ix].node.link.red_get()) {
            // Prune red node, which requires no fixup.
            //%%printNamedHex("path[ix]=", usize(path[ix].node.link.rbn_right_red), io.stdout);
            t.s.nofix += 1;
            //%%io.stdout.printf("Prune red node, which requires no fixup\n");
            assert(path[ix - 1].cmp < 0);
            // var it = usize(0);
            // while (it < ix + 3; it += 1) {
            //     %%printNamedHex("path=", usize(path[it].node), io.stdout);
            // }
            //%%t.dumpstats(io.stdout);
            path[ix - 1].node.link.left_set(NULL);
            //%%t.rbt_root.dump(0, 'T');
            return;
        }
        // The node to be pruned is black, so unwind until balance is
        // restored.
        path[ix].node = NULL;
        ix -%= 1;
        // for (pathp--; (uintptr_t)pathp >= (uintptr_t)path; pathp--) {
        t.s.loop += 1;
        while ((ix >= 0) && (ix < (path.len - 1)) && (path[ix].node != NULL); ix -%= 1) {
            assert(path[ix].cmp != 0);
            if (path[ix].cmp < 0) {
                // rbtn_left_set(a_type, a_field, pathp->node, pathp[1].node);
                path[ix].node.link.left_set(path[ix + 1].node);
                if (path[ix].node.link.red_get()) {
                    // a_type *right = rbtn_right_get(a_type, a_field, pathp->node);
                    // a_type *rightleft = rbtn_left_get(a_type, a_field,  right);
                    // a_type *tnode;
                    var right = path[ix].node;
                    var rightleft = right.link.left_get();
                    var tnode = NULL;
                    if ((rightleft != NULL) && rightleft.link.red_get()) {
                        // In the following diagrams, ||, //, and \
                        // indicate the path to the removed node.
                        //
                        //      ||
                        //    pathp(r)
                        //  //       \
                        // (b)        (b)
                        //           /
                        //          (r)
                        //
                        // rbtn_black_set(a_type, a_field, pathp->node);
                        // rbtn_rotate_right(a_type, a_field, right, tnode);
                        // rbtn_right_set(a_type, a_field, pathp->node, tnode);
                        // rbtn_rotate_left(a_type, a_field, pathp->node, tnode);
                        path[ix].node.link.black_set();
                        tnode = rotate_right(right);
                        path[ix].node.link.right_set(tnode);
                        tnode = rotate_left(path[ix].node);
                    } else {
                        //      ||
                        //    pathp(r)
                        //  //        \
                        // (b)        (b)
                        //           /
                        //          (b)
                        //
                        // rbtn_rotate_left(a_type, a_field, pathp->node, tnode);
                        tnode = rotate_left(path[ix].node);
                    }
                    // Balance restored, but rotation modified subtree root.
                    // assert((uintptr_t)pathp > (uintptr_t)path);
                    assert(ix > 0);
                    if (path[ix - 1].cmp < 0) {
                        // rbtn_left_set(a_type, a_field, pathp[-1].node, tnode);
                        path[ix - 1].node.link.left_set(tnode);
                    } else {
                        // rbtn_right_set(a_type, a_field, pathp[-1].node, tnode);
                        path[ix - 1].node.link.right_set(tnode);
                    }
                    return;
                } else {
                    // a_type *right = rbtn_right_get(a_type, a_field, pathp->node);
                    // a_type *rightleft = rbtn_left_get(a_type, a_field, right);
                    var right = path[ix].node.link.right_get();
                    var rightleft = right.link.left_get();
                    // if (rightleft != NULL && rbtn_red_get(a_type, a_field, rightleft)) {
                    if ((rightleft != NULL) && rightleft.link.red_get()) {
                        //      ||
                        //    pathp(b)
                        //  //        \
                        // (b)        (b)
                        //           /
                        //          (r)
                        // a_type *tnode;
                        // rbtn_black_set(a_type, a_field, rightleft);
                        // rbtn_rotate_right(a_type, a_field, right, tnode);
                        // rbtn_right_set(a_type, a_field, pathp->node, tnode);
                        // rbtn_rotate_left(a_type, a_field, pathp->node, tnode);
                        rightleft.link.black_set();
                        var tnode = rotate_right(right);
                        path[ix].node.link.right_set(tnode);
                        tnode = rotate_left(path[ix].node);
                        // Balance restored, but rotation modified
                        // subtree root, which may actually be the
                        // tree root.
                        // if (pathp == path) {
                        if (ix == 0) {
                            // Set root.
                            t.rbt_root = tnode;
                        } else {
                            if (path[ix - 1].cmp < 0) {
                                //rbtn_left_set(a_type, a_field, pathp[-1].node, tnode);
                                path[ix - 1].node.link.left_set(tnode);
                            } else {
                                //rbtn_right_set(a_type, a_field, pathp[-1].node, tnode);
                                path[ix - 1].node.link.right_set(tnode);
                            }
                        }
                        return;
                    } else {
                        //      ||
                        //    pathp(b)
                        //  //        \
                        // (b)        (b)
                        //           /
                        //          (b)
                        // a_type *tnode;
                        // rbtn_red_set(a_type, a_field, pathp->node);
                        // rbtn_rotate_left(a_type, a_field, pathp->node, tnode);
                        // pathp->node = tnode;
                        path[ix].node.link.red_set();
                        var tnode = rotate_left(path[ix].node);
                        path[ix].node = tnode;
                    }
                }
            } else {
                // a_type *left;
                // rbtn_right_set(a_type, a_field, pathp->node,
                //                pathp[1].node);
                // left = rbtn_left_get(a_type, a_field, pathp->node);
                path[ix].node.link.right_set(path[ix + 1].node);
                var left = path[ix].node.link.left_get();
                // if (rbtn_red_get(a_type, a_field, left)) {
                if (left.link.red_get()) {
                    // a_type *tnode;
                    var tnode = NULL;
                    // a_type *leftright = rbtn_right_get(a_type, a_field, left);
                    // a_type *leftrightleft = rbtn_left_get(a_type, a_field, leftright);
                    var leftright = left.link.right_get();
                    var leftrightleft = leftright.link.left_get();
                    // if (leftrightleft != NULL && rbtn_red_get(a_type, a_field, leftrightleft)) {
                    if ((leftrightleft != NULL) && (leftrightleft.link.red_get())) {
                        //      ||
                        //    pathp(b)
                        //   /        \\
                        // (r)        (b)
                        //   \
                        //   (b)
                        //   /
                        // (r)
                        // a_type *unode;
                        // rbtn_black_set(a_type, a_field, leftrightleft);
                        // rbtn_rotate_right(a_type, a_field, pathp->node, unode);
                        // rbtn_rotate_right(a_type, a_field, pathp->node, tnode);
                        // rbtn_right_set(a_type, a_field, unode, tnode);
                        // rbtn_rotate_left(a_type, a_field, unode, tnode);
                        leftrightleft.link.black_set();
                        var unode = rotate_right(path[ix].node);
                        tnode = rotate_right(path[ix].node);
                        unode.link.right_set(tnode);
                        tnode = rotate_left(unode);
                    } else {
                        //      ||
                        //    pathp(b)
                        //   /        \\
                        // (r)        (b)
                        //   \
                        //   (b)
                        //   /
                        // (b)
                        assert(leftright != NULL);
                        // rbtn_red_set(a_type, a_field, leftright);
                        // rbtn_rotate_right(a_type, a_field, pathp->node, tnode);
                        // rbtn_black_set(a_type, a_field, tnode);
                        leftright.link.red_set();
                        tnode = rotate_right(path[ix].node);
                        tnode.link.black_set();
                    }
                    // Balance restored, but rotation modified subtree
                    // root, which may actually be the tree root.
                    // if (pathp == path) {
                    if (ix == 0) {
                        // Set root.
                        t.rbt_root = tnode;
                    } else {
                        if (path[ix - 1].cmp < 0) {
                            // rbtn_left_set(a_type, a_field, pathp[-1].node, tnode);
                            path[ix - 1].node.link.left_set(tnode);
                        } else {
                            // rbtn_right_set(a_type, a_field, pathp[-1].node, tnode);
                            path[ix - 1].node.link.right_set(tnode);
                        }
                    }
                    return;
                    // } else if (rbtn_red_get(a_type, a_field, pathp->node)) {
                } else if (path[ix].node.link.red_get()) {
                    // a_type *leftleft = rbtn_left_get(a_type, a_field, left);
                    var leftleft = left.link.left_get();
                    if ((leftleft != NULL) && leftleft.link.red_get()) {
                        //        ||
                        //      pathp(r)
                        //     /        \\
                        //   (b)        (b)
                        //   /
                        // (r)
                        // a_type *tnode;
                        // rbtn_black_set(a_type, a_field, pathp->node);
                        // rbtn_red_set(a_type, a_field, left);
                        // rbtn_black_set(a_type, a_field, leftleft);
                        // rbtn_rotate_right(a_type, a_field, pathp->node, tnode);
                        path[ix].node.link.black_set();
                        left.link.red_set();
                        leftleft.link.black_set();
                        var tnode = rotate_right(path[ix].node);
                        // Balance restored, but rotation modified
                        // subtree root.
                        // assert((uintptr_t)pathp > (uintptr_t)path);
                        assert(ix > 0);
                        if (path[ix - 1].cmp < 0) {
                            // rbtn_left_set(a_type, a_field, pathp[-1].node, tnode);
                            path[ix - 1].node.link.left_set(tnode);
                        } else {
                            //rbtn_right_set(a_type, a_field, pathp[-1].node, tnode);
                            path[ix - 1].node.link.right_set(tnode);
                        }
                        return;
                    } else {
                        //        ||                                      */
                        //      pathp(r)                                  */
                        //     /        \\                                */
                        //   (b)        (b)                               */
                        //   /                                            */
                        // (b)                                            */
                        // rbtn_red_set(a_type, a_field, left);
                        // rbtn_black_set(a_type, a_field, pathp->node);
                        left.link.red_set();
                        path[ix].node.link.black_set();
                        // Balance restored.
                        return;
                    }
                } else {
                    // a_type *leftleft = rbtn_left_get(a_type, a_field, left);
                    // if (leftleft != NULL && rbtn_red_get(a_type, a_field, leftleft)) {
                    var leftleft = left.link.left_get();
                    if ((leftleft != NULL) && (leftleft.link.red_get())) {
                        //        ||
                        //      pathp(b)
                        //     /        \\
                        //   (b)        (b)
                        //   /
                        // (r)
                        // a_type *tnode;
                        // rbtn_black_set(a_type, a_field, leftleft);
                        // rbtn_rotate_right(a_type, a_field, pathp->node, tnode);
                        leftleft.link.black_set();
                        var tnode = rotate_right(path[ix].node);
                        // Balance restored, but rotation modified
                        // subtree root, which may actually be the tree
                        // root.
                        // if (pathp == path) {
                        if (ix == 0) {
                            // Set root.
                            t.rbt_root = tnode;
                        } else {
                            if (path[ix -1 ].cmp < 0) {
                                // rbtn_left_set(a_type, a_field, pathp[-1].node, tnode);
                                path[ix - 1].node.link.left_set(tnode);
                            } else {
                                // rbtn_right_set(a_type, a_field, pathp[-1].node, tnode);
                                path[ix - 1].node.link.right_set(tnode);
                            }
                        }
                        return;
                    } else {
                        //        ||
                        //      pathp(b)
                        //     /        \\
                        //   (b)        (b)
                        //   /
                        // (b)
                        // rbtn_red_set(a_type, a_field, left);
                        left.link.red_set();
                    }
                }
            }
        }
        // Set root.
        // %%printNamedHex("at end ix=", ix, io.stdout);
        if (ix >= path.len) ix +%= 1;
        t.rbt_root = path[ix].node;
        t.s.reend += 1;
        // hmm
        assert(!t.rbt_root.link.red_get());
    }
}
