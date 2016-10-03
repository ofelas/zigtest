// /*-
//  * Copyright (C) 2006-2008 Jason Evans <jasone@FreeBSD.org>.
//  * All rights reserved.
//  *
//  * Redistribution and use in source and binary forms, with or without
//  * modification, are permitted provided that the following conditions
//  * are met:
//  * 1. Redistributions of source code must retain the above copyright
//  *    notice(s), this list of conditions and the following disclaimer as
//  *    the first lines of this file unmodified other than the possible
//  *    addition of one or more copyright notices.
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
//  *******************************************************************************
//  *
//  * This allocator implementation is designed to provide scalable performance
//  * for multi-threaded programs on multi-processor systems.  The following
//  * features are included for this purpose:
//  *
//  *   + Multiple arenas are used if there are multiple CPUs, which reduces lock
//  *     contention and cache sloshing.
//  *
//  *   + Cache line sharing between arenas is avoided for internal data
//  *     structures.
//  *
//  *   + Memory is managed in chunks and runs (chunks can be split into runs),
//  *     rather than as individual pages.  This provides a constant-time
//  *     mechanism for associating allocations with particular arenas.
//  *
//  * Allocation requests are rounded up to the nearest size class, and no record
//  * of the original request size is maintained.  Allocations are broken into
//  * categories according to size class.  Assuming runtime defaults, 4 kB pages
//  * and a 16 byte quantum on a 32-bit system, the size classes in each category
//  * are as follows:
//  *
//  *   |=====================================|
//  *   | Category | Subcategory    |    Size |
//  *   |=====================================|
//  *   | Small    | Tiny           |       2 |
//  *   |          |                |       4 |
//  *   |          |                |       8 |
//  *   |          |----------------+---------|
//  *   |          | Quantum-spaced |      16 |
//  *   |          |                |      32 |
//  *   |          |                |      48 |
//  *   |          |                |     ... |
//  *   |          |                |     480 |
//  *   |          |                |     496 |
//  *   |          |                |     512 |
//  *   |          |----------------+---------|
//  *   |          | Sub-page       |    1 kB |
//  *   |          |                |    2 kB |
//  *   |=====================================|
//  *   | Large                     |    4 kB |
//  *   |                           |    8 kB |
//  *   |                           |   12 kB |
//  *   |                           |     ... |
//  *   |                           | 1004 kB |
//  *   |                           | 1008 kB |
//  *   |                           | 1012 kB |
//  *   |=====================================|
//  *   | Huge                      |    1 MB |
//  *   |                           |    2 MB |
//  *   |                           |    3 MB |
//  *   |                           |     ... |
//  *   |=====================================|
//  *
//  * A different mechanism is used for each category:
//  *
//  *   Small : Each size class is segregated into its own set of runs.  Each run
//  *           maintains a bitmap of which regions are free/allocated.
//  *
//  *   Large : Each allocation is backed by a dedicated run.  Metadata are stored
//  *           in the associated arena chunk header maps.
//  *
//  *   Huge : Each allocation is backed by a dedicated contiguous set of chunks.
//  *          Metadata are stored in a separate red-black tree.
//  *
//  *******************************************************************************
//  */
