const std = @import("std");
const VERSION = "0.2.1";
const isWindows = @import("builtin").os.tag == .windows;

const Commands = enum {
    clone,
    help,
    version,
    update,
};

const Colors = enum {
    reset,
    brightBlue,
    green,
    yellow,
    red,
    blue,
    magenta,
    cyan,
    white,
    brightBlack,

    const colorCodes = [@typeInfo(Colors).Enum.fields.len][]const u8{
        "\x1b[0m",  // reset
        "\x1b[94m", // brightBlue
        "\x1b[32m", // green
        "\x1b[33m", // yellow
        "\x1b[31m", // red
        "\x1b[34m", // blue
        "\x1b[35m", // magenta
        "\x1b[36m", // cyan
        "\x1b[37m", // white
        "\x1b[90m", // brightBlack
    };

    inline fn code(self: Colors) []const u8 {
        return colorCodes[@intFromEnum(self)];
    }
};

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

    const command = std.meta.stringToEnum(Commands, if (args.len >= 2) args[1] else "help") orelse Commands.help;
    switch (command) {
        .clone => {
            const name = if (args.len >= 3) try allocator.dupe(u8, args[2]) else try promptName(allocator);
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

                    if (parsed.value.len == 0) {
                        try log(.err, "No repositories found for {s}\n", .{name});
                        return;
                    }
                    // Handles if the user provides no name, which fallbacks to his own repositories
                    const ghName = parsed.value[0].owner.login;

                    try createFolder(ghName);

                    for (parsed.value) |repo| {
                        // TODO: parallel cloning of repositories
                        const result = try run(allocator, @constCast(&[_][]const u8{ "gh", "repo", "clone", repo.nameWithOwner }), ghName);
                        defer {
                            allocator.free(result.stdout);
                            allocator.free(result.stderr);
                        }
                        switch (result.term.Exited) {
                            0 => _ = try stdout.print("{s}Cloned {s}{s}{s}\n", .{ Colors.green.code(), Colors.brightBlue.code(), repo.nameWithOwner, Colors.reset.code() }),
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

                    const workspaceFilePath = try std.mem.concat(allocator, u8, &.{ ghName, "/workspace.code-workspace" });
                    defer allocator.free(workspaceFilePath);

                    const workspaceFile = try std.fs.cwd().createFile(workspaceFilePath, .{});
                    defer workspaceFile.close();

                    var workspaceJson = std.ArrayList(u8).init(allocator);
                    defer workspaceJson.deinit();
                    try std.json.stringify(workspace, .{}, workspaceJson.writer());

                    try workspaceFile.writeAll(workspaceJson.items);
                },
                // Probably just an invalid user/organization name
                1 => {
                    try log(.err, "{s}\n", .{list.stderr});
                },
                else => std.debug.print("Unexpected error: {} (when running\n", .{list.term.Exited}),
            }
        },
        .version => {
            try log(.info, "{s}", .{VERSION});
        },
        .update => {
            const updateCommand = if (isWindows)
                &[_][]const u8{
                    "powershell.exe",
                    "-Command",
                    "irm raw.githubusercontent.com/gaskam/workspace/refs/heads/main/install.ps1 | iex",
                }
            else
                &[_][]const u8{
                    "sh",
                    "-c",
                    "curl -fsSL https://raw.githubusercontent.com/gaskam/workspace/refs/heads/main/install.sh | bash",
                };

            const updateResult = try run(
                allocator,
                @constCast(updateCommand),
                null,
            );
            defer {
                allocator.free(updateResult.stdout);
                allocator.free(updateResult.stderr);
            }

            switch (updateResult.term.Exited) {
                0 => try log(.info, "Successfully updated Workspace\n", .{}),
                else => {
                    try log(.err, "Failed to update Workspace: {s}\n", .{updateResult.stderr});
                    return error.UpdateFailed;
                },
            }
        },
        // implicitly also catches `help` command
        else => {
            const helpMessage = 
                "{s}Workspace{s} is a powerful application designed to install and manage all your repositories in your chosen destination.\n\n" ++
                "Usage: workspace <command> {s}<requirement>{s} {s}[...options]{s}\n\n" ++
                "Commands:\n" ++
                "  {s}clone{s} {s}<organization/user>{s} {s}[destination]{s}  Clone all repositories from an organization/user\n\n" ++
                "  {s}version{s}                                  Display version information\n" ++
                "  {s}update{s}                                   Update workspace to the latest version\n\n" ++
                "  {s}help{s}                                     Display help information\n\n" ++
                "{s}e.g. => $ workspace clone ziglang ~/workspace{s} \n\n" ++
                "Contribute about Workspace:                {s}https://github.com/gaskam/workspace{s}\n";
            try log(.help, helpMessage, .{
                Colors.brightBlue.code(),
                Colors.reset.code(),
                Colors.cyan.code(),
                Colors.reset.code(),
                Colors.brightBlack.code(),
                Colors.reset.code(),
                Colors.brightBlue.code(),
                Colors.reset.code(),
                Colors.cyan.code(),
                Colors.reset.code(),
                Colors.brightBlack.code(),
                Colors.reset.code(),
                Colors.magenta.code(),
                Colors.reset.code(),
                Colors.magenta.code(),
                Colors.reset.code(),
                Colors.yellow.code(),
                Colors.reset.code(),
                Colors.brightBlack.code(),
                Colors.reset.code(),
                Colors.brightBlue.code(),
                Colors.reset.code(),
            });
        },
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

fn promptName(
    allocator: std.mem.Allocator,
) ![]const u8 {
    try log(.info, "Please provide a user/organization name (defaults to yourself): ", .{});
    var input = std.ArrayList(u8).init(allocator);
    try std.io.getStdIn().reader().streamUntilDelimiter(input.writer(), '\n', 64);
    if (isWindows) _ = input.pop();
    return try input.toOwnedSlice();
}

fn createFolder(
    path: []const u8,
) !void {
    std.fs.cwd().makeDir(path) catch |err| {
        if (err == error.PathAlreadyExists) {
            try log(.warning, "Directory already exists(path: {s})\n", .{path});
        } else {
            // TODO
            return err;
        }
    };
}

const LogLevel = enum {
    help,
    info,
    warning,
    err,
};

fn log(
    level: LogLevel,
    comptime message: []const u8,
    args: anytype,
) !void {
    var out = std.io.bufferedWriter(std.io.getStdOut().writer());
    // Unsafe but does not have big side effects
    defer out.flush() catch {};
    const stdout = out.writer();
    switch (level) {
        .help => _ = try stdout.print("{s}[HELP]{s} ", .{ Colors.brightBlue.code(), Colors.reset.code() }),
        .info => _ = try stdout.print("{s}[INFO]{s} ", .{ Colors.green.code(), Colors.reset.code() }),
        .warning => _ = try stdout.print("{s}[WARNING]{s} ", .{ Colors.yellow.code(), Colors.reset.code() }),
        .err => _ = try stdout.print("{s}[ERROR]{s} ", .{ Colors.red.code(), Colors.reset.code() }),
    }
    try stdout.print(message, args);
}
