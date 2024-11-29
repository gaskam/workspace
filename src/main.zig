//! Workspace is a CLI tool for managing GitHub repositories.
//! It allows users to clone all repositories from a user or organization
//! and automatically creates a VSCode workspace configuration.

const std = @import("std");
const processHelper = @import("helpers/process.zig");
const logHelper = @import("helpers/log.zig");

/// Core configuration constants
const VERSION = "0.3.2";
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

/// Entry point of the application.
/// Handles command-line arguments and dispatches to appropriate handlers.
pub fn main() !void {
    // Initialize memory allocators
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = GPA.deinit();
    const allocator = GPA.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const command = std.meta.stringToEnum(Commands, if (args.len >= 2) args[1] else "help") orelse Commands.help;
    switch (command) {
        .clone => {
            // Get repository owner name (user/org) from args or prompt
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
                        try log(.err, "Failed to parse repository list: {s}", .{list.stdout});
                        return err;
                    };
                    defer parsed.deinit();

                    if (parsed.value.len == 0) {
                        try log(.err, "No repositories found for {s}", .{name});
                        return;
                    }
                    // Handles if the user provides no name, which fallbacks to his own repositories
                    const folderPath = if (args.len <= 3) parsed.value[0].owner.login else args[3];

                    try createFolder(folderPath);

                    var processes = std.ArrayList(std.process.Child).init(allocator);
                    defer processes.deinit();

                    var outputFolder = try std.fs.cwd().openDir(folderPath, .{});
                    defer outputFolder.close();

                    var failed: usize = 0;

                    // Create a process for each repository
                    for (parsed.value) |repo| {
                        if (!try isEmptyFolder(outputFolder, repo.name)) {
                            try log(.warning, "Folder {s} is not empty, cancelling clone for this repo.", .{folderPath});
                            failed += 1;
                            continue;
                        }
                        const process = try spawn(allocator, &[_][]const u8{ "gh", "repo", "clone", repo.nameWithOwner }, folderPath);
                        try processes.append(process);
                    }

                    // Wait for all processes to complete
                    for (processes.items, 0..) |process, i| {
                        const result = try wait(allocator, @constCast(&process));
                        defer {
                            allocator.free(result.stdout);
                            allocator.free(result.stderr);
                        }
                        switch (result.term.Exited) {
                            0 => try log(.cloned, "{s}{s}{s}", .{ Colors.brightBlue.code(), parsed.value[i].nameWithOwner, Colors.reset.code() }),
                            1 => try log(.err, "Error: {s}", .{result.stderr}),
                            else => try log(.err, "Unexpected error: {d} (when cloning {s})\n{s}", .{ result.term.Exited, parsed.value[i].nameWithOwner, result.stderr }),
                        }
                        if (result.term.Exited != 0) {
                            failed += 1;
                        }
                    }

                    if (failed != 0)
                        try log(.info, "Cloned {d}/{d} repositories", .{ parsed.value.len - failed, parsed.value.len })
                    else
                        try log(.info, "Cloned all {d} repositories", .{parsed.value.len});

                    // Generate workspace file
                    var foldersList = try std.ArrayList(WorkspaceFolder).initCapacity(allocator, parsed.value.len);
                    defer foldersList.deinit();
                    for (parsed.value) |repo| {
                        foldersList.appendAssumeCapacity(WorkspaceFolder{ .path = repo.name });
                    }
                    const folders = foldersList.items;

                    try generateWorkspace(allocator, folders, folderPath);
                },
                // Probably just an invalid user/organization name
                1 => try log(.err, "{s}\n", .{list.stderr}),
                2 => try log(.err, "Command gets canceled, you really want to make us sweat, lol.\nWell, if you like this project, star it at https://github.com/gaskam/workspace.\n", .{}),
                3 => try log(.err, "Oopsie! This error was never supposed to happen!", .{}),
                4 => try log(.err, "Please login to gh using {s}gh auth login{s}", .{ Colors.brightBlack.code(), Colors.reset.code() }),
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
                const stdout = std.io.getStdOut().writer();
                try stdout.print("\n", .{});
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
        // implicitly also catches `help` command
        .help => {
            const helpMessage =
                "{s}Workspace{s} is a powerful application designed to install and manage all your repositories in your chosen destination.\n\n" ++
                "Usage: workspace <command> {s}<requirement>{s} {s}[...options]{s}\n\n" ++
                "Commands:\n" ++
                "  {s}clone{s} {s}<organization/user>{s} {s}[destination]{s}  Clone all repositories from an organization/user\n\n" ++
                "  {s}version{s}                                  Display version information\n" ++
                "  {s}update{s}, {s}upgrade{s}                          Update workspace to the latest version\n\n" ++
                "  {s}help{s}                                     Display help information\n\n" ++
                "{s}e.g. => $ workspace clone ziglang ./workspace{s} \n\n" ++
                "Contribute about Workspace:                {s}https://github.com/gaskam/workspace{s}";
            try log(.help, helpMessage, .{
                Colors.green.code(),
                Colors.reset.code(),
                Colors.cyan.code(),
                Colors.reset.code(),
                Colors.brightBlack.code(),
                Colors.reset.code(),
                Colors.green.code(),
                Colors.reset.code(),
                Colors.cyan.code(),
                Colors.reset.code(),
                Colors.brightBlack.code(),
                Colors.reset.code(),
                Colors.magenta.code(),
                Colors.reset.code(),
                Colors.magenta.code(),
                Colors.reset.code(),
                Colors.magenta.code(),
                Colors.reset.code(),
                Colors.yellow.code(),
                Colors.reset.code(),
                Colors.brightBlack.code(),
                Colors.reset.code(),
                Colors.green.code(),
                Colors.reset.code(),
            });

            if (args.len >= 2 and !std.mem.eql(u8, args[1], "help")) {
                const stdout = std.io.getStdOut().writer();
                try stdout.print("\n", .{});
                try log(.err, "Unknown command: {s}", .{args[1]});
            }
        },
    }
}

