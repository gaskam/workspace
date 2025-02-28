const std = @import("std");
const constants = @import("../const.zig");

const log = @import("log.zig").log;

const WorkspaceFolder = constants.WorkspaceFolder;

/// Editor we have to generate the workspace configuration file for
pub const Editors = enum {
    /// Defaults to none if actual workspace folder is not found
    auto,
    none,
    VsCode,
    SublimeText,
};

/// Generates a VSCode workspace file containing all cloned repositories
/// allocator: Memory allocator for dynamic allocations
/// folders: Array of workspace folders to include
/// path: Target path for the workspace file
pub fn generateWorkspace(allocator: std.mem.Allocator, folders: []WorkspaceFolder, path: []const u8, workspaceType: Editors, prune: bool) !void {
    //TODO remove temp "_ = prune;"
    _ = prune;
    switch (workspaceType) {
        .none => return,
        .VsCode, .SublimeText => {
            var buffer = std.ArrayList(u8).init(allocator);
            defer buffer.deinit();

            try buffer.appendSlice("{\"folders\":[");

            for (folders, 0..) |folder, i| {
                if (i > 0) try buffer.appendSlice(",");
                try buffer.appendSlice("{\"path\":\"");
                try buffer.appendSlice(folder.path);
                try buffer.appendSlice("\"}");
            }

            try buffer.append('}');

            const workspace_name = if (workspaceType == .VsCode) "workspace.code-workspace" else "workspace.sublime-project";
            const workspace_path = try std.fs.path.join(allocator, &.{ path, workspace_name });
            defer allocator.free(workspace_path);

            try std.fs.cwd().writeFile(.{
                .sub_path = workspace_path,
                .data = buffer.items,
            });
        },
        .auto => {},
    }
}

fn isEditor(allocator: std.mem.Allocator, basePath: []const u8, name: []const u8) !bool {
    const total_path = try std.fs.path.join(allocator, &.{ basePath, name });
    defer allocator.free(total_path);

    std.fs.cwd().access(total_path) catch |err| {
        if (err == error.FileNotFound) return false;
        return err;
    };
    return true;
}

/// Verifies if a folder is empty or doesn't exist
/// folder: Directory handle for the parent folder
/// repoName: Name of the repository/folder to check
/// Returns: true if folder doesn't exist or is empty, false otherwise
pub fn isEmptyFolder(
    folder: std.fs.Dir,
    repoName: []const u8,
) !bool {
    folder.deleteDir(repoName) catch |err| {
        switch (err) {
            error.DirNotEmpty => return false,
            error.FileNotFound => return true,
            error.AccessDenied => try log(.err, "Access denied when opening directory: {s}", .{repoName}),
            error.FileBusy => try log(.err, "File is busy: {s}", .{repoName}),
            error.FileSystem => try log(.err, "Filesystem error when opening directory: {s}", .{repoName}),
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

/// Creates a new directory with comprehensive error handling
/// path: Path where the directory should be created
/// Returns: true if directory was created, false if it already exists
pub fn createFolder(
    path: []const u8,
) !bool {
    std.fs.cwd().makeDir(path) catch |err| {
        switch (err) {
            // In WASI, this error may occur when the file descriptor does
            // not hold the required rights to create a new directory relative to it.
            error.AccessDenied => try log(.err, "Access denied when creating directory: {s}", .{path}),
            error.DiskQuota => try log(.err, "Disk quota exceeded when creating {s}", .{path}),
            error.PathAlreadyExists => {
                try log(.warning, "Directory already exists (path: {s})", .{path});
                return false;
            },
            error.SymLinkLoop => try log(.err, "Symbolic link loop detected while creating {s}", .{path}),
            error.LinkQuotaExceeded => try log(.err, "Link quota exceeded for {s}", .{path}),
            error.NameTooLong => try log(.err, "Path name too long: {s}", .{path}),
            error.FileNotFound => try log(.err, "A parent component of {s} does not exist", .{path}),
            error.SystemResources => try log(.err, "Insufficient system resources to create {s}", .{path}),
            error.NoSpaceLeft => try log(.err, "No space left on device to create {s}", .{path}),
            error.NotDir => try log(.err, "A parent component of {s} is not a directory", .{path}),
            error.ReadOnlyFileSystem => try log(.err, "Cannot create {s} on read-only file system", .{path}),
            // WASI-only; file paths must be valid UTF-8.
            error.InvalidUtf8 => try log(.err, "Invalid UTF-8 in path: {s}", .{path}),
            // Windows-only; file paths provided by the user must be valid WTF-8.
            // https://simonsapin.github.io/wtf-8/
            error.InvalidWtf8 => try log(.err, "Invalid WTF-8 in path: {s}", .{path}),
            error.BadPathName => try log(.err, "Invalid path name: {s}", .{path}),
            error.NoDevice => try log(.err, "No such device for path: {s}", .{path}),
            // On Windows, `\\server` or `\\server\share` was not found.
            error.NetworkNotFound => try log(.err, "Network path not found: {s}", .{path}),
            error.Unexpected => try log(.err, "Unexpected error in zig (please report to https://github.com/gaskam/workspace/issues/): {!}", .{err}),
        }
        return err;
    };
    return true;
}
