const std = @import("std");
const constants = @import("../const.zig");

const processHelper = @import("../helpers/process.zig");
const logHelper = @import("../helpers/log.zig");
const fs = @import("../helpers/fs.zig");
const network = @import("../helpers/network.zig");

const parseArgs = @import("../helpers/args.zig").parseArgs;
const ProcessPool = @import("../helpers/pool.zig").ProcessPool;
const prune = @import("../helpers/prune.zig").prune;

const log = logHelper.log;
const Colors = logHelper.Colors;

pub const command: constants.Command = .{
    .name = "clone",
    .function = &execute,
};

fn execute(allocator: std.mem.Allocator, args: constants.Args) anyerror!void {
    try network.threadedCheckConnection();

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

    const list = try processHelper.run(allocator, @constCast(&[_][]const u8{ "gh", "repo", "list", name, "--json", "nameWithOwner,name,owner", "--limit", config.limit orelse "100000" }), null);
    defer {
        allocator.free(list.stdout);
        allocator.free(list.stderr);
    }

    switch (list.term.Exited) {
        // Command ran fine, parsing the output
        0 => {
            const parsed = std.json.parseFromSlice([]constants.RepoInfo, allocator, list.stdout, .{}) catch |err| {
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

            const created = try fs.createFolder(config.targetFolder.?);

            // Prune repositories that no longer exist in the user's/organization's account
            if (!created and config.prune) {
                try prune(allocator, parsed.value, config.targetFolder.?);
            }

            var schedule = std.ArrayList(constants.RepoInfo).init(allocator);
            defer schedule.deinit();

            var outputFolder = try std.fs.cwd().openDir(config.targetFolder.?, .{});
            defer outputFolder.close();

            var failed: usize = 0;
            var total: usize = 0;

            // Create a process for each repository
            for (parsed.value) |repo| {
                if (!try fs.isEmptyFolder(outputFolder, repo.name)) {
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
            var foldersList = try std.ArrayList(constants.WorkspaceFolder).initCapacity(allocator, parsed.value.len);
            defer foldersList.deinit();
            for (parsed.value) |repo| {
                foldersList.appendAssumeCapacity(constants.WorkspaceFolder{ .path = repo.name });
            }

            try fs.generateWorkspace(allocator, foldersList.items, config.targetFolder.?, .VsCode, false);
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
}
