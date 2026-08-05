# Injected into @ghostty (http_archive). Source filegroups only — no product logic.

exports_files(glob(["**/*"]))

filegroup(
    name = "all_srcs",
    srcs = glob(
        ["**/*"],
        exclude = [
            ".git/**",
            "zig-cache/**",
            "zig-out/**",
            ".zig-cache/**",
            "macos/**",
            "nix/**",
            "vendor/**",
            "dist/**",
        ],
    ),
    visibility = ["//visibility:public"],
)

# Include *_test.zig too: some Ghostty sources @import them at comptime.
filegroup(
    name = "zig_srcs",
    srcs = glob([
        "src/**/*.zig",
        "pkg/**/*.zig",
    ]),
    visibility = ["//visibility:public"],
)

filegroup(
    name = "headers",
    srcs = glob(["include/ghostty/**/*.h"]),
    visibility = ["//visibility:public"],
)

# @embedFile assets (rgb.txt, fonts, etc.) needed by src/**/*.zig
filegroup(
    name = "embed_files",
    srcs = glob(
        [
            "src/**/res/**",
            "pkg/**/res/**",
        ],
        allow_empty = True,
    ),
    visibility = ["//visibility:public"],
)
