// -*- mode:zig; indent-tabs-mode:nil;  -*-
const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const assert = std.debug.assert;
const warn = std.debug.warn;
const builtin = @import("builtin");

const posix = std.os.posix;

pub const sockaddr = posix.sockaddr;

pub const Ipv6MulticastScope = enum {
    InterfaceLocal,
    LinkLocal,
    RealmLocal,
    AdminLocal,
    SiteLocal,
    OrganizationLocal,
    Global
};

pub const IpAddr = union(enum) {
    const Self = this;

    /// An IPv4 address.
    V4: Ipv4Addr,
    /// An IPv6 address.
    V6: Ipv6Addr,

    pub fn is_unspecified(self: *const Self) bool {
        return switch (self.*) {
            IpAddr.V4 => |*a| a.*.is_unspecified(),
            IpAddr.V6 => |*a| a.*.is_unspecified(),
        };
    }

    pub fn is_loopback(self: *const Self) bool {
        return switch (self.*) {
            IpAddr.V4 => |*a| a.*.is_loopback(),
            IpAddr.V6 => |*a| a.*.is_loopback(),
        };
    }

    pub fn is_global(self: *const Self) bool {
        return switch (self.*) {
            IpAddr.V4 => |*a| a.*.is_global(),
            IpAddr.V6 => |*a| a.*.is_global(),
        };
    }

    pub fn is_multicast(self: *const Self) bool {
        return switch (self.*) {
            IpAddr.V4 => |*a| a.*.is_multicast(),
            IpAddr.V6 => |*a| a.*.is_multicast(),
        };
    }

    pub fn is_documentation(self: *const Self) bool {
        return switch (self.*) {
            IpAddr.V4 => |*a| a.*.is_documentation(),
            IpAddr.V6 => |*a| a.*.is_documentation(),
        };
    }

    pub fn is_ipv4(self: *const Self) bool {
        return switch (self.*) {
            IpAddr.V4 => |_| true,
            IpAddr.V6 => |_| false,
        };
    }

    pub fn from_ipv4(ipv4: Ipv4Addr) IpAddr {
        return IpAddr {.V4 = ipv4};
    }

    pub fn is_ipv6(self: *const Self) bool {
        return switch (self.*) {
            IpAddr.V4 => |_| false,
            IpAddr.V6 => |_| true,
        };
    }

    pub fn from_ipv6(ipv6: Ipv6Addr) IpAddr {
        return IpAddr {.V6 = ipv6};
    }

    pub fn format(
        self: *const Self,
        comptime fmt: []const u8,
        context: var,
        comptime Errors: type,
        output: fn (@typeOf(context), []const u8) Errors!void,
    ) Errors!void {
        return switch (self.*) {
            IpAddr.V4 => |*a| a.format(fmt, context, Errors, output),
            IpAddr.V6 => |*a| a.format(fmt, context, Errors, output),
        };
    }

};

