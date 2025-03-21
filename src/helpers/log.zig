const std = @import("std");

/// Logging utility module that provides colored console output functionality
/// with different log levels and ANSI color formatting.
/// Represents ANSI color codes for terminal output formatting.
/// Each variant corresponds to a specific color code that can be
/// used to style console text.
pub const Colors = enum {
    reset,
    brightBlue,
    green,
    yellow,
    red,
    blue,
    magenta,
    cyan,
    white,
    grey,

    const colorCodes = [@typeInfo(Colors).Enum.fields.len][]const u8{
        "\x1b[0m", // reset
        "\x1b[94m", // brightBlue
        "\x1b[32m", // green
        "\x1b[33m", // yellow
        "\x1b[31m", // red
        "\x1b[34m", // blue
        "\x1b[35m", // magenta
        "\x1b[36m", // cyan
        "\x1b[37m", // white
        "\x1b[38;5;245m", //grey
    };

    /// Returns the ANSI escape sequence for the specified color.
    pub inline fn code(self: Colors) []const u8 {
        return colorCodes[@intFromEnum(self)];
    }
};

/// Defines the available logging levels for message output.
/// Each level is associated with a specific prefix and color
/// in the console output.
const LogLevel = enum {
    help,
    info,
    cloned,
    warning,
    err,
    default,
};

const StdoutType = @TypeOf(std.io.getStdOut().writer());

const StdoutGetter = struct {
    stdout: ?StdoutType,

    pub fn get(self: *StdoutGetter) StdoutType {
        if (self.stdout == null) {
            const stdout = std.io.getStdOut().writer();
            self.stdout = stdout;
            return stdout;
        }
        return self.stdout.?;
    }
};

var stdoutGetter = StdoutGetter{ .stdout = null };

/// Prints a formatted log message to stdout with the specified level and color.
///
/// Parameters:
///     level: The LogLevel determining the prefix and styling of the message
///     message: The format string for the message to be printed
///     args: The arguments to be formatted into the message string
/// Returns: void, but may return an error if writing to stdout fails
pub inline fn log(
    comptime level: LogLevel,
    comptime message: []const u8,
    args: anytype,
) !void {
    const stdout = stdoutGetter.get();
    switch (level) {
        .help => _ = try stdout.print("{s}[HELP]{s} ", .{ Colors.green.code(), Colors.reset.code() }),
        .info => _ = try stdout.print("{s}[INFO]{s} ", .{ Colors.green.code(), Colors.reset.code() }),
        .cloned => _ = try stdout.print("{s}[CLONED]{s} ", .{ Colors.green.code(), Colors.reset.code() }),
        .warning => _ = try stdout.print("{s}[WARNING]{s} ", .{ Colors.yellow.code(), Colors.reset.code() }),
        .err => _ = try stdout.print("{s}[ERROR]{s} ", .{ Colors.red.code(), Colors.reset.code() }),
        .default => {},
    }
    try stdout.print(message, args);
    if (comptime level != .default) try stdout.writeByte('\n');
}
