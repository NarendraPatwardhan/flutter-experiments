//! Stub only for compiling unicode *generators* (their test blocks import this).
//! Product targets use the real generated tables, not this file.

pub fn Tables(comptime Elem: type) type {
    return struct {
        pub const stage1: [1]u16 = .{0};
        pub const stage2: [1]u16 = .{0};
        pub const stage3: [1]Elem = .{undefined};
    };
}
