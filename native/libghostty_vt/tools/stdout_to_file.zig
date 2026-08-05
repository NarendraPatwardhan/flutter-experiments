//! Run a program and write its stdout to a file.
//! Usage: stdout_to_file <out_path> <program> [args...]

const std = @import("std");

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    var argv = try std.process.argsWithAllocator(gpa);
    defer argv.deinit();
    _ = argv.next();

    const out_path = argv.next() orelse usage();
    const program = argv.next() orelse usage();

    var child_argv: std.ArrayList([]const u8) = .empty;
    defer child_argv.deinit(gpa);
    try child_argv.append(gpa, program);
    while (argv.next()) |a| try child_argv.append(gpa, a);

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