pub const Ipv4Addr = struct {
    const Self = this;

    inner: in_addr,

    pub fn new(a: u8, b: u8, c: u8, d: u8) Ipv4Addr {
        const u: in_addr_t = ((u32(a) << 24) | (u32(b) << 16) |
                              (u32(c) <<  8) | u32(d));
        return Ipv4Addr {.inner = in_addr {
            .s_addr = std.mem.endianSwapIfLe(in_addr_t, u)} };
    }

    pub fn eql(self: *const Self, other: *const Ipv4Addr) bool {
        return self.inner.s_addr == other.inner.s_addr;
    }

    pub fn localhost() Ipv4Addr {
        return Ipv4Addr.new(127, 0, 0, 1);
    }

    pub fn unspecified() Ipv4Addr {
        return Ipv4Addr.new(0, 0, 0, 0);
    }

    pub fn from_u32(ip: u32) Ipv4Addr {
        return Ipv4Addr.new(@truncate(u8, ip >> 24), @truncate(u8, ip >> 16),
                            @truncate(u8, ip >> 8), @truncate(u8, ip));
    }

    fn from_array(octets_: [4]u8) Ipv4Addr {
        return Ipv4Addr.new(octets_[0], octets_[1], octets_[2], octets_[3]);
    }

    pub fn octets(self: *const Self) [4]u8 {
        const bits = std.mem.endianSwapIfLe(@typeOf(self.inner.s_addr), self.inner.s_addr);
        return []u8 {@truncate(u8, bits >> 24), @truncate(u8, bits >> 16),
                     @truncate(u8, bits >> 8), @truncate(u8, bits)};
    }

    pub fn is_unspecified(self: *const Self) bool {
        return self.inner.s_addr == 0;
    }

    pub fn is_loopback(self: *const Self) bool {
        return self.octets()[0] == 127;
    }

    pub fn is_private(self: *const Self) bool {
        const oct = self.octets();
        return switch (oct[0]) {
            10 => true,
            172 => if (oct[1] >= 16 and oct[1] <= 31) true else false,
            192 => if (oct[1] == 168) true else false,
            else => false,
        };
    }

    pub fn is_link_local(self: *const Self) bool {
        const oct = self.octets();
        return (oct[0] == 169 and oct[1] == 254);
    }

    pub fn is_multicast(self: *const Self) bool {
        const oct = self.octets();
        return oct[0] >= 224 and oct[0] <= 239;
    }

    pub fn is_broadcast(self: *const Self) bool {
        const oct = self.octets();
        return oct[0] == 255 and oct[1] == 255 and
            oct[2] == 255 and oct[3] == 255;
    }

    pub fn is_documentation(self: *const Self) bool {
        const oct = self.octets();
        switch (oct[0]) {
            192 => if (oct[1] == 0 and oct[2] == 2) return true,
            198 => if (oct[1] == 51 and oct[2] == 100) return true,
            203 => if (oct[1] == 0 and oct[2] == 113) return true,
            else => return false,
        }
        return false;
    }

    pub fn is_global(self: *const Self) bool {
        return (!self.is_private() and !self.is_loopback() and !self.is_link_local() and
        !self.is_broadcast() and !self.is_documentation() and !self.is_unspecified());
    }

    pub fn to_ipv6_compatible(self: *const Self) Ipv6Addr {
        const oct = self.octets();
        return Ipv6Addr.new(0, 0, 0, 0, 0, 0,
                            (u16(oct[0]) << 8) | u16(oct[1]),
                            (u16(oct[2]) << 8) | u16(oct[3]));
    }

    pub fn to_ipv6_mapped(self: *const Self) Ipv6Addr {
        const oct = self.octets();
        return Ipv6Addr.new(0, 0, 0, 0, 0, 0xffff,
                      (u16(oct[0]) << 8) | u16(oct[1]),
                      (u16(oct[2]) << 8) | u16(oct[3]));
    }

    pub fn to_sockaddr(self: *const Self, port: posix.in_port_t) posix.sockaddr {
        return posix.sockaddr {
            .in = posix.sockaddr_in {
                .family = posix.PF_INET,
                .port = std.mem.endianSwapIfLe(u16, port),
                .addr = self.inner.s_addr,
                .zero = []u8 {0} ** 8,
            }
        };
    }

    pub fn from_sockaddr(sockaddr_: *const posix.sockaddr) Ipv4Addr {
        return Ipv4Addr.from_u32(std.mem.endianSwapIfLe(u32, sockaddr_.in.addr));
    }

    pub fn format(
        self: *const Self,
        comptime fmt: []const u8,
        context: var,
        comptime Errors: type,
        output: fn (@typeOf(context), []const u8) Errors!void,
    ) Errors!void {
        // We ignore the actual format char for now
        const oct = self.octets();
        return std.fmt.format(context, Errors, output, "{}.{}.{}.{}",
                              oct[0], oct[1], oct[2], oct[3]);
    }
};


