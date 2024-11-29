const std = @import("std");

pub fn spawn(allocator: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8) !std.process.Child {
    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.cwd = cwd;
    try child.spawn();
    return child;
}

pub fn wait(allocator: std.mem.Allocator, process: *std.process.Child) !std.process.Child.RunResult {
    var stdout = std.ArrayList(u8).init(allocator);
    var stderr = std.ArrayList(u8).init(allocator);
    try process.collectOutput(&stdout, &stderr, 4096);

    const term = try process.wait();

    return .{ .term = term, .stdout = try stdout.toOwnedSlice(), .stderr = try stderr.toOwnedSlice() };
}

pub fn run(
    allocator: std.mem.Allocator,
    args: [][]const u8,
    subpath: ?[]const u8,
) !std.process.Child.RunResult {
    const cp = std.process.Child.run(.{
        .allocator = allocator,
        .argv = args,
        .cwd = subpath,
    }) catch |err| {
        if (err == error.FileNotFound and std.mem.eql(u8, args[0], "gh")) {
            return error.GithubCliNotFound;
        }
        return err;
    };
    return cp;
}
