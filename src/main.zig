const std = @import("std");
const VERSION = "0.1.0";

const Commands = enum { @"-h", @"--help", @"-v", @"--version", default };

const RESET = "\x1b[0m";
const BRIGHT_BLUE = "\x1b[94m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";

const RepoInfo = struct {
    name: []const u8,
    nameWithOwner: []const u8,
    owner: struct {
        id: []const u8,
        login: []const u8,
    },
};

const RepoList = []RepoInfo;

const WorkspaceFolder = struct {
    path: []const u8,
};

const Workspace = struct {
    folders: []WorkspaceFolder,
};

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
        _ = try stdout.writeAll("Please provide a user/organization name(defaults to yourself): ");
        var input = std.ArrayList(u8).init(allocator);
        try std.io.getStdIn().reader().streamUntilDelimiter(input.writer(), '\n', 64);
        if (@import("builtin").os.tag == .windows) _ = input.pop();
        break :blk try input.toOwnedSlice();
    };
    defer allocator.free(name);

    const list = try run(allocator, @constCast(&[_][]const u8{ "gh", "repo", "list", name, "--json", "nameWithOwner,name,owner" }), null);
    defer {
        allocator.free(list.stdout);
        allocator.free(list.stderr);
    }
    switch (list.term.Exited) {
        // Command ran fine, parsing the output
        0 => {
            const parsed = std.json.parseFromSlice(RepoList, allocator, list.stdout, .{}) catch |err| {
                std.debug.print("Failed to parse repository list: {s}\n", .{list.stdout});
                return err;
            };
            defer parsed.deinit();

            // Handles if the user provides no name, which fallbacks to his own repositories
            const ghName = parsed.value[0].owner.login;

            std.fs.cwd().makeDir(ghName) catch |err| {
                if (err == error.PathAlreadyExists) {
                    try stdout.print("[Warning] {s}Directory {s}{s}{s} already exists\n", .{YELLOW, BRIGHT_BLUE, ghName, RESET});
                } else {
                    // TODO
                    return err;
                }
            };

            for (parsed.value) |repo| {
                // TODO: parallel cloning of repositories
                const result = try run(allocator, @constCast(&[_][]const u8{ "gh", "repo", "clone", repo.nameWithOwner }), ghName);
                defer {
                    allocator.free(result.stdout);
                    allocator.free(result.stderr);
                }
                switch (result.term.Exited) {
                    0 => _ = try stdout.print("{s}Cloned {s}{s}{s}\n", .{GREEN, BRIGHT_BLUE, repo.nameWithOwner, RESET}),
                    1 => std.debug.print("Error: {s}\n", .{result.stderr}),
                    else => std.debug.print("Unexpected error: {} (when running\n", .{result.term.Exited}),
                }
            }

            // Generate workspace file
            var foldersList = try std.ArrayList(WorkspaceFolder).initCapacity(allocator, parsed.value.len);
            defer foldersList.deinit();
            for (parsed.value) |repo| {
                foldersList.appendAssumeCapacity(WorkspaceFolder{ .path = repo.name });
            }
            const folders = foldersList.items;

            const workspace = Workspace{ .folders = folders };

            const workspaceFilePath = try std.mem.concat(allocator, u8, &.{ ghName, "/workspace.code-workspace"});
            defer allocator.free(workspaceFilePath);
            const workspaceFile = try std.fs.cwd().createFile(workspaceFilePath, .{ });
            defer workspaceFile.close();

            var workspaceJson = std.ArrayList(u8).init(allocator);
            defer workspaceJson.deinit();
            try std.json.stringify(workspace, .{ }, workspaceJson.writer());

            try workspaceFile.writeAll(workspaceJson.items);
        },
        // Probably just an invalid user/organization name
        1 => {
            std.debug.print("Error: {s}\n", .{list.stderr});
            std.debug.print("Unable to fetch repository list for {s}\n", .{name});
        },
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