pub const Ipv6Addr = struct {
    const Self = this;

    inner: in6_addr,

    pub fn new(a: u16, b: u16, c: u16, d: u16, e: u16, f: u16, g: u16, h: u16) Ipv6Addr {
        var addr = Ipv6Addr {.inner = in6_addr {.s6_addr = undefined}};
        addr.inner.s6_addr = []u8 {@truncate(u8, a >> 8), @truncate(u8, a),
                                   @truncate(u8, b >> 8), @truncate(u8, b),
                                   @truncate(u8, c >> 8), @truncate(u8, c),
                                   @truncate(u8, d >> 8), @truncate(u8, d),
                                   @truncate(u8, e >> 8), @truncate(u8, e),
                                   @truncate(u8, f >> 8), @truncate(u8, f),
                                   @truncate(u8, g >> 8), @truncate(u8, g),
                                   @truncate(u8, h >> 8), @truncate(u8, h)};
        return addr;
    }

    pub fn localhost() Ipv6Addr {
        return Ipv6Addr.new(0, 0, 0, 0, 0, 0, 0, 1);
    }

    pub fn unspecified() Ipv6Addr {
        return Ipv6Addr.new(0, 0, 0, 0, 0, 0, 0, 0);
    }

    pub fn eql(self: *const Self, other: *const Ipv6Addr) bool {
        return mem.eql(u8, self.inner.s6_addr, other.inner.s6_addr);
    }

    pub fn segments(self: *const Self) [8]u16 {
        const arr = &self.inner.s6_addr;
        return [8]u16 {
            u16(arr[0]) << 8 | (arr[1]),
            u16(arr[2]) << 8 | (arr[3]),
            u16(arr[4]) << 8 | (arr[5]),
            u16(arr[6]) << 8 | (arr[7]),
            u16(arr[8]) << 8 | (arr[9]),
            u16(arr[10]) << 8 | (arr[11]),
            u16(arr[12]) << 8 | (arr[13]),
            u16(arr[14]) << 8 | (arr[15]),
        };
    }

    pub fn is_unspecified(self: *const Self)  bool {
        return mem.eql(u16, self.segments(), [8]u16 {0, 0, 0, 0, 0, 0, 0, 0});
    }

    pub fn is_loopback(self: *const Self) bool {
        return mem.eql(u16, self.segments(), [8]u16 {0, 0, 0, 0, 0, 0, 0, 1});
    }

    pub fn is_global(self: *const Self) bool {
        if (self.multicast_scope()) |scope| {
            return switch (scope) {
                Ipv6MulticastScope.Global => true,
                else => false,
            };
        } else {
            return self.is_unicast_global();
        }
    } 

    pub fn is_unique_local(self: *const Self) bool {
        return (self.segments()[0] & 0xfe00) == 0xfc00;
    }

    pub fn is_unicast_link_local(self: *const Self) bool {
        return (self.segments()[0] & 0xffc0) == 0xfe80;
    }

    pub fn is_unicast_site_local(self: *const Self) bool {
        return (self.segments()[0] & 0xffc0) == 0xfec0;
    }

    pub fn is_documentation(self: *const Self) bool {
        return (self.segments()[0] == 0x2001) and (self.segments()[1] == 0xdb8);
    }

    pub fn is_unicast_global(self: *const Self) bool {
        return (!self.is_multicast()
                and !self.is_loopback() and !self.is_unicast_link_local()
                and !self.is_unicast_site_local() and !self.is_unique_local()
                and !self.is_unspecified() and !self.is_documentation());
    }

    pub fn multicast_scope(self: *const Self) ?Ipv6MulticastScope {
        if (self.is_multicast()) {
            return switch (self.segments()[0] & 0x000f) {
                1 => Ipv6MulticastScope.InterfaceLocal,
                2 => Ipv6MulticastScope.LinkLocal,
                3 => Ipv6MulticastScope.RealmLocal,
                4 => Ipv6MulticastScope.AdminLocal,
                5 => Ipv6MulticastScope.SiteLocal,
                8 => Ipv6MulticastScope.OrganizationLocal,
                14 => Ipv6MulticastScope.Global,
                else => null,
            };
        } else {
            return null;
        }
    }

    pub fn is_multicast(self: *const Self) bool {
        return (self.segments()[0] & 0xff00) == 0xff00;
    }

    pub fn to_ipv4(self: *const Self) ?Ipv4Addr {
        const seg = self.segments();
        const abcde = seg[0] | seg[1] | seg[2] | seg[3] | seg[4];
        const f = seg[5];
        const g = seg[6];
        const h = seg[7];
        if (abcde == 0) {
            if ((f == 0) or (f == 0xffff)) {
                return Ipv4Addr.new(@truncate(u8, g >> 8), @truncate(u8, g),
                                    @truncate(u8, h >> 8), @truncate(u8, h));
            }
        }
        return null;

        // match self.segments() {
        //     [0, 0, 0, 0, 0, f, g, h] if f == 0 || f == 0xffff => {
        //         Some(Ipv4Addr.new((g >> 8) as u8, g as u8,
        //                            (h >> 8) as u8, h as u8))
        //     },
        //     _ => None
        // }
    }

    pub fn octets(self: *const Self) [16]u8 {
        return self.inner.s6_addr;
    }

    pub fn format(
        self: *const Self,
        comptime fmt: []const u8,
        context: var,
        comptime Errors: type,
        output: fn (@typeOf(context), []const u8) Errors!void,
    ) Errors!void {
        // We ignore the actual format char for now
        const seg = self.segments();
        const g = seg[6];
        const h = seg[7];
        // could be optimized a little
        if (mem.eql(u16, seg[0..], []u16{0,0,0,0,0,0,0,0})) {
            return output(context, "::");
        } else if (mem.eql(u16, seg[0..], []u16{0,0,0,0,0,0,0,1})) {
            return output(context, "::1");
        } else if (mem.eql(u16, seg[0..6], []u16{0,0,0,0,0,0})) {
            return std.fmt.format(context, Errors, output, "::{}.{}.{}.{}",
                                  @truncate(u8, g >> 8), @truncate(u8, g),
                                  @truncate(u8, h >> 8), @truncate(u8, h));
        } else if (mem.eql(u16, seg[0..6], []u16{0,0,0,0,0,0xffff})) {
            return std.fmt.format(context, Errors, output, "::ffff:{}.{}.{}.{}",
                                  @truncate(u8, g >> 8), @truncate(u8, g),
                                  @truncate(u8, h >> 8), @truncate(u8, h));
        } else {
            var longest_span_len:u8 = 0;
            var longest_span_at:u8 = 0;
            var cur_span_len:u8 = 0;
            var cur_span_at:u8 = 0;
            var i: u8 = 0;
            //for i in 0..8 {
            while (i < 8) : (i += 1) {
                if (seg[i] == 0) {
                    if (cur_span_len == 0) {
                        cur_span_at = i;
                    }

                    cur_span_len += 1;

                    if (cur_span_len > longest_span_len) {
                        longest_span_len = cur_span_len;
                        longest_span_at = cur_span_at;
                    }
                } else {
                    cur_span_len = 0;
                    cur_span_at = 0;
                }
            }

            // (longest_span_at, longest_span_len)
            if (longest_span_len > 1) {
                // TODO incomplete
                //  fn fmt_subslice(segments: &[u16], fmt: &mut fmt::Formatter) -> fmt::Result {
                //      if !segments.is_empty() {
                //          write!(fmt, "{:x}", segments[0])?;
                //          for &seg in &segments[1..] {
                //              write!(fmt, ":{:x}", seg)?;
                //          }
                //      }
                //      Ok(())
                //  }
                const s1 = seg[0..longest_span_at];
                const s2 = seg[longest_span_at + longest_span_len..];
                if (s1[0] != 0) {
                    try std.fmt.format(context, Errors, output, "{x}", s1[0]);
                }
                for (s1[1..]) |s, ii| {
                    try std.fmt.format(context, Errors, output, ":{x}", s);
                }
                try output(context, "::");
                //  fmt_subslice(&self.segments()[..zeros_at], fmt)?;
                //  fmt.write_str("::")?;
                //  fmt_subslice(&self.segments()[zeros_at + zeros_len..], fmt)
                if (s2.len > 0) {
                    if (s2[0] != 0) {
                        try std.fmt.format(context, Errors, output, "{x}", s2[0]);
                    }
                    for (s2[1..]) |s, ii| {
                        try std.fmt.format(context, Errors, output, ":{x}", s);
                    }
                }
                // return std.fmt.format(context, Errors, output, "{x}:{x}:{x}:{x}:{x}:{x}:{x}:{x}",
                //                       seg[0], seg[1], seg[2], seg[3], seg[4], seg[5], seg[6], seg[7]);
            } else { 
                return std.fmt.format(context, Errors, output, "{x}:{x}:{x}:{x}:{x}:{x}:{x}:{x}",
                                      seg[0], seg[1], seg[2], seg[3], seg[4], seg[5], seg[6], seg[7]);
            }
        }
    }
};

