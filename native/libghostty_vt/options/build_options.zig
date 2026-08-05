//! Synthetic `@import("build_options")` for libghostty-vt under rules_zig.
//! Mirrors fields Ghostty's Config.addOptions exposes that lib-vt needs.
//! Keep c_abi/lib-vt oriented; no Ghostty GUI app options.

pub const app_runtime: []const u8 = "none";
pub const font_backend: []const u8 = "none";
pub const renderer: []const u8 = "none";
