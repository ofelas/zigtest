// -*- mode:zig; indent-tabs-mode:nil;  -*-
const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const debug = std.debug;
const warn = debug.warn;
const builtin = @import("builtin");

use @import("duration.zig");

const Timer = std.os.time.Timer;

pub const Instant = struct {
    const Self = this;

    inner: u64,

    pub inline fn now() Instant {
        return Instant{.inner = Timer.clockNative()};
    }

    pub inline fn duration_since(self: *const Self, earlier: Instant) Duration {
        return self.as_duration().sub(earlier.as_duration());
    }

    pub inline fn elapsed(self: *const Self) Duration {
        return Instant.now().as_duration().sub(self.as_duration());
    }

    pub inline fn as_duration(self: *const Self) Duration {
        return Duration.from_nanos(self.inner);
    }
};


test "Instant.dummy" {
    debug.assert(false == false);
}

test "Instant.now" {
    var instant = Instant.now();

    var d = instant.as_duration();
    //warn("instant.inner={}, d .secs={}, .nanos={d9}\n", instant.inner, d.secs, d.nanos);
}

test "Instant.duration_since" {
    var earlier = Instant.now();
    var d = earlier.as_duration();
    //warn("earlier.inner={}, d .secs={}, .nanos={d9}\n", earlier.inner, d.secs, d.nanos);
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        std.os.time.sleep(1, 0);
        var now = Instant.now();
        d = now.duration_since(earlier);
        debug.assert(d.secs == i + 1);
        var d2 = earlier.elapsed();
        warn("d  .secs={}, .nanos={d9}\n", d.secs, d.nanos);
        warn("d2 .secs={}, .nanos={d9}\n", d2.secs, d2.nanos);
        debug.assert(d2.secs == i + 1);
    }
}
