// -*- mode:zig; indent-tabs-mode:nil;  -*-
const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const debug = std.debug;
const warn = debug.warn;
const builtin = @import("builtin");

const NANOS_PER_SEC: u32 = 1000000000;
const NANOS_PER_MILLI: u32 = 1000000;
const NANOS_PER_MICRO: u32 = 1000;
const MILLIS_PER_SEC: u64 = 1000;
const MICROS_PER_SEC: u64 = 1000000;

inline fn addOrNull(comptime T: type, a: T, b: T) ?T {
    var v: T = 0;
    return if (@addWithOverflow(u64, a, b, &v)) null else v;
}

inline fn subOrNull(comptime T: type, a: T, b: T) ?T {
    var v: T = 0;
    return if (@subWithOverflow(u64, a, b, &v)) null else v;
}

pub const Duration = struct {
    const Self = this;

    secs: u64,
    nanos: u32, // Always 0 <= nanos < NANOS_PER_SEC

    pub inline fn new(secs: u64, nanos: u32) Duration {
        var seconds: u64 = 0;
        if (@addWithOverflow(u64, secs, u64(nanos / NANOS_PER_SEC), &seconds)) {
            // Got overflow...
            seconds = secs;
        }
        return Duration { .secs = seconds, .nanos = nanos % NANOS_PER_SEC };
    }

    pub inline fn from_secs(secs: u64) Duration {
        return Duration { .secs = secs, .nanos = 0 };
    }

    pub inline fn from_millis(millis: u64) Duration {
        return Duration {
            .secs = millis / MILLIS_PER_SEC,
            .nanos = (@truncate(u32, millis % MILLIS_PER_SEC)) * NANOS_PER_MILLI,
        };
    }

    pub inline fn from_micros(micros: u64) Duration {
        return Duration {
            .secs = micros / MICROS_PER_SEC,
            .nanos = (@truncate(u32, micros % MICROS_PER_SEC)) * NANOS_PER_MICRO,
        };
    }
    
    pub inline fn from_nanos(nanos: u64) Duration {
        return Duration {
            .secs = nanos / u64(NANOS_PER_SEC),
            .nanos = @truncate(u32, nanos % u64(NANOS_PER_SEC)),
        };
    }

    pub inline fn as_secs(self: *const Self) u64 {
        return self.secs;
    }

    pub inline fn subsec_millis(self: *const Self) u32 {
        return self.nanos / NANOS_PER_MILLI;
    }

    pub inline fn subsec_micros(self: *const Self) u32 {
        return self.nanos / NANOS_PER_MICRO;
    }

    pub inline fn subsec_nanos(self: *const Self) u32 {
        return self.nanos;
    }

    pub inline fn checked_add(self: *const Self, rhs: Duration) ?Duration {
        if (addOrNull(u64, self.secs, rhs.secs)) |*secs| {
            var nanos = self.nanos + rhs.nanos;
            if (nanos >= NANOS_PER_SEC) {
                nanos -= NANOS_PER_SEC;
                if (addOrNull(u64, secs.*, 1)) |new_secs| {
                    secs.* = new_secs;
                } else {
                    return null;
                }
            }
            debug.assert(nanos < NANOS_PER_SEC);
            return Duration {.secs = secs.*, .nanos = nanos};
        } else {
            return null;
        }
    }

    pub inline fn add(self: *const Self, rhs: Duration) Duration {
        if (self.checked_add(rhs)) |d| {
            return d;
        } else {
            @panic("overflow when adding durations");
        }
    }

    pub inline fn add_assign(self: *Self, rhs: Duration) void {
        self.* = self.add(rhs);
    }

    pub inline fn checked_sub(self: *const Self, rhs: Duration) ?Duration {
        if (subOrNull(u64, self.secs, rhs.secs)) |*secs| {
            var nanos = self.nanos;
            if (nanos >= rhs.nanos) {
                nanos -= rhs.nanos;
            } else {
                if (subOrNull(u64, secs.*, 1)) |sub_secs| {
                    secs.* = sub_secs;
                    nanos = NANOS_PER_SEC - rhs.nanos;
                } else {
                    return null;
                }
            }
            debug.assert(nanos < NANOS_PER_SEC);
            return Duration {.secs = secs.*, .nanos = nanos};
        } else {
            return null;
        }
    }

    pub inline fn sub(self: *const Self, rhs: Duration) Duration {
        if (self.checked_sub(rhs)) |d| {
            return d;
        } else {
            @panic("overflow when subtracting durations");
        }
    }

    pub inline fn sub_assign(self: *Self, rhs: Duration) void {
        self.* = self.sub(rhs);
    }

};

