const std = @import("std");

const targets: []const std.zig.CrossTarget = &.{
    std.zig.CrossTarget{ .cpu_arch = .x86_64, .os_tag = .windows },
    std.zig.CrossTarget{ .cpu_arch = .x86_64, .os_tag = .linux },
    std.zig.CrossTarget{ .cpu_arch = .aarch64, .os_tag = .linux },
    std.zig.CrossTarget{ .cpu_arch = .x86_64, .os_tag = .macos },
    std.zig.CrossTarget{ .cpu_arch = .aarch64, .os_tag = .macos },

    // Baseline builds
    std.zig.CrossTarget{ .cpu_arch = .x86_64, .os_tag = .linux, .cpu_model = .baseline },
    std.zig.CrossTarget{ .cpu_arch = .x86_64, .os_tag = .macos, .cpu_model = .baseline },
    std.zig.CrossTarget{ .cpu_arch = .x86_64, .os_tag = .windows, .cpu_model = .baseline },
};

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    for (targets) |t| {
        const name =
            if (t.cpu_model == .baseline)
            try std.mem.concat(b.allocator, u8, &.{ "workspace-", try t.zigTriple(b.allocator), "-baseline" })
        else
            try std.mem.concat(b.allocator, u8, &.{ "workspace-", try t.zigTriple(b.allocator) });

        const exe = b.addExecutable(.{
            .name = name,
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(t),
            .optimize = .ReleaseSafe,
        });

        const target_output = b.addInstallArtifact(exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = "",
                },
            },
            .pdb_dir = .disabled,
            .implib_dir = .disabled,
        });

        b.getInstallStep().dependOn(&target_output.step);
    }

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "workspace",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
