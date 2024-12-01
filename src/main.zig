//! Workspace is a CLI tool for managing GitHub repositories.
//! It allows users to clone all repositories from a user or organization
//! and automatically creates a VSCode workspace configuration.

const std = @import("std");
const builtin = @import("builtin");
const processHelper = @import("helpers/process.zig");
const logHelper = @import("helpers/log.zig");

/// Core configuration constants
const VERSION = "0.5.0";
const isWindows = @import("builtin").os.tag == .windows;
const MAX_INPUT_LENGTH = 64;
const MAX_HTTP_BUFFER = 256;

/// Process helper aliases
const spawn = processHelper.spawn;
const wait = processHelper.wait;
const run = processHelper.run;

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
};

/// GitHub repository information structure
const RepoInfo = struct {
    name: []const u8,
    nameWithOwner: []const u8,
    owner: struct {
        id: []const u8,
        login: []const u8,
    },
};

const RepoList = []RepoInfo;

/// Structure representing VSCode workspace folders
const WorkspaceFolder = struct {
    path: []const u8,
};

/// Main VSCode workspace configuration structure
const Workspace = struct {
    folders: []WorkspaceFolder,
};

/// Structure for managing clone processes
const Process = struct {
    child: std.process.Child,
    repo: RepoInfo,
};

/// Structure for managing a pool of clone processes
const ProcessPool = struct {
    processes: std.ArrayList(*Process),
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, arena: std.mem.Allocator, capacity: usize) !ProcessPool {
        return ProcessPool{
            .processes = try std.ArrayList(*Process).initCapacity(arena, capacity),
            .allocator = allocator,
            .arena = arena,
        };
    }

    fn spawn(self: *ProcessPool, repo: RepoInfo, targetFolder: []const u8) !void {
        const process = try self.arena.create(Process);
        process.* = try spawnCloneProcess(self.allocator, repo, targetFolder);
        try self.processes.append(process);
    }

    fn waitOne(self: *ProcessPool) !?struct { success: bool, process: *Process } {
        if (self.processes.items.len == 0) return null;

        // Find first finished process
        for (self.processes.items, 0..) |proc, i| {
            if (wait(self.allocator, &proc.child)) |result| {
                defer cleanupProcessResult(self.allocator, result);
                const success = handleCloneResult(result, proc.repo);
                _ = self.processes.swapRemove(i);
                return .{ .success = success, .process = proc };
            } else |_| continue;
        }
        return null;
    }
};

