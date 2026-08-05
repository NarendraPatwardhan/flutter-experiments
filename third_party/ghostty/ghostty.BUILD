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
