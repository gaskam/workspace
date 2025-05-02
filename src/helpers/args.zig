const std = @import("std");
const constants = @import("../const.zig");
const log = @import("log.zig").log;

/// Configuration structure for clone operations
/// targetFolder: Optional destination folder for cloned repositories
/// limit: Optional maximum number of repositories to clone
/// processes: Number of concurrent clone operations
/// prune: Whether to remove repositories that no longer exist
pub const CloneConfig = struct {
    targetFolder: ?[]const u8 = null,
    limit: ?[]const u8 = null,
    processes: usize,
    prune: bool = false,
};

fn ArgType(arg_type: constants.ArgType) type {
    return switch (arg_type) {
        .filepath, .text => []const u8,
    };
}

fn FlagType(flag_type: constants.FlagsType) type {
    return switch (flag_type) {
        .boolean => ?bool,
        .number => ?usize,
    };
}

fn DefaultValue(T: type) *const anyopaque {
    return @ptrCast(&@as(T, switch (T) {
        []const u8 => "",
        ?bool => null,
        ?usize => null,
        else => unreachable,
    }));
}

fn ParseArgsResult(specification: constants.Definition) type {
    var mandatory_fields_list: [specification.arguments.mandatory.len]std.builtin.Type.StructField = undefined;
    for (specification.arguments.mandatory, 0..) |arg, i| {
        mandatory_fields_list[i] = .{
            .name = arg.name,
            .type = ArgType(arg.group),
            .default_value_ptr = DefaultValue(ArgType(arg.group)),
            .is_comptime = false,
            .alignment = @alignOf(ArgType(arg.group)),
        };
    }

    const Mandatory = @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &mandatory_fields_list,
            .decls = &.{},
            .is_tuple = false,
        }
    });

    var optional_fields_list: [specification.arguments.optionals.len]std.builtin.Type.StructField = undefined;
    for (specification.arguments.optionals, 0..) |arg, i| {
        optional_fields_list[i] = .{
            .name = arg.name,
            .type = ArgType(arg.group),
            .default_value_ptr = DefaultValue(ArgType(arg.group)),
            .is_comptime = false,
            .alignment = @alignOf(ArgType(arg.group)),
        };
    }

    const Optionals = @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &optional_fields_list,
            .decls = &.{},
            .is_tuple = false,
        }
    });

    var flags_list: [specification.flags.len]std.builtin.Type.StructField = undefined;
    for (specification.flags, 0..) |flag, i| {
        flags_list[i] = .{
            .name = flag.name,
            .type = FlagType(flag.group),
            .default_value_ptr = DefaultValue(FlagType(flag.group)),
            .is_comptime = false,
            .alignment = @alignOf(FlagType(flag.group)),
        };
    }

    const Flags = @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &flags_list,
            .decls = &.{},
            .is_tuple = false,
        }
    });

    return struct {
        mandatory: Mandatory = .{},
        optionals: Optionals = .{},
        flags: Flags = .{},
    };
}

/// Parses command line arguments for clone operations
/// Returns: CloneConfig with parsed settings
/// Error: Returns error if argument parsing fails
pub fn parseArgs(
    comptime specification: constants.Definition,
    args: []const []const u8,
) !ParseArgsResult(specification) {
    var index: usize = 0;
    var result: ParseArgsResult(specification) = .{};
    inline for (specification.arguments.mandatory) |argument| {
        if (args[index][0] == '-') {
            try log(.err, "Missing required positional argument {s}", .{ argument.name });
            return error.MissingRequiredArgument;
        }
        @field(result.mandatory, argument.name) = args[index];
        index += 1;
    }

    inline for (specification.arguments.optionals) |argument| {
        if (args[index][0] == '-') break;
        @field(result.optionals, argument.name) = args[index];
        index += 1;
    }

    // TODO: add support for flags

    return result;
}
