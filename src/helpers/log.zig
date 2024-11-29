const std = @import("std");

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
    brightBlack,

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
        "\x1b[90m", // brightBlack
    };

    pub inline fn code(self: Colors) []const u8 {
        return colorCodes[@intFromEnum(self)];
    }
};

const LogLevel = enum {
    help,
    info,
    cloned,
    warning,
    err,
};

pub inline fn log(
    comptime level: LogLevel,
    comptime message: []const u8,
    args: anytype,
) !void {
    const stdout = std.io.getStdOut().writer();
    switch (level) {
        .help => _ = try stdout.print("{s}[HELP]{s} ", .{ Colors.green.code(), Colors.reset.code() }),
        .info => _ = try stdout.print("{s}[INFO]{s} ", .{ Colors.green.code(), Colors.reset.code() }),
        .cloned => _ = try stdout.print("{s}[CLONED]{s} ", .{ Colors.green.code(), Colors.reset.code() }),
        .warning => _ = try stdout.print("{s}[WARNING]{s} ", .{ Colors.yellow.code(), Colors.reset.code() }),
        .err => _ = try stdout.print("{s}[ERROR]{s} ", .{ Colors.red.code(), Colors.reset.code() }),
    }
    try stdout.print(message, args);
    try stdout.writeByte('\n');
}