/// Entry point of the application.
/// Handles command-line arguments and dispatches to appropriate handlers.
pub fn main() !void {
    // Use arena allocator for temporary allocations
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // Use GPA for long-lived allocations
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = GPA.deinit();
    const allocator = GPA.allocator();

    const args = try std.process.argsAlloc(arena_allocator);
    // No need to free args since arena handles it

    const command = std.meta.stringToEnum(Commands, if (args.len >= 2) args[1] else "help") orelse Commands.help;
    switch (command) {
        .clone => {
            if (args.len < 3) {
                try log(.err, "Missing required argument: <organization/user>", .{});
                return;
            }

            // Get repository owner name (user/org) from args or prompt
            const name = args[2];

            var config = try parseArgs(args[3..]);

            const list = try run(allocator, @constCast(&[_][]const u8{ "gh", "repo", "list", name, "--json", "nameWithOwner,name,owner", "--limit", config.limit orelse "100000" }), null);
            defer {
                allocator.free(list.stdout);
                allocator.free(list.stderr);
            }

            switch (list.term.Exited) {
                // Command ran fine, parsing the output
                0 => {
                    const parsed = std.json.parseFromSlice(RepoList, allocator, list.stdout, .{}) catch |err| {
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
                        try prune(parsed.value, config.targetFolder.?);
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
                            try log(.warning, "Folder {s} is not empty, cancelling clone for this repo.", .{repo.name});
                            failed += 1;
                            continue;
                        }
                        total += 1;
                        try schedule.append(repo);
                    }

                    var processes = std.ArrayList(Process).init(allocator);
                    defer processes.deinit();

                    for (@min(config.processes, schedule.items.len)) |_| {
                        const toSpawn = schedule.pop();
                        const process = Process{
                            .child = try spawn(allocator, @constCast(&[_][]const u8{
                                "gh",
                                "repo",
                                "clone",
                                toSpawn.nameWithOwner,
                            }), config.targetFolder.?),
                            .repo = toSpawn,
                        };
                        try processes.append(process);
                    }

                    // Optimize parallel cloning
                    if (schedule.items.len > 0) {
                        const max_concurrent = @min(config.processes, schedule.items.len);
                        var pool = try ProcessPool.init(allocator, arena_allocator, max_concurrent);

                        // Initialize pool
                        const initial_count = @min(max_concurrent, schedule.items.len);
                        for (0..initial_count) |_| {
                            const repo = schedule.pop();
                            try pool.spawn(repo, config.targetFolder.?);
                        }

                        // Process remaining repositories
                        while (schedule.items.len > 0 or pool.processes.items.len > 0) {
                            if (try pool.waitOne()) |result| {
                                if (!result.success) failed += 1;

                                // Replace finished process with new one if available
                                if (schedule.items.len > 0) {
                                    const repo = schedule.pop();
                                    try pool.spawn(repo, config.targetFolder.?);
                                }
                            }
                        }
                    }

                    if (failed != 0) {
                        try log(.default, "", .{});
                        try log(.info, "Cloned {d}/{d} repositories", .{ parsed.value.len - failed, parsed.value.len });
                    } else {
                        try log(.default, "", .{});
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
                2 => try log(.err, "Command gets canceled, you really want to make us sweat, lol.\nWell, if you like this project, star it at https://github.com/gaskam/workspace.\n", .{}),
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
            const latestVersion = try checkForUpdates(allocator);
            if (latestVersion) {
                try log(.default, "", .{});
                try log(.warning, "A new version is available! Please run `workspace update` to update to the latest version.", .{});
            }
        },
        .update, .upgrade => {
            const hasUpdate = try checkForUpdates(allocator);
            if (!hasUpdate) {
                try log(.info, "Workspace is already up-to-date", .{});
                try log(.info, "Version: {s}", .{VERSION});
                return;
            }

            try log(.info, "Starting update process...", .{});
            try spawnUpdater(allocator);
            return;
        },
        .ziglove => {
            try log(.info, "We love {s}Zig{s} too!\n\nLet's support them on {s}https://github.com/ziglang/zig{s}", .{ Colors.yellow.code(), Colors.reset.code(), Colors.green.code(), Colors.reset.code() });
        },
        .help => {
            const helpMessage =
                "{0s}Workspace{1s} is a powerful application designed to install and manage all your repositories.\n\n" ++
                "Usage: workspace <command> {2s}<requirement>{1s} [...options] {3s}[--flags]{1s}\n\n" ++
                "Commands:\n" ++
                "  {0s}clone{1s} {2s}<organization/user>{1s} [destination]  Clone all repositories from an organization/user\n\n" ++
                "  \xC3\xC4 {3s}[--limit]{1s} {3s}<number>{1s}                    Limit the number of repositories to clone\n" ++
                "  \xC3\xC4 {3s}[--processes]{1s} {3s}<number>{1s}                Limit the number of concurrent processes\n" ++
                "  \xB3                                        -> Default is the number of logical CPUs - 1\n" ++
                "  \xC0\xC4 {3s}[--prune]{1s}                             Delete repositories that do not belong to current user\n\n" ++
                "  {6s}-> Note that if you provide --limit and --prune flags, we'll delete\n" ++
                "     the repositories that no longer exist once the limit is reached.{1s}\n\n" ++
                "  {4s}version{1s}                                  Display version information\n" ++
                "  {4s}update{1s}, {4s}upgrade{1s}                          Update workspace to the latest version\n\n" ++
                "  {5s}help{1s}                                     Display help information\n\n" ++
                "{3s}e.g. => $ workspace clone ziglang ./workspace --limit 10 --processes 5 --prune{1s}\n\n" ++
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
                try log(.default, "", .{});
                try log(.err, "Unknown command: {s}", .{args[1]});
            }
        },
    }
}

const CloneConfig = struct {
    targetFolder: ?[]const u8,
    limit: ?[]const u8 = null,
    processes: usize,
    prune: bool = false,
};

fn parseArgs(
    args: []const []const u8,
) !CloneConfig {
    var usedArgs: usize = 0;
    var config = CloneConfig{ .targetFolder = null, .processes = try std.Thread.getCpuCount() - 1 };
    config.prune = true;
    if (args.len == 0) {
        return config;
    }
    if (!std.mem.startsWith(u8, args[0], "-")) {
        config.targetFolder = args[0];
        usedArgs += 1;
    }

    const Args = enum { @"--limit", @"-l", @"--processes", @"-p", @"--prune", default };

    while (usedArgs < args.len) {
        const command = std.meta.stringToEnum(Args, args[usedArgs]) orelse Args.default;
        switch (command) {
            .@"--limit", .@"-l" => {
                if (usedArgs + 1 >= args.len) {
                    std.debug.print("missing argument for --limit\n", .{});
                    return error.MissingArgument;
                }
                config.limit = args[usedArgs + 1];
                usedArgs += 2;
            },
            .@"--processes", .@"-p" => {
                if (usedArgs + 1 >= args.len) {
                    std.debug.print("missing argument for --processes\n", .{});
                    return error.MissingArgument;
                }
                const processes = try std.fmt.parseInt(usize, args[usedArgs + 1], 10);
                config.processes = processes;
                usedArgs += 2;
            },
            .@"--prune" => {
                config.prune = true;
                usedArgs += 1;
            },
            .default => {
                std.debug.print("unknown argument: {s}\n", .{args[usedArgs]});
                return error.UnknownArgument;
            },
        }
    }
    return config;
}

/// Generates a VSCode workspace file with the given folders and default settings
fn generateWorkspace(allocator: std.mem.Allocator, folders: []WorkspaceFolder, path: []const u8) !void {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    try buffer.appendSlice("{\"folders\":[");
    
    for (folders, 0..) |folder, i| {
        if (i > 0) try buffer.appendSlice(",");
        try buffer.appendSlice("{\"path\":\"");
        try buffer.appendSlice(folder.path);
        try buffer.appendSlice("\"}");
    }
    
    try buffer.appendSlice("],\"settings\":{");
    try buffer.appendSlice("\"files.autoSave\":\"afterDelay\",");
    try buffer.appendSlice("\"editor.formatOnSave\":true,");
    try buffer.appendSlice("\"editor.detectIndentation\":true,");
    try buffer.appendSlice("\"git.enableSmartCommit\":true,");
    try buffer.appendSlice("\"git.confirmSync\":false}}");

    const workspace_path = try std.fs.path.join(allocator, &.{ path, "workspace.code-workspace" });
    defer allocator.free(workspace_path);

    try std.fs.cwd().writeFile(.{
        .sub_path = workspace_path,
        .data = buffer.items,
    });
}

/// Checks if a folder exists and is empty
/// Returns true if folder doesn't exist or is empty
fn isEmptyFolder(
    folder: std.fs.Dir,
    repoName: []const u8,
) !bool {
    folder.deleteDir(repoName) catch |err| {
        switch (err) {
            error.DirNotEmpty => return false,
            error.FileNotFound => return true,
            error.AccessDenied => try log(.err, "Access denied when opening directory: {s}\n", .{repoName}),
            error.FileBusy => try log(.err, "File is busy: {s}\n", .{repoName}),
            error.FileSystem => try log(.err, "Filesystem error when opening directory: {s}\n", .{repoName}),
            error.SymLinkLoop => try log(.err, "Path is a symlink loop (path: {s})", .{repoName}),
            error.NameTooLong => {
                try log(.err, "Folder name is too long for fylesystem (cancelling clone failcheck)", .{});
                return true;
            },
            error.NotDir => try log(.err, "Path is not a directory (path: {s})", .{repoName}),
            error.SystemResources => try log(.err, "Too much system ressource usage (cancelling clone failcheck)", .{}),
            error.ReadOnlyFileSystem => try log(.err, "Filesystem is read-only (cancelling clone failcheck)", .{}),
            error.InvalidUtf8 => try log(.err, "Invalid UTF-8 in repository name", .{}),
            error.InvalidWtf8 => try log(.err, "Invalid WTF-8 in repository name", .{}),
            error.BadPathName => try log(.err, "Invalid pathname (in repository name)", .{}),
            error.NetworkNotFound => try log(.err, "Network device was not found :(", .{}),
            error.Unexpected => try log(.err, "Unexpected posix error (please report to https://github.com/gaskam/workspace/issues/): {!}", .{err}),
        }
        return false;
    };
    return true;
}

/// Checks GitHub for new versions of workspace
/// Returns true if an update is available
fn checkForUpdates(allocator: std.mem.Allocator) !bool {
    const content = fetchUrlContent(allocator, "https://raw.githubusercontent.com/gaskam/workspace/refs/heads/main/INSTALL") catch {
        try log(.default, "", .{});
        try log(.warning, "Failed to check for updates...", .{});
        return false;
    };
    defer allocator.free(content);

    // Trim any whitespace/newlines from the content
    const latest_version = std.mem.trim(u8, content, &std.ascii.whitespace);
    return !std.mem.eql(u8, latest_version, VERSION);
}

/// Fetches content from a URL using HTTP GET
/// Returns the content as a string, caller owns the memory
fn fetchUrlContent(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var buffer: [4096]u8 = undefined;
    var req = try client.open(.GET, try std.Uri.parse(url), .{ .server_header_buffer = &buffer });
    defer req.deinit();

    try req.send();
    try req.wait();

    if (req.response.status != .ok) {
        return error.HttpError;
    }

    const body = try req.reader().readAllAlloc(allocator, MAX_HTTP_BUFFER);
    return body;
}

/// Creates a directory and handles various filesystem errors
fn createFolder(
    path: []const u8,
) !bool {
    std.fs.cwd().makeDir(path) catch |err| {
        switch (err) {
            // In WASI, this error may occur when the file descriptor does
            // not hold the required rights to create a new directory relative to it.
            error.AccessDenied => try log(.err, "Access denied when creating directory: {s}\n", .{path}),
            error.DiskQuota => try log(.err, "Disk quota exceeded when creating {s}\n", .{path}),
            error.PathAlreadyExists => {
                try log(.warning, "Directory already exists (path: {s})\n", .{path});
                return false;
            },
            error.SymLinkLoop => try log(.err, "Symbolic link loop detected while creating {s}\n", .{path}),
            error.LinkQuotaExceeded => try log(.err, "Link quota exceeded for {s}\n", .{path}),
            error.NameTooLong => try log(.err, "Path name too long: {s}\n", .{path}),
            error.FileNotFound => try log(.err, "A parent component of {s} does not exist\n", .{path}),
            error.SystemResources => try log(.err, "Insufficient system resources to create {s}\n", .{path}),
            error.NoSpaceLeft => try log(.err, "No space left on device to create {s}\n", .{path}),
            error.NotDir => try log(.err, "A parent component of {s} is not a directory\n", .{path}),
            error.ReadOnlyFileSystem => try log(.err, "Cannot create {s} on read-only file system\n", .{path}),
            // WASI-only; file paths must be valid UTF-8.
            error.InvalidUtf8 => try log(.err, "Invalid UTF-8 in path: {s}\n", .{path}),
            // Windows-only; file paths provided by the user must be valid WTF-8.
            // https://simonsapin.github.io/wtf-8/
            error.InvalidWtf8 => try log(.err, "Invalid WTF-8 in path: {s}\n", .{path}),
            error.BadPathName => try log(.err, "Invalid path name: {s}\n", .{path}),
            error.NoDevice => try log(.err, "No such device for path: {s}\n", .{path}),
            // On Windows, `\\server` or `\\server\share` was not found.
            error.NetworkNotFound => try log(.err, "Network path not found: {s}\n", .{path}),
            error.Unexpected => try log(.err, "Unexpected error in zig (please report to https://github.com/gaskam/workspace/issues/): {!}\n", .{err}),
        }
        return err;
    };
    return true;
}

/// Custom error type for update operations
const UpdateError = error{
    CreateProcessFailed,
    SpawnUpdateFailed,
};

/// Spawns the appropriate update script based on the OS
/// Exits the current process after spawning the updater
fn spawnUpdater(allocator: std.mem.Allocator) UpdateError!void {
    const args = if (isWindows)
        &[_][]const u8{
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            "(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/gaskam/workspace/refs/heads/main/install.ps1') | Invoke-Expression",
        }
    else
        &[_][]const u8{ "sh", "-c", "curl -fsSL https://raw.githubusercontent.com/gaskam/workspace/refs/heads/main/install.sh | bash" };

    var child = std.process.Child.init(args, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    child.spawn() catch |err| {
        log(.err, "Failed to spawn update process: {s}", .{@errorName(err)}) catch unreachable;
        return error.SpawnUpdateFailed;
    };
    std.process.exit(0);
}

/// Helper function to force remove a directory on Windows using PowerShell
fn forceRemoveDir(allocator: std.mem.Allocator, path: []const u8) !void {
    const result = try run(allocator, @constCast(&[_][]const u8{
        "powershell.exe",
        // "-NoProfile",
        // "-ExecutionPolicy",
        // "Bypass",
        // "-Command",
        "Remove-Item",
        "-Path",
        path,
        "-Recurse",
        "-Force",
    }), null);
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (result.term.Exited != 0) {
        try log(.err, "Failed to remove directory {s}: {s}", .{path, result.stderr});
        return error.RemoveFailed;
    }
}

/// Prunes repositories that no longer exist in the user's/organization's account
fn prune(list: []RepoInfo, targetFolder: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // Create hash set with default capacity
    var repo_set = std.StringHashMap(void).init(arena_alloc);
    
    // Add repositories in chunks to avoid overflow
    const chunk_size: u32 = 1024;
    var i: usize = 0;
    while (i < list.len) : (i += chunk_size) {
        const end = @min(i + chunk_size, list.len);
        try repo_set.ensureUnusedCapacity(@intCast(end - i));
        for (list[i..end]) |repo| {
            try repo_set.put(repo.name, {});
        }
    }

    var dir_to_remove = std.ArrayList([]const u8).init(arena_alloc);
    
    // Collect directories to remove
    {
        var dir = try std.fs.cwd().openDir(targetFolder, .{ .iterate = true });
        defer dir.close();
        
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .directory) continue;
            if (!repo_set.contains(entry.name)) {
                try dir_to_remove.append(try arena_alloc.dupe(u8, entry.name));
            }
        }
    }

    // Remove directories
    for (dir_to_remove.items) |dir_name| {
        try removeRepository(targetFolder, dir_name);
    }
}

