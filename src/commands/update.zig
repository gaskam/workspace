const std = @import("std");
const constants = @import("../const.zig");

const logHelper = @import("../helpers/log.zig");
const network = @import("../helpers/network.zig");

const log = logHelper.log;

const isWindows = constants.isWindows;

pub const command: constants.Command = .{
    .name = "update",
    .alias = "upgrade",
    .function = &execute,
};

pub const definition: constants.Definition = .{
    .command = command,
};

fn execute(allocator: std.mem.Allocator, args: [][]const u8) anyerror!void {
    _ = args;
    try network.threadedCheckConnection();

    const hasUpdate = try network.checkForUpdates(allocator);
    if (!hasUpdate) {
        try log(.info, "Workspace is already up-to-date", .{});
        try log(.info, "Version: {s}", .{constants.VERSION});
        return;
    }

    try log(.info, "Starting update process...", .{});
    try log(.info, "Wait just a moment and try running version command", .{});
    try spawnUpdater(allocator);
    return;
}

/// Error type for update-related operations
const UpdateError = error{
    CreateProcessFailed,
    SpawnUpdateFailed,
};

/// Initiates the update process by spawning the appropriate update script
/// allocator: Memory allocator for process spawning
/// Note: This function exits the current process after spawning the updater
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
