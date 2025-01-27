//! Workspace - A CLI tool for managing GitHub repositories.
//! Provides functionalities for cloning repositories and generating VSCode workspace files.

const std = @import("std");
const builtin = @import("builtin");
const processHelper = @import("helpers/process.zig");
const logHelper = @import("helpers/log.zig");
const fs = @import("helpers/fs.zig");
const constants = @import("const.zig");
const update = @import("helpers/update.zig");

/// Specific imports
const parseArgs = @import("helpers/args.zig").parseArgs;
const ProcessPool = @import("helpers/pool.zig").ProcessPool;
const prune = @import("helpers/prune.zig").prune;

/// Process helper aliases
const isWindows = constants.isWindows;
const VERSION = constants.VERSION;
const RepoInfo = constants.RepoInfo;
const WorkspaceFolder = constants.WorkspaceFolder;
const spawn = processHelper.spawn;
const wait = processHelper.wait;
const run = processHelper.run;
const cleanupProcessResult = processHelper.cleanupProcessResult;
const createFolder = fs.createFolder;
const isEmptyFolder = fs.isEmptyFolder;
const generateWorkspace = fs.generateWorkspace;
const checkForUpdates = update.checkForUpdates;
const threadedCheckConnection = update.threadedCheckConnection;
const spawnUpdater = update.spawnUpdater;

/// Colors helper aliases
const log = logHelper.log;
const Colors = logHelper.Colors;

/// Available CLI commands
const Commands = enum {
    clone, // Clone repositories from a user/organization
    help, // Display help information
    version, // Show current version
    update, // Update to latest version
    upgrade, // Alias for update
    ziglove, // Easter egg
    uninstall, // Uninstall workspace
};