/// Spawns a clone process for a given repository
fn spawnCloneProcess(allocator: std.mem.Allocator, repo: RepoInfo, targetFolder: []const u8) !Process {
    return Process{
        .child = try spawn(allocator, @constCast(&[_][]const u8{
            "gh",
            "repo",
            "clone",
            repo.nameWithOwner,
        }), targetFolder),
        .repo = repo,
    };
}

/// Cleans up the result of a process
fn cleanupProcessResult(allocator: std.mem.Allocator, result: std.process.Child.RunResult) void {
    allocator.free(result.stdout);
    allocator.free(result.stderr);
}

/// Handles the result of a clone process
fn handleCloneResult(result: std.process.Child.RunResult, repo: RepoInfo) bool {
    switch (result.term.Exited) {
        0 => {
            log(.cloned, "{s}{s}{s}", .{ Colors.brightBlue.code(), repo.nameWithOwner, Colors.reset.code() }) catch unreachable;
            return true;
        },
        1 => {
            log(.err, "Error: {s}", .{result.stderr}) catch unreachable;
            return false;
        },
        else => {
            log(.err, "Unexpected error: {d} (when cloning {s})\n{s}", .{ result.term.Exited, repo.nameWithOwner, result.stderr }) catch unreachable;
            return false;
        },
    }
}