const in_addr_t = u32;
const in6_addr_t = [16]u8;

pub const in_addr = struct {
    pub s_addr: in_addr_t,
};

pub const in6_addr = struct {
    pub s6_addr: in6_addr_t,
};

test "IP.v4.misc" {
    assert(Ipv4Addr.new(127, 0, 0, 1).is_loopback() == true);
    assert(Ipv4Addr.new(45, 22, 13, 197).is_loopback() == false);
    assert(Ipv4Addr.new(169, 254, 0, 0).is_link_local() == true);
    assert(Ipv4Addr.new(169, 254, 10, 65).is_link_local() == true);
    assert(Ipv4Addr.new(16, 89, 10, 65).is_link_local() == false);
    assert(Ipv4Addr.new(10, 254, 0, 0).is_global() == false);
    assert(Ipv4Addr.new(192, 168, 10, 65).is_global() == false);
    assert(Ipv4Addr.new(172, 16, 10, 65).is_global() == false);
    assert(Ipv4Addr.new(0, 0, 0, 0).is_global() == false);
    assert(Ipv4Addr.new(80, 9, 12, 3).is_global() == true);
    assert(Ipv4Addr.new(224, 254, 0, 0).is_multicast() == true);
    assert(Ipv4Addr.new(236, 168, 10, 65).is_multicast() == true);
    assert(Ipv4Addr.new(172, 16, 10, 65).is_multicast() == false);
    assert(Ipv4Addr.new(255, 255, 255, 255).is_broadcast() == true);
    assert(Ipv4Addr.new(192, 0, 2, 255).is_documentation() == true);
    assert(Ipv4Addr.new(198, 51, 100, 65).is_documentation() == true);
    assert(Ipv4Addr.new(203, 0, 113, 6).is_documentation() == true);
    assert(Ipv4Addr.new(193, 34, 17, 19).is_documentation() == false);
    assert(Ipv4Addr.new(236, 168, 10, 65).is_broadcast() == false);
    assert(Ipv4Addr.new(10, 0, 0, 1).is_private() == true);
    assert(Ipv4Addr.new(10, 10, 10, 10).is_private() == true);
    assert(Ipv4Addr.new(172, 16, 10, 10).is_private() == true);
    assert(Ipv4Addr.new(172, 29, 45, 14).is_private() == true);
    assert(Ipv4Addr.new(172, 32, 0, 2).is_private() == false);
    assert(Ipv4Addr.new(192, 168, 0, 2).is_private() == true);
    assert(Ipv4Addr.new(192, 169, 0, 2).is_private() == false);
}

