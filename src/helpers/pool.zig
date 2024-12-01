const std = @import("std");
const processHelper = @import("process.zig");
const logHelper = @import("log.zig");
const RepoInfo = @import("../const.zig").RepoInfo;

/// Process helper aliases
const spawn = processHelper.spawn;
const wait = processHelper.wait;
const run = processHelper.run;
const cleanupProcessResult = processHelper.cleanupProcessResult;

/// Log helper aliases
const log = logHelper.log;
const Colors = logHelper.Colors;

/// Structure for managing clone processes
const Process = struct {
    child: std.process.Child,
    repo: RepoInfo,
};

const ProcessResult = struct {
    success: bool,
    result: std.process.Child.RunResult,
};

const NodeType = std.DoublyLinkedList(Process).Node;

/// Structure for managing a pool of clone processes
pub const ProcessPool = struct {
    processes: std.DoublyLinkedList(Process),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ProcessPool {
        return ProcessPool{
            .processes = std.DoublyLinkedList(Process){},
            .allocator = allocator,
        };
    }

    pub fn spawn(self: *ProcessPool, repo: RepoInfo, targetFolder: []const u8) !void {
        const node = try self.allocator.create(NodeType);
        node.data = try spawnCloneProcess(self.allocator, repo, targetFolder);
        self.processes.append(node);
    }

    pub fn next(self: *ProcessPool) !?ProcessResult {
        if (self.processes.len == 0) return null;

        const node = self.processes.popFirst().?;
        defer self.allocator.destroy(node);
        const firstProcess = node.data;

        const result = try wait(self.allocator, @constCast(&firstProcess.child));
        defer cleanupProcessResult(self.allocator, result);

        const success = try handleCloneResult(result, firstProcess.repo);

        return .{
            .success = success,
            .result = result,
        };
    }
};

/// Creates and starts a clone process for a repository
/// allocator: Memory allocator for process creation
/// repo: Repository information
/// targetFolder: Destination folder for the clone
/// Returns: Process structure containing child process and repo info
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

/// Processes the result of a repository clone operation
/// result: Process execution result
/// repo: Repository information
/// Returns: true if clone was successful, false otherwise
fn handleCloneResult(result: std.process.Child.RunResult, repo: RepoInfo) !bool {
    switch (result.term.Exited) {
        0 => {
            try log(.cloned, "{s}{s}{s}", .{ Colors.brightBlue.code(), repo.nameWithOwner, Colors.reset.code() });
            return true;
        },
        1 => {
            try log(.err, "Failed to clone {s}: {s}", .{ repo.nameWithOwner, result.stderr });
            return false;
        },
        else => {
            try log(.err, "Unexpected error: {d} (when cloning {s})\n{s}", .{ result.term.Exited, repo.nameWithOwner, result.stderr });
            return false;
        },
    }
}
