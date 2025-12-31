const std = @import("std");
const builtin = @import("builtin");

const default_use_ncurses = false;

const ZIGUP_VERSION_STR = @import("build.zig.zon").version;
const ZIGUP_VERSION = std.SemanticVersion.parse(ZIGUP_VERSION_STR) catch unreachable;
const MIN_ZIG_STRING = @import("build.zig.zon").minimum_zig_version;
const MIN_ZIG = std.SemanticVersion.parse(MIN_ZIG_STRING) catch unreachable;
const PROGRAM_NAME = @tagName(@import("build.zig.zon").name);

const Build = blk: {
    const version = builtin.zig_version;
    if (version.order(MIN_ZIG) == .lt) {
        @compileError(std.fmt.comptimePrint(
            "Old zig is detected, (ver: {s}). Use the recent zig at least {s}.",
            .{ builtin.zig_version_string, MIN_ZIG_STRING },
        ));
    }
    break :blk std.Build;
};

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const badepo = b.dependency("badepo", .{
        .target = target,
        .optimize = optimize,
    }).module("badepo");

    const exe = b.addExecutable(.{
        .name = PROGRAM_NAME,
        .version = ZIGUP_VERSION,
        .root_module = b.createModule(.{
            .root_source_file = b.path("./src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = if (optimize == .Debug) false else true,
            .link_libc = true,
            .imports = &.{
                .{ .name = "badepo", .module = badepo },
            },
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
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
        const cross_target = b.resolveTargetQuery(t);
        const badepo_cross = b.dependency("badepo", .{
            .target = cross_target,
            .optimize = optimize,
        }).module("badepo");

        const release_exe = b.addExecutable(.{
            .name = PROGRAM_NAME,
            .version = ZIGUP_VERSION,
            .root_module = b.createModule(.{
                .root_source_file = b.path("./src/main.zig"),
                .target = cross_target,
                .optimize = .ReleaseSafe,
                .strip = true,
                .link_libc = true,
                .imports = &.{
                    .{ .name = "badepo", .module = badepo_cross },
                },
            }),
        });

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
