const std = @import("std");

pub fn main() !void {
    const args = [_][]const u8{
        "test",
        "--limit",
        "5",
        "--processes",
        "3",
        "--prune",
    };

    const config = try parseArgs(&args, "test");

    std.debug.print("config: {any}\n", .{config});
    std.debug.print("config.targetFolder: {s}\n", .{config.targetFolder});
}

const CloneConfig = struct {
    targetFolder: []const u8,
    limit: ?usize = null,
    processes: usize,
    prune: bool = false,
};

fn parseArgs(
    args: []const []const u8,
    defaultFolder: []const u8,
) !CloneConfig {
    var usedArgs: usize = 0;
    var config = CloneConfig{ .targetFolder = defaultFolder, .processes = try std.Thread.getCpuCount() - 1 };
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
                const limit = try std.fmt.parseInt(usize, args[usedArgs + 1], 10);
                config.limit = limit;
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
