const std = @import("std");

/// Configuration structure for clone operations
/// targetFolder: Optional destination folder for cloned repositories
/// limit: Optional maximum number of repositories to clone
/// processes: Number of concurrent clone operations
/// prune: Whether to remove repositories that no longer exist
pub const CloneConfig = struct {
    targetFolder: ?[]const u8,
    limit: ?[]const u8 = null,
    processes: usize,
    prune: bool = false,
};

/// Parses command line arguments for clone operations
/// Returns: CloneConfig with parsed settings
/// Error: Returns error if argument parsing fails
pub fn parseArgs(
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
