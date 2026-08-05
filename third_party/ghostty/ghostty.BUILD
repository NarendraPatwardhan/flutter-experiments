# @ghostty pin — sources for rules_zig (no shell zig build).
# Compilation targets live in //native/libghostty_vt (product module graph).

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

filegroup(
    name = "zig_srcs",
    srcs = glob(
        [
            "src/**/*.zig",
            "pkg/**/*.zig",
        ],
        exclude = [
            "src/**/*_test.zig",
        ],
    ),
    visibility = ["//visibility:public"],
)

filegroup(
    name = "headers",
    srcs = glob(["include/ghostty/**/*.h"]),
    visibility = ["//visibility:public"],
)

filegroup(
    name = "lib_vt_main",
    srcs = ["src/lib_vt.zig"],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "uucode_config",
    srcs = ["src/build/uucode_config.zig"],
    visibility = ["//visibility:public"],
)
