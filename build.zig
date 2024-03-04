const std = @import("std");
const builtin = @import("builtin");

const default_use_ncurses = switch (builtin.os.tag) {
    .macos, .linux => true,
    else => false,
};

pub const MIN_ZIG_VERSION_STR = "0.12.0-dev.2925+88b3c1442";
pub const MIN_ZIG_VERSION = std.SemanticVersion.parse(MIN_ZIG_VERSION_STR) catch unreachable;

const Build = blk: {
    const version = builtin.zig_version;
    if (version.order(MIN_ZIG_VERSION) == .lt) {
        @compileError(std.fmt.comptimePrint(
            "Old zig is detected, (ver: {s}). Use the recent zig at least {s}.",
            .{ builtin.zig_version_string, MIN_ZIG_VERSION_STR },
        ));
    }
    break :blk std.Build;
};

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const use_ncurses = b.option(
        bool,
        "ncurses",
        \\tui version that uses ncurses
        \\before compile this, the machine should have ncurses library
        ,
    ) orelse default_use_ncurses;

    const exe_options = b.addOptions();
    exe_options.addOption(bool, "use_ncurses", use_ncurses);

    const exe = b.addExecutable(.{
        .name = "zigup",
        .root_source_file = .{ .path = "./src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    if (use_ncurses) exe.linkSystemLibrary("ncurses");
    exe.linkLibC();
    exe.root_module.addOptions("zigup_build", exe_options);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Release
    const release_step = b.step("release", "Make zigup binaries for release");
    const targets: []const std.Target.Query = &.{
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .x86_64, .os_tag = .windows },
    };

    for (targets) |t| {
        const release_exe = b.addExecutable(.{
            .name = "zigup",
            .root_source_file = .{ .path = "./src/main.zig" },
            .target = b.resolveTargetQuery(t),
            .optimize = .ReleaseSafe,
        });

        release_exe.linkLibC();
        release_exe.root_module.addOptions("zigup_build", exe_options);

        const target_output = b.addInstallArtifact(release_exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = try t.zigTriple(b.allocator),
                },
            },
        });

        release_step.dependOn(&target_output.step);
    }
}
