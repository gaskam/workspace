const std = @import("std");
const Command = @import("../const.zig").Command;

const logHelper = @import("../helpers/log.zig");
const constants = @import("../const.zig");

const log = logHelper.log;
const Colors = logHelper.Colors;

pub const command: Command = .{
    .name = "uninstall",
    .args = struct {},
    .function = execute,
};

fn execute(allocator: std.mem.Allocator, args: anytype) anyerror!void {
    if (args.len == 3 and std.mem.eql(u8, args[2], "--fast")) {
        try uninstall(allocator);
    } else {
        const stdout = std.io.getStdOut();
        var bw = std.io.bufferedWriter(stdout.writer());
        try log(.warning, "This command will {s}UNINSTALL WORKSPACE{s} from your system.\n\nAre you sure you want to proceed? [y/N]", .{ Colors.red.code(), Colors.reset.code() });
        try log(.default, "> ", .{});
        try bw.flush();
        const stdin = std.io.getStdIn().reader();

        var inputList = std.ArrayList(u8).init(allocator);
        defer inputList.deinit();
        try stdin.streamUntilDelimiter(inputList.writer(), '\n', 10);
        if (constants.isWindows and inputList.getLastOrNull() == '\r') {
            _ = inputList.pop();
        }
        if (inputList.items.len == 1 and (inputList.items[0] == 'y' or inputList.items[0] == 'Y')) {
            try uninstall(allocator);
        } else {
            try log(.default, "\n", .{});
            try log(.info, "Uninstall process aborted :) Welcome back!", .{});
        }
    }
}

fn uninstall(allocator: std.mem.Allocator) anyerror!void {
    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    var selfExeDir = try std.fs.openDirAbsolute(try std.fs.selfExeDirPath(&buf), .{});
    defer selfExeDir.close();
    const path = try selfExeDir.realpathAlloc(allocator, "../");
    defer allocator.free(path);
    try log(.default, "\n", .{});
    try log(.info, "Uninstalling Workspace from {s}", .{path});
    if (!std.mem.endsWith(u8, path, ".workspace")) {
        try log(.err, "Failed to uninstall Workspace:", .{});
        try log(.err, "-> Invalid workspace path: {s}", .{path});
        return;
    }

    if (constants.isWindows) {
        const escapedPath = try std.fmt.allocPrint(allocator, "{s}", .{path});
        defer allocator.free(escapedPath);

        const ps_cmd = &[_][]const u8{
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            "Start-Sleep",
            "-Seconds",
            "2;",
            "Remove-Item",
            "-Path",
            escapedPath,
            "-Recurse",
            "-Force",
        };

        var child = std.process.Child.init(ps_cmd, allocator);
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;

        child.spawn() catch |err| {
            try log(.default, "\n", .{});
            try log(.err, "Failed to spawn uninstall process: {s}", .{@errorName(err)});
            return;
        };
    } else {
        try std.fs.deleteTreeAbsolute(path);
    }
}