/// Generates a VSCode workspace file with the given folders and default settings
fn generateWorkspace(allocator: std.mem.Allocator, folders: []WorkspaceFolder, path: []const u8) !void {
    // Define default VSCode settings
    const Settings = struct {
        files_autoSave: []const u8 = "afterDelay",
        editor_formatOnSave: bool = true,
        editor_detectIndentation: bool = true,
        git_enableSmartCommit: bool = true,
        git_confirmSync: bool = false,
    };

    const WorkspaceFile = struct {
        folders: []WorkspaceFolder,
        settings: Settings = .{},
    };

    const workspace = WorkspaceFile{
        .folders = folders,
    };

    const workspaceFilePath = try std.fs.path.join(allocator, &.{ path, "workspace.code-workspace" });
    defer allocator.free(workspaceFilePath);

    var workspaceJson = std.ArrayList(u8).init(allocator);
    defer workspaceJson.deinit();
    try std.json.stringify(workspace, .{}, workspaceJson.writer());

    const file = try std.fs.cwd().createFile(workspaceFilePath, .{});
    defer file.close();
    try file.writeAll(workspaceJson.items);
}

/// Checks if a folder exists and is empty
/// Returns true if folder doesn't exist or is empty
fn isEmptyFolder(
    folder: std.fs.Dir,
    repoName: []const u8,
) !bool {
    var dir = folder.openDir(repoName, .{ .access_sub_paths = false, .iterate = true }) catch |err| {
        switch (err) {
            error.FileNotFound => return true,
            error.NotDir => try log(.err, "Path is not a directory: {s}\n", .{repoName}),
            error.AccessDenied => try log(.err, "Access denied when opening directory: {s}\n", .{repoName}),
            error.SymLinkLoop => try log(.err, "Path is a symlink loop (path: {s})", .{repoName}),
            error.ProcessFdQuotaExceeded => {
                try log(.err, "Process: too much open file handles (cancelling clone failcheck)", .{});
                return true;
            },
            error.NameTooLong => {
                try log(.err, "Path name is too long for fylesystem (cancelling clone failcheck)", .{});
                return true;
            },
            error.SystemFdQuotaExceeded => {
                try log(.err, "System: too much open file handles... Aborting", .{});
                return err;
            },
            error.NoDevice => try log(.err, "The directory doesn't seem to be on a valid device. This shouldn't happen.", .{}),
            error.SystemResources => try log(.err, "Too much system ressource usage (cancelling clone failcheck)", .{}),
            error.InvalidUtf8 => try log(.err, "Invalid UTF-8 in repository name", .{}),
            error.InvalidWtf8 => try log(.err, "Invalid WTF-8 in repository name", .{}),
            error.BadPathName => try log(.err, "Invalid pathname (in repository name)", .{}),
            error.DeviceBusy => try log(.err, "Device too busy", .{}),
            error.NetworkNotFound => try log(.err, "Network device was not found :(", .{}),
            error.Unexpected => try log(.err, "Unexpected posix error (please report to https://github.com/gaskam/workspace/issues/): {!}", .{err}),
        }
        return false;
    };
    defer dir.close();
    var iterator = dir.iterate();
    return try iterator.next() == null;
}

/// Checks GitHub for new versions of workspace
/// Returns true if an update is available
fn checkForUpdates(allocator: std.mem.Allocator) !bool {
    const content = fetchUrlContent(allocator, "https://raw.githubusercontent.com/gaskam/workspace/refs/heads/main/INSTALL") catch {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("\n", .{});
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

/// Prompts the user for input with a default fallback
/// Returns the user input or an error
fn promptName(
    allocator: std.mem.Allocator,
) ![]const u8 {
    try log(.info, "Please provide a user/organization name (defaults to yourself): ", .{});
    var input = std.ArrayList(u8).init(allocator);
    std.io.getStdIn().reader().streamUntilDelimiter(input.writer(), '\n', MAX_INPUT_LENGTH) catch |err| {
        switch (err) {
            error.StreamTooLong => try log(.err, "Input name too long (max {d} characters)", .{MAX_INPUT_LENGTH}),
            error.EndOfStream => try log(.err, "No input provided", .{}),
            else => try log(.err, "Unable to get input: {!}", .{err}),
        }
        return err;
    };
    if (isWindows) _ = input.pop();
    return try input.toOwnedSlice();
}

/// Creates a directory and handles various filesystem errors
fn createFolder(
    path: []const u8,
) !void {
    std.fs.cwd().makeDir(path) catch |err| {
        switch (err) {
            // In WASI, this error may occur when the file descriptor does
            // not hold the required rights to create a new directory relative to it.
            error.AccessDenied => try log(.err, "Access denied when creating directory: {s}\n", .{path}),
            error.DiskQuota => try log(.err, "Disk quota exceeded when creating {s}\n", .{path}),
            error.PathAlreadyExists => try log(.warning, "Directory already exists (path: {s})\n", .{path}),
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
    };
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
