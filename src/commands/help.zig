const std = @import("std");
const constants = @import("../const.zig");
const logHelper = @import("../helpers/log.zig");
const commands = @import("../commands.zig");

const log = logHelper.log;
const Colors = logHelper.Colors;

const RESET = Colors.reset.code();
const GREEN = Colors.green.code();
const CYAN = Colors.cyan.code();
const GREY = Colors.grey.code();
const MAGENTA = Colors.magenta.code();
const YELLOW = Colors.yellow.code();
const RED = Colors.red.code();

const command: constants.Command = .{
    .name = "help",
    .function = &execute,
};

pub const definition: constants.Definition = .{ .command = command, .description = "Display help information", .group = .help, .arguments = .{ .optionals = &.{
    .{
        .name = "subcommand",
        .description = "Display help about a specific subcommand",
        .group = .text,
    },
} } };

fn execute(allocator: std.mem.Allocator, args: [][]const u8) anyerror!void {
    _ = allocator;
    const helpMessage =
        "{0s}Workspace{1s} is a powerful application designed to install and manage all your repositories.\n\n" ++
        "Usage: workspace <command> {2s}<requirement>{1s} [...options] {3s}[--flags]{1s}\n\n" ++
        "Commands:\n" ++
        "  {0s}clone{1s} {2s}<organization/user>{1s} [destination]  Clone all repositories from an organization/user\n\n" ++
        "  |-- {3s}[--limit]{1s} {3s}<number>{1s}                   Limit the number of repositories to clone\n" ++
        "  |-- {3s}[--processes]{1s} {3s}<number>{1s}               Limit the number of concurrent processes\n" ++
        "  |                                        -> Default is the number of logical CPUs - 1\n" ++
        "  |-- {3s}[--auto]{1s}, {3s}[--code]{1s}, {3s}[--sublime]{1s}      Generates a workspace file\n" ++
        "  |                                        -> Please note that the 'auto' tag is best practice\n" ++
        "  |-- {3s}[--prune]{1s}                            Delete repositories that do not belong to current user\n\n" ++
        "  {6s}-> Note that if you provide --limit and --prune flags, we'll delete\n" ++
        "     the repositories that no longer exist once the limit is reached.{1s}\n\n" ++
        "  {4s}version{1s}                                  Display version information\n" ++
        "  {4s}update{1s}, {4s}upgrade{1s}                          Update workspace to the latest version\n\n" ++
        "  {5s}help{1s}                                     Display help information\n\n" ++
        "{3s}e.g. => $ workspace clone ziglang ./workspace --limit 10 --processes 5 --prune{1s}\n\n" ++
        "  {6s}uninstall{1s} {3s}[--fast]{1s}                       Uninstall workspace :(\n\n" ++
        "Contribute about Workspace:                {0s}https://github.com/gaskam/workspace{1s}";
    try log(.help, helpMessage, .{
        Colors.green.code(),
        Colors.reset.code(),
        Colors.cyan.code(),
        Colors.grey.code(),
        Colors.magenta.code(),
        Colors.yellow.code(),
        Colors.red.code(),
    });

    // Create a buffer for our help text
    var help_buffer: [8192]u8 = undefined; // Reasonably large buffer for help text
    var fbs = std.io.fixedBufferStream(&help_buffer);
    var writer = fbs.writer();

    try writer.writeAll("Commands:\n");

    inline for (commands.all) |def| {
        // Skip hidden commands
        if (def.group == .hidden) continue;

        const name = def.command.name;
        const alias = def.command.alias;
        const arguments = def.arguments;
        const flags = def.flags;

        // Choose color based on command group
        const color = switch (def.group) {
            .cloning => GREEN,
            .help => YELLOW,
            .versionning => MAGENTA,
            .uninstall => RED,
            .hidden => unreachable,
        };

        // Format command name with color
        try writer.print("  {s}{s}{s}", .{ color, name, RESET });

        // Format alias if present
        if (alias) |a| {
            try writer.print(", {s}{s}{s}", .{ color, a, RESET });
        }

        // Format arguments
        if (arguments.mandatory.len > 0) {
            for (arguments.mandatory) |arg| {
                try writer.print(" {s}<{s}>{s}", .{ CYAN, arg.name, RESET });
            }
        }

        // Format optional arguments
        if (arguments.optionals.len > 0) {
            for (arguments.optionals) |arg| {
                try writer.print(" {s}[{s}]{s}", .{ GREY, arg.name, RESET });
            }
        }

        // Add command description
        try writer.print("  {s}{s}{s}", .{ GREY, def.description, RESET });

        // End the line for the command description
        try writer.writeAll("\n");

        // Format flags if any
        if (flags.len > 0) {
            // Display flag(s) with pipe notation
            for (flags) |flag| {
                // Format the flag with proper alignment
                try writer.print("  |-- ", .{});
                try writer.print("{s}[--{s}]", .{ GREY, flag.name });

                // Add argument placeholders for flags that require values
                if (flag.group == .number) {
                    try writer.print(" {s}<number>{s}", .{ CYAN, RESET });
                }

                // Use proper alignment with a format specifier for the description
                try writer.print("{s}{s:>40}{s}\n", .{ GREY, flag.description, RESET });
            }

            // Add an extra empty line after flags for better readability
            if (flags.len > 0) {
                try writer.writeAll("\n");
            }
        }
    }

    // Print the generated help information
    try log(.default, "{s}", .{fbs.getWritten()});

    if (args.len >= 1 and !std.mem.eql(u8, args[0], "help")) {
        try log(.default, "\n", .{});
        try log(.err, "Unknown command: {s}", .{args[0]});
    }
}