/// Removes a repository directory
fn removeRepository(targetFolder: []const u8, dirName: []const u8) !void {
    if (isWindows) {
        const dirPath = try std.fs.path.join(std.heap.page_allocator, &.{targetFolder, dirName});
        forceRemoveDir(std.heap.page_allocator, dirPath) catch |force_err| {
            log(.err, "Failed to force remove directory {s}: {!}", .{ dirName, force_err }) catch unreachable;
        };
    } else {
        var outputFolder = try std.fs.cwd().openDir(targetFolder, .{});
        defer outputFolder.close();
        outputFolder.deleteTree(dirName) catch |err| {
            switch (err) {
                error.FileTooBig => log(.err, "File too big to delete: {s}", .{dirName}) catch unreachable,
                error.DeviceBusy => log(.err, "Device is busy", .{}) catch unreachable,
                error.AccessDenied => {
                    log(.err, "Access denied when deleting {s}", .{dirName}) catch unreachable;
                    log(.info, "Please run the command as an administrator", .{}) catch unreachable;
                },
                error.SystemResources => log(.err, "Insufficient system resources", .{}) catch unreachable,
                error.Unexpected => log(.err, "Unexpected error: {!}", .{err}) catch unreachable,
                error.NameTooLong => log(.err, "Path name too long: {s}", .{dirName}) catch unreachable,
                error.NoDevice => log(.err, "No such device for path: {s}", .{dirName}) catch unreachable,
                error.InvalidWtf8 => log(.err, "Invalid WTF-8 in path: {s}", .{dirName}) catch unreachable,
                error.FileSystem => log(.err, "Filesystem error when deleting {s}", .{dirName}) catch unreachable,
                error.NotDir => log(.err, "Not a directory: {s}", .{dirName}) catch unreachable,
                error.FileBusy => log(.err, "File is busy: {s}", .{dirName}) catch unreachable,
                error.ProcessFdQuotaExceeded => log(.err, "Process file descriptor quota exceeded", .{}) catch unreachable,
                error.SystemFdQuotaExceeded => log(.err, "System file descriptor quota exceeded", .{}) catch unreachable,
                error.SymLinkLoop => log(.err, "Symbolic link loop detected in {s}", .{dirName}) catch unreachable,
                error.BadPathName => log(.err, "Invalid pathname: {s}", .{dirName}) catch unreachable,
                error.InvalidUtf8 => log(.err, "Invalid UTF-8 in path: {s}", .{dirName}) catch unreachable,
                error.ReadOnlyFileSystem => log(.err, "Cannot delete on read-only filesystem", .{}) catch unreachable,
                error.NetworkNotFound => log(.err, "Network path not found: {s}", .{dirName}) catch unreachable,
            }
        };
    }
    log(.info, "Removed {s} as it does no longer belong to the user/organization", .{dirName}) catch unreachable;
}