test "Duration.new" {
    var d = Duration.new(0,0);
    debug.assert(d.secs == 0 and d.nanos == 0);

    d = Duration.new(0, NANOS_PER_SEC - 1);
    debug.assert(d.secs == 0 and d.nanos == NANOS_PER_SEC - 1);

    d = Duration.new(0, NANOS_PER_SEC);
    debug.assert(d.secs == 1 and d.nanos == 0);

    d = Duration.new(@maxValue(u64), 0);
    debug.assert(d.secs == @maxValue(u64) and d.nanos == 0);

    d = Duration.new(@maxValue(u64), @maxValue(u32));
    debug.assert(d.secs == @maxValue(u64) and d.nanos == @maxValue(u32) % NANOS_PER_SEC);
}

test "Duration.from_secs" {
    var d = Duration.from_secs(0);
    debug.assert(d.secs == 0 and d.nanos == 0);
    debug.assert(d.secs == Duration.new(0, NANOS_PER_SEC-1).secs);
    debug.assert(d.secs == Duration.new(0, 0).as_secs());
    debug.assert(d.as_secs() == Duration.new(0, 33).as_secs());
}

test "Duration.from_secs" {
    var d = Duration.from_secs(5);
    debug.assert(d.secs == 5 and d.nanos == 0);
    debug.assert(d.secs == Duration.new(5, NANOS_PER_SEC-1).secs);
    debug.assert(d.secs == Duration.new(5, 0).as_secs());
    debug.assert(d.as_secs() == Duration.new(5, 33).as_secs());
}

test "Duration.from_millis" {
    var d = Duration.from_millis(5001);
    debug.assert(d.secs == 5 and d.nanos == 1 * NANOS_PER_MILLI);
    debug.assert(d.secs == Duration.new(5, NANOS_PER_SEC-1).secs);
    debug.assert(d.secs == Duration.new(5, 0).as_secs());
    debug.assert(d.as_secs() == Duration.new(5, 33).as_secs());

    d = Duration.from_millis(5432);
    debug.assert(d.as_secs() == 5);
    debug.assert(d.subsec_millis() == 432);

    d = Duration.from_millis(54321);
    debug.assert(d.as_secs() == 54);
    debug.assert(d.subsec_millis() == 321);
}

test "Duration.from_micros" {
    var d = Duration.from_micros(5001);
    debug.assert(d.secs == 0 and d.nanos == 5001 * NANOS_PER_MICRO);
}

test "Duration.from_nanos" {
    var d = Duration.from_nanos(5001);
    debug.assert(d.secs == 0 and d.nanos == 5001);

    d = Duration.new(0, NANOS_PER_SEC);
    debug.assert(d.secs == 1 and d.nanos == 0);

    d = Duration.new(7, NANOS_PER_SEC + 33);
    debug.assert(d.secs == 8 and d.nanos == 33);
}

test "Duration.checked_add" {
    if (Duration.new(0, 0).checked_add(Duration.new(0, 1))) |dd| {
        debug.assert(dd.secs == 0 and dd.nanos == 1);
    }
    var d = Duration.new(1, 0);
    if (d.checked_add(Duration.new(@maxValue(u64), 0))) |x| {
        debug.assert(false);
    }
    d = Duration.new(0, NANOS_PER_SEC - 1);
    if (d.checked_add(Duration.new(@maxValue(u64)-1, 1))) |x| {
        debug.assert(x.secs == @maxValue(u64) and x.nanos == 0);
        debug.assert(d.secs == 0 and d.nanos == NANOS_PER_SEC - 1);
    } else {
        debug.assert(false);
    }
}

test "Duration.add" {
    var d = Duration.new(0, 0).add(Duration.new(0, 1));
    debug.assert(d.secs == 0 and d.nanos == 1);
}

test "Duration.add_assign" {
    var d = Duration.new(0, 0);
    d.add_assign(Duration.new(0, 1));
    debug.assert(d.secs == 0 and d.nanos == 1);
}

test "Duration.checked_sub" {
    var d = Duration.new(0, 1);
    if (d.checked_sub(Duration.new(0, 0))) |dd| {
        debug.assert(d.secs == 0 and d.nanos == 1);
    } else {
        debug.assert(false);
    }

    d = Duration.new(0, 0);
    if (d.checked_sub(Duration.new(0, 1))) |dd| {
        debug.assert(false);
    } else {
        debug.assert(d.secs == 0 and d.nanos == 0);
    }
}

test "Duration.sub" {
    var d = Duration.new(2, 2).sub(Duration.new(1, 1));
    debug.assert(d.secs == 1 and d.nanos == 1);
}

test "Duration.sub_assign" {
    var d = Duration.new(33, 33);
    d.sub_assign(Duration.new(0, 1));
    debug.assert(d.secs == 33 and d.nanos == 32);
}