test "IP.unspecified" {
    var a4 = Ipv4Addr.unspecified();
    var v4 = IpAddr.from_ipv4(a4);
    var a6 = Ipv6Addr.unspecified();
    var v6 = IpAddr.from_ipv6(a6);


    assert(a4.is_unspecified() == true);
    assert(v4.is_unspecified() == true);

    assert(a4.is_loopback() == false);
    assert(v4.is_loopback() == false);

    assert(a4.is_private() == false);
    assert(a4.is_global() == false);
    assert(a4.is_multicast() == false);

    assert(v4.is_ipv4() == true);
    assert(v4.is_ipv6() == false);

    assert(a6.is_unspecified() == true);
    assert(v6.is_unspecified() == true);

    assert(a6.is_loopback() == false);
    assert(v6.is_loopback() == false);

    assert(v6.is_ipv4() == false);
    assert(v6.is_ipv6() == true);
}

test "IP.v4.format" {
    var buf = []u8 {0} ** 64;
    var b = try std.fmt.bufPrint(buf[0..], "{}", &Ipv4Addr.localhost());
    assert(mem.eql(u8, "127.0.0.1", b[0..]));
    b = try std.fmt.bufPrint(buf[0..], "{}", &Ipv4Addr.unspecified());
    assert(mem.eql(u8, "0.0.0.0", b[0..]));
}

