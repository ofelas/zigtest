#!/usr/bin/python -Bt

# License: MIT (see the LICENSE file)

from __future__ import print_function

import sys
import os
import lzma

def zig_dump(data):
    buf = ["0x%02x" % (ord(x)) for x in data]
    x = 0
    print("var test_data = [_]u8", end="{")
    while x < len(buf):
        print("%s," % ",".join(buf[x:x+16]))
        x += 16
    print("", end="};\n")
   

def main():
    print("Running main...")
    opts= {"format": "alone", "level":6}
    fname = sys.argv[1]
    if fname == "dump":
        fname = sys.argv[2]
        sz = os.stat(fname).st_size
        print("%s is a file (%d)" % (fname, sz))
        data = open(fname, "rb").read(sz)
    elif os.path.isfile(fname):
        sz = os.stat(fname).st_size
        print("%s is a file (%d)" % (fname, sz))
        data = lzma.compress(open(fname, "rb").read(sz), opts)
        print(data[-16:].encode("hex"))
        try:
            lzma.decompress(data)
        except:
            print("Failed to decompress")
    else:
        print("Compressing '%s'" % (fname))
        data = lzma.compress(fname, opts)
    zig_dump(data)

if __name__ == "__main__":
    main()
