const std = @import("std");
const Command = @import("../const.zig").Command;

const logHelper = @import("../helpers/log.zig");
const constants = @import("../const.zig");
const network = @import("../helpers/network.zig");

const log = logHelper.log;
const Colors = logHelper.Colors;

pub const command: Command = .{
    .name = "version",
    .args = struct {},
    .function = execute,
};

fn execute(allocator: std.mem.Allocator, args: anytype) anyerror!void {
    _ = args;
    try log(.info, "{s}", .{constants.VERSION});
    try network.threadedCheckConnection();
    const latestVersion = try network.checkForUpdates(allocator);
    if (latestVersion) {
        try log(.default, "\n", .{});
        try log(.warning, "A new version is available! Please run `workspace update` to update to the latest version.", .{});
    }
}