test "IP.v4.localhost" {
    var a4 = Ipv4Addr.localhost();
    var v4 = IpAddr.from_ipv4(a4);

    assert(a4.is_unspecified() == false);
    assert(v4.is_unspecified() == false);

    assert(a4.is_loopback() == true);
    assert(v4.is_loopback() == true);

    assert(a4.is_link_local() == false);
    assert(a4.is_private() == false);
    assert(a4.is_global() == false);
    assert(a4.is_multicast() == false);
    assert(a4.is_broadcast() == false);

    assert(v4.is_ipv4() == true);
    assert(v4.is_ipv6() == false);
}

test "IP.v4.linklocal" {
    var a4 = Ipv4Addr.new(169,254,1,2);
    var v4 = IpAddr.from_ipv4(a4);

    assert(a4.is_unspecified() == false);
    assert(v4.is_unspecified() == false);

    assert(a4.is_loopback() == false);
    assert(v4.is_loopback() == false);

    assert(a4.is_link_local() == true);
    assert(a4.is_private() == false);
    assert(a4.is_global() == false);
    assert(a4.is_multicast() == false);
    assert(a4.is_broadcast() == false);

    assert(v4.is_ipv4() == true);
    assert(v4.is_ipv6() == false);
}

test "IP.v4.multicast" {

    var i: u16 = 224;
    while (i <= 239) : (i += 1) {
        var a4 = Ipv4Addr.new(@truncate(u8, i),1,2,3);
        var v4 = IpAddr.from_ipv4(a4);

        assert(a4.is_unspecified() == false);
        assert(a4.is_loopback() == false);
        assert(a4.is_multicast() == true);
        assert(a4.is_broadcast() == false);
        assert(a4.is_link_local() == false);
        assert(a4.is_private() == false);
        assert(a4.is_global() == true);

        assert(v4.is_ipv4() == true);
        assert(v4.is_ipv6() == false);
        assert(v4.is_unspecified() == false);
        assert(v4.is_loopback() == false);
    }
}

test "Ip.v4.v6.compatible" {
    var v6a = Ipv6Addr.new(0, 0, 0, 0, 0, 0, 49152, 767);
    var v6b = Ipv4Addr.new(192, 0, 2, 255).to_ipv6_compatible();
    assert(v6a.eql(v6b) == true);
}

test "Ip.v4.v6.mapped" {
    var v6a = Ipv6Addr.new(0, 0, 0, 0, 0, 65535, 49152, 767);
    var v6b = Ipv4Addr.new(192, 0, 2, 255).to_ipv6_mapped();
    assert(v6a.eql(v6b) == true);
}

