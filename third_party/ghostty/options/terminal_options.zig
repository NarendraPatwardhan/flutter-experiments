//! Synthetic `@import("terminal_options")` for libghostty-vt (rules_zig).
//! Matches fields written by Ghostty `terminal/build_options.zig` Options.add
//! for a libghostty-vt C ABI build: no oniguruma, no SIMD, c_abi on.

pub const artifact = enum {
    ghostty,
    lib,
}.lib;

pub const c_abi: bool = true;
pub const oniguruma: bool = false;
pub const simd: bool = false;
pub const slow_runtime_safety: bool = false;
pub const kitty_graphics: bool = true;
pub const tmux_control_mode: bool = false;

pub const version_string: []const u8 = "0.1.0-flutter";
pub const version_major: usize = 0;
pub const version_minor: usize = 1;
pub const version_patch: usize = 0;
pub const version_pre: ?[]const u8 = "flutter";
pub const version_build: ?[]const u8 = null;
