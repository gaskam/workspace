//! Workspace - A CLI tool for managing GitHub repositories.
//! Provides functionalities for cloning repositories and generating VSCode workspace files.

const std = @import("std");
const constants = @import("const.zig");

/// A custom command list generated by build.zig
const commands = @import("commands.zig").all;

// Inspired from std.meta.stringToEnum
const commandsMap = blk: {
    const kvs = build_kvs: {
        const EnumKV = struct { []const u8, *const constants.Command };
        var kvs_array: [commands.len * 2]EnumKV = undefined;
        var i = 0;
        for (commands) |command| {
            kvs_array[i] = .{ command.name, &command };
            if (command.alias) |alias| {
                kvs_array[i + 1] = .{ alias, &command };
                i += 2;
            } else {
                i += 1;
            }
        }
        break :build_kvs kvs_array[0..i];
    };
    const map = std.StaticStringMap(*const constants.Command).initComptime(kvs);
    
    break :blk map;
};

const helpCommand = commandsMap.get("help") orelse @compileError("Unable to locate help command.");

/// Specific imports
const parseArgs = @import("helpers/args.zig").parseArgs;
const ProcessPool = @import("helpers/pool.zig").ProcessPool;
const prune = @import("helpers/prune.zig").prune;

/// Entry point of the application.
/// Handles command-line arguments and dispatches to appropriate handlers.
pub fn main() !void {
    // Use GPA for long-lived allocations
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = GPA.deinit();
    const allocator = GPA.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const command = commandsMap.get(if (args.len >= 2) args[1] else "help") orelse helpCommand;

    try command.function(allocator, args[1..]);
}
