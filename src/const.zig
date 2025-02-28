const std = @import("std");

/// Core configuration constants
pub const VERSION = "1.3.3";
pub const MAX_INPUT_LENGTH = 64;
pub const MAX_HTTP_BUFFER = 256;

pub const isWindows = @import("builtin").os.tag == .windows;

/// GitHub repository information structure
pub const RepoInfo = struct {
    name: []const u8,
    nameWithOwner: []const u8,
    owner: struct {
        id: []const u8,
        login: []const u8,
    },
};

/// Structure representing VSCode workspace folders
pub const WorkspaceFolder = struct {
    path: []const u8,
};

pub const Command = struct {
    name: []const u8,
    args: type,
    function: fn (std.mem.Allocator, anytype) anyerror!void,
};
