//! Run a program and write its stdout to a file.
//! Usage: stdout_to_file <out_path> <program> [args...]
//! Zig 0.16 process.Init API.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var args_iter = try init.minimal.args.initAllocator(gpa);
    defer args_iter.deinit();
    _ = args_iter.next();

    const out_path = args_iter.next() orelse usage();
    const program = args_iter.next() orelse usage();

    var child_argv: std.ArrayList([]const u8) = .empty;
    defer child_argv.deinit(gpa);
    try child_argv.append(gpa, program);
    while (args_iter.next()) |a| {
        try child_argv.append(gpa, a);
    }

    const out_file = try std.fs.cwd().createFile(out_path, .{});
    defer out_file.close();

    var child = std.process.Child.init(child_argv.items, gpa);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    try child.spawn();

    const stdout = child.stdout orelse unreachable;
    var buf: [64 * 1024]u8 = undefined;
    while (true) {
        const n = try stdout.read(buf[0..]);
        if (n == 0) break;
        try out_file.writeAll(buf[0..n]);
    }

    const term = try child.wait();
    switch (term) {
        .Exited => |code| std.process.exit(code),
        else => std.process.exit(1),
    }
}

fn usage() noreturn {
    std.debug.print("usage: stdout_to_file <out_path> <program> [args...]\n", .{});
    std.process.exit(2);
}
