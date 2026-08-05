//! Run a program after chdir to a root directory.
//! Usage: chdir_exec <root> <program> [args...]
//! Zig 0.16 process.Init API.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.arena.allocator();
    const io = init.io;

    var args_iter = try init.args.iterateAllocator(gpa);
    defer args_iter.deinit();
    _ = args_iter.next(); // argv0

    const root = args_iter.next() orelse usage();
    const program_rel = args_iter.next() orelse usage();

    const cwd = try std.fs.cwd().realpathAlloc(gpa, ".");
    const abs_root = try absPath(gpa, cwd, root);
    const abs_program = try absPath(gpa, cwd, program_rel);

    var child_argv: std.ArrayList([]const u8) = .empty;
    try child_argv.append(gpa, abs_program);
    while (args_iter.next()) |a| {
        try child_argv.append(gpa, try absPath(gpa, cwd, a));
    }

    var child = std.process.Child.init(child_argv.items, gpa);
    child.cwd = abs_root;
    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| std.process.exit(code),
        else => std.process.exit(1),
    }
    _ = io;
}

fn usage() noreturn {
    std.debug.print("usage: chdir_exec <root> <program> [args...]\n", .{});
    std.process.exit(2);
}

fn absPath(gpa: std.mem.Allocator, cwd: []const u8, p: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(p)) return try gpa.dupe(u8, p);
    return try std.fs.path.resolve(gpa, &.{ cwd, p });
}
