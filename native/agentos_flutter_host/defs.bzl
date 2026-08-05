"""Always-opt product host cdylib (same idea as agent-os hosts/wasmtime/defs.bzl).

fastbuild/debug wasmtime is large and slow. Transition the whole host subgraph to
compilation_mode=opt regardless of the top-level -c.

Stripping is a separate genrule that runs after this target (see BUILD.bazel).
"""

def _host_release_transition_impl(_settings, _attr):
    return {"//command_line_option:compilation_mode": "opt"}

_host_release_transition = transition(
    implementation = _host_release_transition_impl,
    inputs = [],
    outputs = ["//command_line_option:compilation_mode"],
)

def _host_release_shared_library_impl(ctx):
    lib = ctx.attr.lib[0]
    default = lib[DefaultInfo]

    shared = None
    for file in default.files.to_list():
        if file.extension in ["so", "dylib", "dll"]:
            shared = file
            break
    if not shared:
        fail("host_release_shared_library expected a shared library output")

    out = ctx.actions.declare_file(ctx.attr.out if ctx.attr.out else shared.basename)
    ctx.actions.symlink(output = out, target_file = shared)
    return [DefaultInfo(
        files = depset([out]),
        runfiles = ctx.runfiles(files = [out]).merge(default.default_runfiles),
    )]

host_release_shared_library = rule(
    implementation = _host_release_shared_library_impl,
    doc = "Surface a rust_shared_library as always-opt.",
    attrs = {
        "lib": attr.label(
            mandatory = True,
            cfg = _host_release_transition,
            doc = "rust_shared_library built at compilation_mode=opt.",
        ),
        "out": attr.string(
            doc = "Stable output basename (e.g. libagentos_flutter_host_opt.so).",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)