/// Entry point of the application.
/// Handles command-line arguments and dispatches to appropriate handlers.
pub fn main() !void {
    // Use GPA for long-lived allocations
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = GPA.deinit();
    const allocator = GPA.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const command = std.meta.stringToEnum(Commands, if (args.len >= 2) args[1] else "help") orelse Commands.help;
    switch (command) {
        .clone => {
            try threadedCheckConnection();

            if (args.len < 3) {
                try log(.err, "Missing required argument: <organization/user>", .{});
                return;
            }

            // Get repository owner name (user/org) from args or prompt
            const name = args[2];

            var config = try parseArgs(args[3..]);

            if (config.limit != null and try std.fmt.parseInt(usize, config.limit.?, 10) == 0) {
                try log(.err, "Invalid cloning limit: 0", .{});
                return;
            }

            const list = try run(allocator, @constCast(&[_][]const u8{ "gh", "repo", "list", name, "--json", "nameWithOwner,name,owner", "--limit", config.limit orelse "100000" }), null);
            defer {
                allocator.free(list.stdout);
                allocator.free(list.stderr);
            }

            switch (list.term.Exited) {
                // Command ran fine, parsing the output
                0 => {
                    const parsed = std.json.parseFromSlice([]RepoInfo, allocator, list.stdout, .{}) catch |err| {
                        try log(.err, "Failed to parse repository list: {s}", .{list.stdout});
                        return err;
                    };
                    defer parsed.deinit();

                    if (parsed.value.len == 0) {
                        try log(.err, "No repositories found for {s}", .{name});
                        return;
                    }
                    // Handles if the user provides no name, which fallbacks to his own repositories
                    if (config.targetFolder == null)
                        config.targetFolder = parsed.value[0].owner.login;

                    const created = try createFolder(config.targetFolder.?);

                    // Prune repositories that no longer exist in the user's/organization's account
                    if (!created and config.prune) {
                        try prune(allocator, parsed.value, config.targetFolder.?);
                    }

                    var schedule = std.ArrayList(RepoInfo).init(allocator);
                    defer schedule.deinit();

                    var outputFolder = try std.fs.cwd().openDir(config.targetFolder.?, .{});
                    defer outputFolder.close();

                    var failed: usize = 0;
                    var total: usize = 0;

                    // Create a process for each repository
                    for (parsed.value) |repo| {
                        if (!try isEmptyFolder(outputFolder, repo.name)) {
                            try log(.warning, "Folder {s}{s}{s} is not empty, cancelling clone for this repo.", .{ Colors.brightBlue.code(), repo.name, Colors.reset.code() });
                            failed += 1;
                            continue;
                        }
                        total += 1;
                        try schedule.append(repo);
                    }

                    // Create a process pool for concurrent cloning
                    var pool = ProcessPool.init(allocator);

                    for (@min(config.processes, schedule.items.len)) |_| {
                        const repo = schedule.pop();
                        try pool.spawn(repo, config.targetFolder.?);
                    }

                    while (pool.processes.len > 0) {
                        const result = try pool.next();
                        if (!result.?.success) {
                            try log(.err, "Failed to clone {s}{s}{s}", .{ Colors.brightBlue.code(), result.?.name, Colors.reset.code() });
                            failed += 1;
                        }

                        if (schedule.popOrNull()) |repo| {
                            try pool.spawn(repo, config.targetFolder.?);
                        }
                    }

                    if (failed != 0) {
                        try log(.default, "\n", .{});
                        try log(.info, "Cloned {d}/{d} repositories", .{ parsed.value.len - failed, parsed.value.len });
                    } else {
                        try log(.default, "\n", .{});
                        try log(.info, "Cloned all {d} repositories", .{parsed.value.len});
                    }

                    // Generate workspace file
                    var foldersList = try std.ArrayList(WorkspaceFolder).initCapacity(allocator, parsed.value.len);
                    defer foldersList.deinit();
                    for (parsed.value) |repo| {
                        foldersList.appendAssumeCapacity(WorkspaceFolder{ .path = repo.name });
                    }
                    const folders = foldersList.items;

                    try generateWorkspace(allocator, folders, config.targetFolder.?);
                },
                // Probably just an invalid user/organization name
                1 => try log(.err, "{s}\n", .{list.stderr}),
                2 => try log(.err, "Command got cancelled, you really want to make us sweat, lol.\nWell, if you like this project, star it at https://github.com/gaskam/workspace.\n", .{}),
                3 => try log(.err, "Oopsie! This error was never supposed to happen!", .{}),
                4 => try log(.err, "Please login to gh using {s}gh auth login{s}", .{ Colors.grey.code(), Colors.reset.code() }),
                else => {
                    try log(.err, "Unexpected error: {d} (when fetching user info)", .{list.term.Exited});
                    try log(.err, "{s}", .{list.stderr});
                },
            }
        },
        .version => {
            try log(.info, "{s}", .{VERSION});
            try threadedCheckConnection();
            const latestVersion = try checkForUpdates(allocator);
            if (latestVersion) {
                try log(.default, "\n", .{});
                try log(.warning, "A new version is available! Please run `workspace update` to update to the latest version.", .{});
            }
        },
        .update, .upgrade => {
            try threadedCheckConnection();

            const hasUpdate = try checkForUpdates(allocator);
            if (!hasUpdate) {
                try log(.info, "Workspace is already up-to-date", .{});
                try log(.info, "Version: {s}", .{VERSION});
                return;
            }

            try log(.info, "Starting update process...", .{});
            try log(.info, "Wait just a moment and try running version command", .{});
            try spawnUpdater(allocator);
            return;
        },
        .ziglove => {
            try log(.info, "We love {s}Zig{s} too!\n\nLet's support them on {s}https://github.com/ziglang/zig{s}", .{ Colors.yellow.code(), Colors.reset.code(), Colors.green.code(), Colors.reset.code() });
        },
        .uninstall => {
            const stdout = std.io.getStdOut();
            var bw = std.io.bufferedWriter(stdout.writer());
            try log(.warning, "This command will {s}UNINSTALL WORKSPACE{s} from your system.\n\nAre you sure you want to proceed? [y/N]", .{ Colors.red.code(), Colors.reset.code() });
            try log(.default, "> ", .{});
            try bw.flush();
            const stdin = std.io.getStdIn().reader();

            var inputList = std.ArrayList(u8).init(allocator);
            defer inputList.deinit();
            try stdin.streamUntilDelimiter(inputList.writer(), '\n', 10);
            if (isWindows and inputList.getLastOrNull() == '\r') {
                _ = inputList.pop();
            }
            if (inputList.items.len == 1 and (inputList.items[0] == 'y' or inputList.items[0] == 'Y')) {
                var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
                var selfExeDir = try std.fs.openDirAbsolute(try std.fs.selfExeDirPath(&buf), .{});
                defer selfExeDir.close();
                const path = try selfExeDir.realpathAlloc(allocator, "../");
                defer allocator.free(path);
                try log(.default, "\n", .{});
                try log(.info, "Uninstalling Workspace from {s}", .{path});
                if (!std.mem.endsWith(u8, path, ".workspace")) {
                    try log(.err, "Failed to uninstall Workspace:", .{});
                    try log(.err, "-> Invalid workspace path: {s}", .{path});
                    return;
                }

                if (isWindows) {
                    const escapedPath = try std.fmt.allocPrint(allocator, "{s}", .{path});
                    defer allocator.free(escapedPath);

                    const ps_cmd = &[_][]const u8{
                        "powershell.exe",
                        "-NoProfile",
                        "-ExecutionPolicy",
                        "Bypass",
                        "-Command",
                        "Start-Sleep",
                        "-Seconds",
                        "2;",
                        "Remove-Item",
                        "-Path",
                        escapedPath,
                        "-Recurse",
                        "-Force",
                    };

                    var child = std.process.Child.init(ps_cmd, allocator);
                    child.stdin_behavior = .Ignore;
                    child.stdout_behavior = .Ignore;
                    child.stderr_behavior = .Ignore;

                    child.spawn() catch |err| {
                        try log(.default, "\n", .{});
                        try log(.err, "Failed to spawn uninstall process: {s}", .{@errorName(err)});
                        return;
                    };
                } else {
                    try std.fs.deleteTreeAbsolute(path);
                }
            } else {
                try log(.default, "\n", .{});
                try log(.info, "Uninstall process aborted :) Welcome back!", .{});
            }
        },
        .help => {
            const helpMessage =
                "{0s}Workspace{1s} is a powerful application designed to install and manage all your repositories.\n\n" ++
                "Usage: workspace <command> {2s}<requirement>{1s} [...options] {3s}[--flags]{1s}\n\n" ++
                "Commands:\n" ++
                "  {0s}clone{1s} {2s}<organization/user>{1s} [destination]  Clone all repositories from an organization/user\n\n" ++
                "  |-- {3s}[--limit]{1s} {3s}<number>{1s}                   Limit the number of repositories to clone\n" ++
                "  |-- {3s}[--processes]{1s} {3s}<number>{1s}               Limit the number of concurrent processes\n" ++
                "  |                                        -> Default is the number of logical CPUs - 1\n" ++
                "  |-- {3s}[--prune]{1s}                            Delete repositories that do not belong to current user\n\n" ++
                "  {6s}-> Note that if you provide --limit and --prune flags, we'll delete\n" ++
                "     the repositories that no longer exist once the limit is reached.{1s}\n\n" ++
                "  {4s}version{1s}                                  Display version information\n" ++
                "  {4s}update{1s}, {4s}upgrade{1s}                          Update workspace to the latest version\n\n" ++
                "  {5s}help{1s}                                     Display help information\n\n" ++
                "{3s}e.g. => $ workspace clone ziglang ./workspace --limit 10 --processes 5 --prune{1s}\n\n" ++
                "  {6s}uninstall{1s}                                Uninstall workspace :(\n\n" ++
                "Contribute about Workspace:                {0s}https://github.com/gaskam/workspace{1s}";
            try log(.help, helpMessage, .{
                Colors.green.code(),
                Colors.reset.code(),
                Colors.cyan.code(),
                Colors.grey.code(),
                Colors.magenta.code(),
                Colors.yellow.code(),
                Colors.red.code(),
            });

            if (args.len >= 2 and !std.mem.eql(u8, args[1], "help")) {
                try log(.default, "\n", .{});
                try log(.err, "Unknown command: {s}", .{args[1]});
            }
        },
    }
}
