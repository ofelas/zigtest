const std = @import("std");
const assert = std.debug.assert;
const warn = std.debug.warn;
pub const IpAddr = @import("ip.zig").IpAddr;
pub const Ipv4Addr = @import("ip.zig").Ipv4Addr;
pub const Ipv6Addr = @import("ip.zig").Ipv6Addr;
pub const sockaddr_in = std.os.linux.sockaddr_in;
pub const sockaddr_in6 = std.os.linux.sockaddr_in6;

pub const SocketAddr = union(enum) {
    const Self = this;

    /// An IPv4 socket address.
    V4: SocketAddrV4,
    /// An IPv6 socket address.
    V6: SocketAddrV6,

    pub fn new(ip_: IpAddr, port_: u16) SocketAddr {
        return switch (ip_) {
            IpAddr.V4 => |a| SocketAddr{.V4 = SocketAddrV4.new(a, port_)},
            IpAddr.V6 => |a| SocketAddr{.V6 = SocketAddrV6.new(a, port_, 0, 0)},
        };
    }

    pub fn ip(self: *const Self) IpAddr {
        return switch (self.*) {
            SocketAddr.V4 => |*a| IpAddr{.V4 = a.*.ip().*},
            SocketAddr.V6 => |*a| IpAddr{.V6 = a.*.ip().*},
        };
    }

    pub fn set_ip(self: *Self, new_ip: IpAddr) void {
        // `switch (*self, new_ip)` would have us mutate a copy of self only to throw it away.
        switch (self.*) {
            SocketAddr.V4 => |*a| {
                switch (new_ip) {
                    IpAddr.V4 => |*aa| {
                        a.*.set_ip(aa.*);
                    },
                    else => unreachable,
                }
            },
            SocketAddr.V6 => |*a| {
                switch (new_ip) {
                    IpAddr.V6 => |*aa| {
                        
                    },
                    else => unreachable,
                }
            },
        }
        // switch (self, new_ip) {
        //     (&mut SocketAddr.V4(ref mut a), IpAddr.V4(new_ip)) => a.set_ip(new_ip),
        //     (&mut SocketAddr.V6(ref mut a), IpAddr.V6(new_ip)) => a.set_ip(new_ip),
        //     (self_, new_ip) => *self_ = Self.new(new_ip, self_.port()),
        // }
    }

    pub fn port(self: *const Self) u16 {
        return switch (self.*) {
            SocketAddr.V4 => |*a| a.port(),
            SocketAddr.V6 => |*a| a.port(),
        };
    }

    pub fn set_port(self: *Self, new_port: u16) void {
        return switch (self.*) {
            SocketAddr.V4 => |*a| a.set_port(new_port),
            SocketAddr.V6 => |*a| a.set_port(new_port),
        };
    }

    pub fn is_ipv4(self: *const Self) bool {
        return switch (self.*) {
            SocketAddr.V4 => |_| true,
            SocketAddr.V6 => |_| false,
        };
    }

    pub fn is_ipv6(self: *const Self) bool {
        return switch (self.*) {
            SocketAddr.V4 => |_| false,
            SocketAddr.V6 => |_| true,
        };
    }
};

pub const SocketAddrV4 = struct {
    const Self = this;

    inner: sockaddr_in,

    pub fn new(ip_: Ipv4Addr, port_: u16) SocketAddrV4 {
        return SocketAddrV4 {
            .inner = sockaddr_in {
                .family = std.os.posix.AF_INET,
                .addr = ip_.inner.s_addr,
                .port = std.mem.endianSwapIfLe(@typeOf(port_), port_), // swapifle
                .zero = []u8 {0} ** 8,
            },
        };
    }

    pub fn port(self: *const Self) u16 {
        return std.mem.endianSwapIfLe(u16, self.inner.port);
    }

    pub fn set_port(self: *Self, new_port: u16) void {
        self.inner.port = std.mem.endianSwapIfLe(@typeOf(new_port), new_port);
    }

    pub fn ip(self: *const Self) *const Ipv4Addr {
        return @ptrCast(*const Ipv4Addr, &self.inner.addr);
    }

    pub fn set_ip(self: *Self, new_ip: Ipv4Addr) void {
        self.*.inner.addr = new_ip.inner.s_addr;
    }
};

pub const SocketAddrV6 = struct {
    const Self = this;

    inner: sockaddr_in6,

    pub fn new(ip_: Ipv6Addr, port_: u16, flowinfo: u32, scope_id: u32) SocketAddrV6 {
        return SocketAddrV6 {
            .inner = sockaddr_in6 {
                .family = std.os.posix.AF_INET6,
                .port = std.mem.endianSwapIfLe(@typeOf(port_), port_),    // swapifle
                .addr = ip_.inner.s6_addr,
                .flowinfo = flowinfo,
                .scope_id = scope_id,
                //.. unsafe { mem::zeroed() }
            },
        };
    }

    pub fn port(self: *const Self) u16 {
        return std.mem.endianSwapIfLe(u16, self.inner.port);
    }

    pub fn set_port(self: *Self, new_port: u16) void {
        self.inner.port = std.mem.endianSwapIfLe(@typeOf(new_port), new_port);
    }

    pub fn ip(self: *const Self) *const Ipv6Addr {
        return @ptrCast(*const Ipv6Addr, &self.inner.addr);
    }

};

test "SocketAddr.misc" {
    var sa4 = SocketAddr.new(IpAddr.from_ipv4(Ipv4Addr.localhost()), 1234);
    var sa6 = SocketAddr.new(IpAddr.from_ipv6(Ipv6Addr.unspecified()), 1234);

    assert(sa4.is_ipv4() == true);
    assert(sa4.is_ipv6() == false);

    assert(sa6.is_ipv4() == false);
    assert(sa6.is_ipv6() == true);

    const p4 = sa4.port();
    const p6 = sa6.port();

    sa4.set_port(1099);
    sa6.set_port(1066);

    assert(sa4.port() == 1099);
    assert(sa6.port() == 1066);

    var ip4 = sa4.ip();
    warn("ip4={}\n", &ip4);

    var ip6 = sa6.ip();
    warn("ip6={}\n", &ip6);

    sa4.set_ip(IpAddr.from_ipv4(Ipv4Addr.new(10,10,10,10)));
    warn("sa4.ip()={}\n", &sa4.ip());
}

//why for a struct with fn port(self: *const Self) u16,... fn otherfn(self: *Self, port: u16)... gives redefinition of port
