const std = @import("std");
const logHelper = @import("log.zig");
const constants = @import("../const.zig");

const Colors = logHelper.Colors;
const log = logHelper.log;

const run = @import("process.zig").run;
const isWindows = constants.isWindows;
const RepoInfo = constants.RepoInfo;

/// Removes repositories that no longer exist in the user's/organization's account
/// list: Array of current repository information
/// targetFolder: Path to the folder containing repositories
pub fn prune(allocator: std.mem.Allocator, list: []RepoInfo, targetFolder: []const u8) !void {
    // Create hash set with default capacity
    var repo_set = std.StringHashMap(void).init(allocator);
    defer repo_set.deinit();

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

    var dir_to_remove = std.ArrayList([]const u8).init(allocator);
    defer dir_to_remove.deinit();

    // Collect directories to remove
    {
        var dir = try std.fs.cwd().openDir(targetFolder, .{ .iterate = true });
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .directory) continue;
            if (!repo_set.contains(entry.name)) {
                try dir_to_remove.append(try allocator.dupe(u8, entry.name));
            }
        }
    }

    // Remove directories
    for (dir_to_remove.items) |dir_name| {
        defer allocator.free(dir_name);
        try removeRepository(allocator, targetFolder, dir_name);
    }
}

/// Removes a repository directory with platform-specific handling
/// targetFolder: Parent folder containing the repository
/// dirName: Name of the repository directory to remove
fn removeRepository(allocator: std.mem.Allocator, targetFolder: []const u8, dirName: []const u8) !void {
    if (isWindows) {
        // const dirPath = try std.fs.path.join(std.heap.page_allocator, &.{ targetFolder, dirName });
        forceRemoveDir(allocator, targetFolder, dirName) catch |force_err| {
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
    log(.info, "Removed {s}{s}{s} as it does no longer belong to the user/organization", .{ Colors.brightBlue.code(), dirName, Colors.reset.code() }) catch unreachable;
}

/// Forces directory removal on Windows systems using PowerShell
/// allocator: Memory allocator for process execution
/// path: Path to the directory to remove
fn forceRemoveDir(allocator: std.mem.Allocator, cwd: []const u8, path: []const u8) !void {
    const result = try run(allocator, @constCast(&[_][]const u8{
        "powershell.exe",
        "Remove-Item",
        "-Path",
        path,
        "-Recurse",
        "-Force",
    }), cwd);
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (result.term.Exited != 0) {
        try log(.err, "Failed to remove directory {s}: {s}", .{ path, result.stderr });
        return error.RemoveFailed;
    }
}
