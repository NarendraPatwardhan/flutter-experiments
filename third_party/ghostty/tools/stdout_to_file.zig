//! Run a program and write its stdout to a file.
//! Usage: stdout_to_file <out_path> <program> [args...]
//! Zig 0.16: std.process.run + Io.Dir.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args_iter = try init.minimal.args.iterateAllocator(gpa);
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

    const result = try std.process.run(gpa, io, .{
        .argv = child_argv.items,
    });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    var out_file = try std.Io.Dir.cwd().createFile(io, out_path, .{});
    defer out_file.close(io);
    var buf: [4096]u8 = undefined;
    var w = out_file.writer(io, &buf);
    try w.interface.writeAll(result.stdout);
    try w.interface.flush();

    if (result.stderr.len > 0) {
        std.debug.print("{s}", .{result.stderr});
    }

    switch (result.term) {
        .exited => |code| std.process.exit(code),
        else => std.process.exit(1),
    }
}

fn usage() noreturn {
    std.debug.print("usage: stdout_to_file <out_path> <program> [args...]\n", .{});
    std.process.exit(2);
}
