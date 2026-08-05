# @uucode sources for rules_zig (Ghostty lib-vt Unicode dependency).

exports_files(glob(["**/*"]))

filegroup(
    name = "zig_srcs",
    srcs = glob(["src/**/*.zig"]),
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
