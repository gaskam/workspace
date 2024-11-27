const std = @import("std");
const VERSION = "0.2.1";
const isWindows = @import("builtin").os.tag == .windows;
const MAX_INPUT_LENGTH = 64;

const CommandError = error{
    GithubCliNotFound,
    CommandFailed,
};

const Commands = enum {
    clone,
    help,
    version,
    update,
    upgrade,
    ziglove,
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
        "\x1b[0m", // reset
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

const CloneTask = struct {
    repo: RepoInfo,
    folderPath: []const u8,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, repo: RepoInfo, folderPath: []const u8) !*CloneTask {
        const task = try allocator.create(CloneTask);
        task.* = .{
            .repo = repo,
            .folderPath = try allocator.dupe(u8, folderPath),
            .allocator = allocator,
        };
        return task;
    }

    fn deinit(self: *CloneTask) void {
        self.allocator.free(self.folderPath);
        self.allocator.destroy(self);
    }
};

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = GPA.deinit();
    var TSA = std.heap.ThreadSafeAllocator{
        .child_allocator = GPA.allocator(),
    };
    const allocator = TSA.allocator();
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
                    const folderPath = if (args.len <= 3) parsed.value[0].owner.login else args[3];

                    try createFolder(folderPath);

                    var threads = std.ArrayList(std.Thread).init(allocator);
                    defer threads.deinit();

                    // Create a thread for each repository
                    for (parsed.value) |repo| {
                        const task = try CloneTask.init(allocator, repo, folderPath);
                        const thread = try std.Thread.spawn(.{}, cloneWorker, .{task});
                        try threads.append(thread);
                    }

                    // Wait for all threads to complete
                    for (threads.items) |thread| {
                        thread.join();
                    }

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
                4 => try log(.err, "Please login to gh using {s}gh auth login{s}\n", .{ Colors.brightBlack.code(), Colors.reset.code() }),
                else => {
                    try log(.err, "Unexpected error: {d} (when fetching user info)\n", .{list.term.Exited});
                    try log(.err, "{s}\n", .{list.stderr});
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
                0 => try log(.info, "Successfully updated Workspace", .{}),
                else => {
                    try log(.err, "Failed to update Workspace: {s}\nPlease try the install command: `curl -fsSL https://raw.githubusercontent.com/gaskam/workspace/refs/heads/main/install.sh | bash`", .{updateResult.stderr});
                    return;
                },
            }
        },
        .ziglove => {
            try log(.info, "We love {s}Zig{s} too!\n\nLet's support them on {s}https://github.com/ziglang/zig{s}", .{ Colors.yellow.code(), Colors.reset.code(), Colors.green.code(), Colors.reset.code() });
        },
        // implicitly also catches `help` command
        else => {
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

fn cloneWorker(task: *CloneTask) !void {
    defer task.deinit();
    
    const result = try run(task.allocator, @constCast(&[_][]const u8{ "gh", "repo", "clone", task.repo.nameWithOwner }), task.folderPath);
    defer {
        task.allocator.free(result.stdout);
        task.allocator.free(result.stderr);
    }

    switch (result.term.Exited) {
        0 => try log(.cloned, "{s}{s}{s}", .{ Colors.brightBlue.code(), task.repo.nameWithOwner, Colors.reset.code() }),
        1 => try log(.err, "Error: {s}", .{result.stderr}),
        else => try log(.err, "Unexpected error: {d} (when cloning {s})\n{s}", .{ result.term.Exited, task.repo.nameWithOwner, result.stderr }),
    }
}

fn run(
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
            return CommandError.GithubCliNotFound;
        }
        return err;
    };
    return cp;
}

fn generateWorkspace(allocator: std.mem.Allocator, folders: []WorkspaceFolder, path: []const u8) !void {
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

fn checkForUpdates(allocator: std.mem.Allocator) !bool {
    const result = try run(allocator, @constCast(&[_][]const u8{ 
        "gh", "release", "list", "-L", "1",
        "--repo", "gaskam/workspace",
        "--exclude-drafts", "--exclude-pre-releases",
        "--json", "tagName,isDraft,isPrerelease",
        "-q", ".[] | select(.isDraft==false and .isPrerelease==false) | .tagName"
    }), null);
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    switch (result.term.Exited) {
        0 => {
            // Trim any whitespace/newlines from the version string
            const latestVersion = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
            return !std.mem.eql(u8, latestVersion, VERSION);
        },
        else => {
            try log(.err, "Failed to check for updates: {s}", .{result.stderr});
            return false;
        },
    }
}

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

const LogLevel = enum {
    help,
    info,
    cloned,
    warning,
    err,
};

fn log(
    level: LogLevel,
    comptime message: []const u8,
    args: anytype,
) !void {
    const stdout = std.io.getStdOut().writer();
    switch (level) {
        .help => _ = try stdout.print("{s}[HELP]{s} ", .{ Colors.green.code(), Colors.reset.code() }),
        .info => _ = try stdout.print("{s}[INFO]{s} ", .{ Colors.green.code(), Colors.reset.code() }),
        .cloned => _ = try stdout.print("{s}[CLONED]{s} ", .{ Colors.green.code(), Colors.reset.code() }),
        .warning => _ = try stdout.print("{s}[WARNING]{s} ", .{ Colors.yellow.code(), Colors.reset.code() }),
        .err => _ = try stdout.print("{s}[ERROR]{s} ", .{ Colors.red.code(), Colors.reset.code() }),
    }
    try stdout.print(message, args);
    try stdout.writeByte('\n');
}
