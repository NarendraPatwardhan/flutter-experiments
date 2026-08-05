# @uucode — Zig module used by Ghostty libghostty-vt.
# Tables generation is owned by //native/libghostty_vt (Bazel actions).

exports_files(glob(["**/*"]))

filegroup(
    name = "zig_srcs",
    srcs = glob(["src/**/*.zig"]),
    visibility = ["//visibility:public"],
)

filegroup(
    name = "root",
    srcs = ["src/root.zig"],
    visibility = ["//visibility:public"],
)
