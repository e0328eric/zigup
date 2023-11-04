const std = @import("std");
const builtin = @import("builtin");

const default_use_ncurses = switch (builtin.os.tag) {
    .macos, .linux => true,
    else => false,
};

pub fn build(b: *std.Build) void {
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
    if (use_ncurses) {
        exe.linkSystemLibrary("ncurses");
    }
    exe.addOptions("zigup_build", exe_options);
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
}
