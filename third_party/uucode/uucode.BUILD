# @uucode sources for rules_zig (Ghostty lib-vt Unicode dependency).

exports_files(glob(["**/*"]))

# Explicit list — rules_zig needs real .zig files in srcs (not only a filegroup label).
UUCODE_LIB_ZIG = [
    "src/ascii.zig",
    "src/build_config.zig",  # added by 0001-single-module-imports.patch
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
]

UUCODE_GENERATE_ZIG = UUCODE_LIB_ZIG + [
    "src/generate.zig",
]

filegroup(
    name = "lib_zig",
    srcs = UUCODE_LIB_ZIG,
    visibility = ["//visibility:public"],
)

filegroup(
    name = "generate_zig",
    srcs = UUCODE_GENERATE_ZIG,
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
