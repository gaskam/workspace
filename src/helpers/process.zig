const std = @import("std");

/// Spawns a new child process with the given arguments and working directory
/// Parameters:
///  - allocator: Memory allocator for process resources
///  - argv: Array of command line arguments
///  - cwd: Optional working directory for the process
/// Returns: A Child process handle with configured pipes
/// Error: May return error on process spawn failure
pub fn spawn(allocator: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8) !std.process.Child {
    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.cwd = cwd;
    try child.spawn();
    return child;
}

/// Waits for process completion and collects its output
/// Parameters:
///  - allocator: Memory allocator for output buffers
///  - process: Pointer to the child process to wait for
/// Returns: Process execution result containing exit code and captured output
/// Error: May return error on IO or process operations
pub fn wait(allocator: std.mem.Allocator, process: *std.process.Child) !std.process.Child.RunResult {
    var stdout = std.ArrayList(u8).init(allocator);
    var stderr = std.ArrayList(u8).init(allocator);
    try process.collectOutput(&stdout, &stderr, 4096);

    const term = try process.wait();

    return .{ .term = term, .stdout = try stdout.toOwnedSlice(), .stderr = try stderr.toOwnedSlice() };
}

/// Executes a command with arguments in specified directory and waits for completion
/// Parameters:
///  - allocator: Memory allocator for process resources
///  - args: Array of command arguments
///  - subpath: Optional working directory path
/// Returns: Process execution result
/// Error: Returns GithubCliNotFound if 'gh' command is not available, or other process errors
pub fn run(
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
            return error.GithubCliNotFound;
        }
        return err;
    };
    return cp;
}

/// Frees memory associated with a process result
/// Parameters:
///  - allocator: Memory allocator used for the process
///  - result: Process execution result to clean up
pub fn cleanupProcessResult(allocator: std.mem.Allocator, result: std.process.Child.RunResult) void {
    allocator.free(result.stdout);
    allocator.free(result.stderr);
}
