const std = @import("std");
const VERSION = "0.0.0";

const Commands = enum { @"-h", @"--help", @"-v", @"--version", default };

const RESET = "\x1b[0m";
const BRIGHT_BLUE = "\x1b[94m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";

const RepoInfo = struct {
    name: []const u8,
    nameWithOwner: []const u8,
};

const RepoList = []RepoInfo;

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = GPA.deinit();
    const allocator = GPA.allocator();
    const stdout = std.io.getStdOut().writer();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len >= 2) {
        const command = std.meta.stringToEnum(Commands, args[1]) orelse Commands.default;
        switch (command) {
            .@"-h", .@"--help" => {
                try stdout.print("Usage: {s}{s}\n{s}version{s}: Print the version\n{s}help{s}: Print this help\n", .{
                    BRIGHT_BLUE,
                    args[0],
                    YELLOW,
                    RESET,
                    YELLOW,
                    RESET,
                });
                std.process.exit(0);
            },
            .@"-v", .@"--version" => {
                try stdout.print("{s}", .{VERSION});
                std.process.exit(0);
            },
            else => {},
        }
    }

    if (args.len >= 2 and std.mem.eql(u8, args[1], "version")) {
        try stdout.print("{s}", .{VERSION});
        std.process.exit(0);
    }

    const name = if (args.len >= 2 and args[1][0] != '-') try allocator.dupe(u8, args[1]) else blk: {
        _ = try stdout.write("Please provide a user/organization name: ");
        var input = std.ArrayList(u8).init(allocator);
        try std.io.getStdIn().reader().streamUntilDelimiter(input.writer(), '\n', 64);
        if (@import("builtin").os.tag == .windows) _ = input.pop();
        break :blk try input.toOwnedSlice();
    };
    defer allocator.free(name);

    const list = try run(allocator, @constCast(&[_][]const u8{ "gh", "repo", "list", name, "--json", "nameWithOwner,name" }), null);
    defer {
        allocator.free(list.stdout);
        allocator.free(list.stderr);
    }
    switch (list.term.Exited) {
        0 => {
            const parsed = try std.json.parseFromSlice(RepoList, allocator, list.stdout, .{});
            defer parsed.deinit();

            try std.fs.cwd().makeDir(args[1]);

            for (parsed.value) |repo| {
                const result = try run(allocator, @constCast(&[_][]const u8{ "gh", "repo", "clone", repo.nameWithOwner }), args[1]);
                defer {
                    allocator.free(result.stdout);
                    allocator.free(result.stderr);
                }
                switch (result.term.Exited) {
                    0 => std.debug.print("{s}Cloned {s}{s}{s}\n", .{GREEN, BRIGHT_BLUE, repo.nameWithOwner, RESET}),
                    1 => std.debug.print("Error: {s}\n", .{result.stderr}),
                    else => std.debug.print("Unexpected error: {} (when running\n", .{result.term.Exited}),
                }
            }
        },
        1 => std.debug.print("Error: {s}\n", .{list.stderr}),
        else => std.debug.print("Unexpected error: {} (when running\n", .{list.term.Exited}),
    }
}

fn run(
    allocator: std.mem.Allocator,
    args: [][]const u8,
    subpath: ?[]const u8,
) !std.process.Child.RunResult {
    const cwd = try std.fs.cwd().realpathAlloc(allocator, subpath orelse ".");
    defer allocator.free(cwd);

    const cp = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = args,
        .cwd = cwd,
    });

    return cp;
}
