//! Synthetic `@import("build_options")` for libghostty-vt under rules_zig.
//! Fields match Ghostty Config.addOptions used at comptime by lib-vt paths.

pub const flatpak: bool = false;
pub const snap: bool = false;
pub const x11: bool = false;
pub const wayland: bool = false;
pub const sentry: bool = false;
/// lib-vt builds with SIMD off to avoid highway/simdutf system deps.
pub const simd: bool = false;
pub const i18n: bool = false;
pub const wasm_shared: bool = false;

pub const app_runtime: enum { none, gtk, glfw, browser } = .none;
pub const font_backend: enum { none, freetype, coretext } = .none;
pub const renderer: enum { none, opengl, metal, webgl } = .none;
pub const exe_entrypoint: enum { ghostty, helpgen, mdgen_ghostty, mdgen_list, webdata, website } = .ghostty;
pub const wasm_target: enum { browser, nodejs, wasi } = .browser;

pub const app_version: @import("std").SemanticVersion = .{
    .major = 0,
    .minor = 1,
    .patch = 0,
    .pre = "flutter",
};
pub const app_version_string: [:0]const u8 = "0.1.0-flutter";
pub const lib_version: @import("std").SemanticVersion = .{
    .major = 0,
    .minor = 1,
    .patch = 0,
};
pub const lib_version_string: [:0]const u8 = "0.1.0";
pub const release_channel: enum { stable, tip } = .tip;
