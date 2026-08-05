# Injected into @uucode (http_archive). Source filegroups only — no product logic.

exports_files(glob(["**/*"]))

filegroup(
    name = "lib_zig",
    srcs = [
        "src/ascii.zig",
        "src/build_config.zig",  # from 0001-single-module-imports.patch
        "src/code_point.zig",
        "src/components.zig",
        "src/config.zig",
        "src/fields.zig",
        "src/get.zig",
        "src/grapheme.zig",
        "src/multi_slice.zig",
        "src/quirks.zig",
        "src/root.zig",
        "src/storage.zig",
        "src/types.zig",
        "src/utf8.zig",
    ],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "generate_zig",
    srcs = [
        "src/ascii.zig",
        "src/build_config.zig",
        "src/code_point.zig",
        "src/components.zig",
        "src/config.zig",
        "src/fields.zig",
        "src/generate.zig",
        "src/get.zig",
        "src/grapheme.zig",
        "src/multi_slice.zig",
        "src/quirks.zig",
        "src/root.zig",
        "src/storage.zig",
        "src/types.zig",
        "src/utf8.zig",
    ],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "ucd",
    srcs = glob(["ucd/**"]),
    visibility = ["//visibility:public"],
)

filegroup(
    name = "tree",
    srcs = glob(
        ["**/*"],
        exclude = [".git/**"],
    ),
    visibility = ["//visibility:public"],
)