test "Ip.v4.to.from.sockaddr" {
    var v4a = Ipv4Addr.new(192, 0, 2, 255);
    var sa = v4a.to_sockaddr(123);
    var v4b = Ipv4Addr.from_sockaddr(&sa);

    assert(v4a.eql(v4b) == true);
}

test "Ip.v6.format" {
    var v6a = Ipv6Addr.new(0, 0, 0, 0, 0, 0, 49152, 767);
    var v6b = Ipv4Addr.new(192, 0, 2, 255).to_ipv6_compatible();
    assert(v6a.eql(v6b) == true);

    var buf = []u8 {0} ** 64;
    var b: []u8 = undefined;
    b = try std.fmt.bufPrint(buf[0..], "{}", &v6a);
    assert(mem.eql(u8, b[0..], "::192.0.2.255"));
    b = try std.fmt.bufPrint(buf[0..], "{}", &v6b);
    assert(mem.eql(u8, b[0..], "::192.0.2.255"));
    b = try std.fmt.bufPrint(buf[0..], "{}", &Ipv6Addr.new(0x2001, 0xdb8, 0, 0, 0, 0, 1, 1));
    assert(mem.eql(u8, b[0..], "2001:db8::1:1"));
    b = try std.fmt.bufPrint(buf[0..], "{}", &Ipv6Addr.new(0, 0, 0, 0, 0, 0xffff, 0xc000, 0x280));
    assert(mem.eql(u8, b[0..], "::ffff:192.0.2.128"));
    b = try std.fmt.bufPrint(buf[0..], "{}", &Ipv6Addr.new(0xae, 0, 0, 0, 0, 0xffff, 0x0102, 0x0304));
    assert(mem.eql(u8, "ae::ffff:102:304", b[0..]));
    // two runs of zeros, equal length
    b = try std.fmt.bufPrint(buf[0..], "{}", &Ipv6Addr.new(1, 0, 0, 4, 5, 0, 0, 8));
    assert(mem.eql(u8, "1::4:5:0:0:8", b[0..]));
    b = try std.fmt.bufPrint(buf[0..], "{}", &Ipv6Addr.new(1, 0, 0, 0, 0, 0, 0, 0));
    assert(mem.eql(u8, "1::", b[0..]));
    // two runs of zeros, second one is longer
    b = try std.fmt.bufPrint(buf[0..], "{}", &Ipv6Addr.new(1, 0, 0, 4, 0, 0, 0, 8));
    assert(mem.eql(u8, "1:0:0:4::8", b[0..]));
    b = try std.fmt.bufPrint(buf[0..], "{}", &Ipv6Addr.unspecified());
    assert(mem.eql(u8, "::", b[0..]));
    b = try std.fmt.bufPrint(buf[0..], "{}", &Ipv6Addr.localhost());
    assert(mem.eql(u8, "::1", b[0..]));
}

