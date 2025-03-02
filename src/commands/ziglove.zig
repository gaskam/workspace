const std = @import("std");
const constants = @import("../const.zig");

const logHelper = @import("../helpers/log.zig");

const log = logHelper.log;
const Colors = logHelper.Colors;

pub const command: constants.Command = .{
    .name = "ziglove",
    .function = &execute,
};

fn execute(allocator: std.mem.Allocator, args: constants.Args) anyerror!void {
    _ = .{ allocator, args };
    try log(.info, "We love {s}Zig{s} too!\n\nLet's support them on {s}https://github.com/ziglang/zig{s}", .{ Colors.yellow.code(), Colors.reset.code(), Colors.green.code(), Colors.reset.code() });
}
