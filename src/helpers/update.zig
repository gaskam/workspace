const std = @import("std");
const constants = @import("../const.zig");

const log = @import("log.zig").log;

const VERSION = constants.VERSION;
const isWindows = constants.isWindows;
const MAX_HTTP_BUFFER = constants.MAX_HTTP_BUFFER;

/// Checks GitHub for new versions of workspace
/// allocator: Memory allocator for HTTP operations
/// Returns: true if an update is available, false otherwise
pub fn checkForUpdates(allocator: std.mem.Allocator) !bool {
    try threadedCheckConnection();
    
    const content = fetchUrlContent(allocator, "https://raw.githubusercontent.com/gaskam/workspace/refs/heads/main/INSTALL") catch {
        try log(.default, "\n", .{});
        try log(.warning, "Failed to check for updates...", .{});
        return false;
    };
    defer allocator.free(content);

    // Trim any whitespace/newlines from the content
    const latest_version = std.mem.trim(u8, content, &std.ascii.whitespace);
    return !std.mem.eql(u8, latest_version, VERSION);
}

/// Fetches content from a URL using HTTP GET
/// allocator: Memory allocator for HTTP operations
/// url: Target URL to fetch
/// Returns: Allocated string containing the response body
pub fn fetchUrlContent(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
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

/// Error type for update-related operations
const UpdateError = error{
    CreateProcessFailed,
    SpawnUpdateFailed,
};

/// Initiates the update process by spawning the appropriate update script
/// allocator: Memory allocator for process spawning
/// Note: This function exits the current process after spawning the updater
pub fn spawnUpdater(allocator: std.mem.Allocator) UpdateError!void {
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

// TODO
pub fn threadedCheckConnection() !void {
    return;
    // var process = try std.Thread.spawn();
    // process.detach();
}

/// Checks if the user is connected to the internet
/// Returns: NoInternetConnection error if no connection is available
pub fn checkConnexion() void {
    var socket = std.net.tcpConnectToHost(std.heap.page_allocator, "1.1.1.1", 53) catch |err| {
        switch (err) {
            error.NetworkUnreachable,
            error.ConnectionRefused,
            error.ConnectionResetByPeer,
            error.ConnectionTimedOut,
            => {
                try log(.err, "Oups! It seems that you are not connected to THE internet", .{});
                try log(.info, "If you are a cute grandma, please connect to the internet", .{});
            },
            else => {
                try log(.err, "Unknown network error: {s}", .{@errorName(err)});
            },
        }
        std.process.exit(1);
    };
    defer socket.close();
}