test "IP.v6.misc" {
    assert(mem.eql(u16, Ipv6Addr.new(0, 0, 0, 0, 0, 0xffff, 0xc00a, 0x2ff).segments(),
                   []u16 {0, 0, 0, 0, 0, 0xffff, 0xc00a, 0x2ff}));
    assert(Ipv6Addr.new(0, 0, 0, 0, 0, 0xffff, 0xc00a, 0x2ff).is_unspecified() == false);
    assert(Ipv6Addr.new(0, 0, 0, 0, 0, 0, 0, 0).is_unspecified() == true);
    assert(Ipv6Addr.new(0, 0, 0, 0, 0, 0xffff, 0xc00a, 0x2ff).is_loopback() == false);
    assert(Ipv6Addr.new(0, 0, 0, 0, 0, 0, 0, 0x1).is_loopback() == true);
    assert(Ipv6Addr.new(0, 0, 0, 0, 0, 0xffff, 0xc00a, 0x2ff).is_global() == true);
    assert(Ipv6Addr.new(0, 0, 0, 0, 0, 0, 0, 0x1).is_global() == false);
    assert(Ipv6Addr.new(0, 0, 0x1c9, 0, 0, 0xafc8, 0, 0x1).is_global() == true);
    assert(Ipv6Addr.new(0, 0, 0, 0, 0, 0xffff, 0xc00a, 0x2ff).is_unique_local() == false);
    assert(Ipv6Addr.new(0xfc02, 0, 0, 0, 0, 0, 0, 0).is_unique_local() == true);
    assert(Ipv6Addr.new(0, 0, 0, 0, 0, 0xffff, 0xc00a, 0x2ff).is_unicast_link_local() == false);
    assert(Ipv6Addr.new(0xfe8a, 0, 0, 0, 0, 0, 0, 0).is_unicast_link_local() == true);
    assert(Ipv6Addr.new(0, 0, 0, 0, 0, 0xffff, 0xc00a, 0x2ff).is_unicast_site_local() == false);
    assert(Ipv6Addr.new(0xfec2, 0, 0, 0, 0, 0, 0, 0).is_unicast_site_local() == true);
    assert(Ipv6Addr.new(0, 0, 0, 0, 0, 0xffff, 0xc00a, 0x2ff).is_documentation() == false);
    assert(Ipv6Addr.new(0x2001, 0xdb8, 0, 0, 0, 0, 0, 0).is_documentation() == true);
    assert(Ipv6Addr.new(0x2001, 0xdb8, 0, 0, 0, 0, 0, 0).is_unicast_global() == false);
    assert(Ipv6Addr.new(0, 0, 0, 0, 0, 0xffff, 0xc00a, 0x2ff).is_unicast_global() == true);
    //assert(Ipv6Addr.new(0xff0e, 0, 0, 0, 0, 0, 0, 0).multicast_scope() == Ipv6MulticastScope.Global);
    if (Ipv6Addr.new(0xff0e, 0, 0, 0, 0, 0, 0, 0).multicast_scope()) |scope| {
        assert(scope == Ipv6MulticastScope.Global);
    } else {
        assert(false);
    }
    assert(Ipv6Addr.new(0, 0, 0, 0, 0, 0xffff, 0xc00a, 0x2ff).multicast_scope() == null);
    assert(Ipv6Addr.new(0xff00, 0, 0, 0, 0, 0, 0, 0).is_multicast() == true);
    assert(Ipv6Addr.new(0, 0, 0, 0, 0, 0xffff, 0xc00a, 0x2ff).is_multicast() == false);
    assert(Ipv6Addr.new(0xff00, 0, 0, 0, 0, 0, 0, 0).to_ipv4() == null);
    /// assert(Ipv6Addr.new(0, 0, 0, 0, 0, 0xffff, 0xc00a, 0x2ff).to_ipv4(),
    ///            Some(Ipv4Addr.new(192, 10, 2, 255)));
    var mv4a = Ipv6Addr.new(0, 0, 0, 0, 0, 0xffff, 0xc00a, 0x2ff).to_ipv4();
    var v4b = Ipv4Addr.new(192, 10, 2, 255);
    if (mv4a) |v4a| {
        assert(v4a.eql(&v4b));
    } else {
        assert(false);
    }
    /// assert(Ipv6Addr.new(0, 0, 0, 0, 0, 0, 0, 1).to_ipv4(),
    ///            Some(Ipv4Addr.new(0, 0, 0, 1)));
    mv4a = Ipv6Addr.new(0, 0, 0, 0, 0, 0, 0, 1).to_ipv4();
    v4b = Ipv4Addr.new(0, 0, 0, 1);
    if (mv4a) |v4a| {
        assert(v4a.eql(&v4b));
    } else {
        assert(false);
    }
    assert(mem.eql(u8, Ipv6Addr.new(0xff00, 0, 0, 0, 0, 0, 0, 0).octets(),
                   []u8 {0xff, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}));
}
