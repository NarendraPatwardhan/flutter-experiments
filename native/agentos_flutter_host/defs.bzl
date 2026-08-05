"""Always-opt + stripped product host cdylib.

Mirrors agent-os hosts/wasmtime release transition, and strips the .so with the
C++ toolchain strip tool (Bazel action — not a shell genrule).
"""

load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain", "use_cpp_toolchain")

def _host_release_transition_impl(_settings, _attr):
    return {
        "//command_line_option:compilation_mode": "opt",
        # Ask Bazel to strip linked outputs in this configuration when rules honor it.
        "//command_line_option:strip": "always",
    }

_host_release_transition = transition(
    implementation = _host_release_transition_impl,
    inputs = [],
    outputs = [
        "//command_line_option:compilation_mode",
        "//command_line_option:strip",
    ],
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

    cc_toolchain = find_cpp_toolchain(ctx)
    strip = cc_toolchain.strip_executable

    # Deterministic strip via the registered C++ toolchain (not PATH `strip`).
    ctx.actions.run(
        executable = strip,
        arguments = [
            "--strip-unneeded",
            "-o",
            out.path,
            shared.path,
        ],
        inputs = depset(
            direct = [shared],
            transitive = [cc_toolchain.all_files],
        ),
        outputs = [out],
        mnemonic = "StripSharedLibrary",
        progress_message = "Stripping %{input}",
        use_default_shell_env = False,
    )

    return [DefaultInfo(
        files = depset([out]),
        runfiles = ctx.runfiles(files = [out]).merge(default.default_runfiles),
    )]

host_release_shared_library = rule(
    implementation = _host_release_shared_library_impl,
    doc = "Always-opt rust_shared_library, stripped with the C++ toolchain.",
    fragments = ["cpp"],
    toolchains = use_cpp_toolchain(),
    attrs = {
        "lib": attr.label(
            mandatory = True,
            cfg = _host_release_transition,
            doc = "rust_shared_library built at compilation_mode=opt.",
        ),
        "out": attr.string(
            doc = "Stable output basename (e.g. libagentos_flutter_host.so).",
        ),
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)
