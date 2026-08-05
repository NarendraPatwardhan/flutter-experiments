"""Codegen for the Ghostty pin adapter — Starlark actions only (no shell genrules)."""

load("@bazel_skylib//lib:paths.bzl", "paths")

def _pick_file_impl(ctx):
    for f in ctx.files.srcs:
        if f.basename == ctx.attr.basename:
            return DefaultInfo(files = depset([f]))
    fail("pick_file: no file named %s in %s" % (ctx.attr.basename, ctx.attr.srcs))

pick_file = rule(
    implementation = _pick_file_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True, mandatory = True),
        "basename": attr.string(mandatory = True),
    },
)

def _uucode_staged_src_impl(ctx):
    """Symlink lib srcs + run generator to produce tables.zig beside them."""
    prefix = ctx.label.name

    staged_srcs = []
    for src in ctx.files.lib_srcs:
        out = ctx.actions.declare_file("%s/src/%s" % (prefix, src.basename))
        ctx.actions.symlink(output = out, target_file = src)
        staged_srcs.append(out)

    tables = ctx.actions.declare_file("%s/src/tables.zig" % prefix)

    root_zig = None
    for f in ctx.files.uucode_tree:
        if f.basename == "root.zig" and f.dirname.endswith("/src"):
            root_zig = f
            break
    if root_zig == None:
        fail("could not find uucode src/root.zig in uucode_tree")

    uucode_root = paths.dirname(root_zig.dirname)

    ctx.actions.run(
        executable = ctx.executable._chdir_exec,
        arguments = [
            uucode_root,
            ctx.executable.generator.path,
            tables.path,
        ],
        inputs = depset(
            direct = ctx.files.uucode_tree + staged_srcs + [
                ctx.executable.generator,
                ctx.executable._chdir_exec,
            ],
        ),
        outputs = [tables],
        mnemonic = "UucodeGenerateTables",
        progress_message = "Generating uucode tables.zig",
    )

    return [DefaultInfo(files = depset(staged_srcs + [tables]))]

uucode_staged_src = rule(
    implementation = _uucode_staged_src_impl,
    attrs = {
        "lib_srcs": attr.label_list(allow_files = [".zig"], mandatory = True),
        "uucode_tree": attr.label(allow_files = True, mandatory = True),
        "generator": attr.label(
            executable = True,
            cfg = "exec",
            mandatory = True,
        ),
        "_chdir_exec": attr.label(
            default = Label("//third_party/ghostty:chdir_exec"),
            executable = True,
            cfg = "exec",
        ),
    },
)

def _run_stdout_file_impl(ctx):
    out = ctx.outputs.out
    args = [out.path, ctx.executable.tool.path] + ctx.attr.tool_args
    ctx.actions.run(
        executable = ctx.executable._stdout_to_file,
        arguments = args,
        inputs = depset(
            direct = [ctx.executable.tool, ctx.executable._stdout_to_file] + ctx.files.srcs,
        ),
        outputs = [out],
        mnemonic = "ZigStdoutToFile",
        progress_message = "Capturing stdout of %s" % ctx.executable.tool.short_path,
    )
    return [DefaultInfo(files = depset([out]))]

run_stdout_file = rule(
    implementation = _run_stdout_file_impl,
    attrs = {
        "tool": attr.label(executable = True, cfg = "exec", mandatory = True),
        "tool_args": attr.string_list(),
        "srcs": attr.label_list(allow_files = True),
        "out": attr.output(mandatory = True),
        "_stdout_to_file": attr.label(
            default = Label("//third_party/ghostty:stdout_to_file"),
            executable = True,
            cfg = "exec",
        ),
    },
)
