const std = @import("std");
const download = @import("./download.zig");

const fmt = std.fmt;
const io = std.io;
const json = std.json;
const mem = std.mem;
const process = std.process;
const time = std.time;
const tty = std.io.tty;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const JsonValue = std.json.Value;
const Stdin = @TypeOf(io.getStdIn().reader());
const Stdout = @TypeOf(io.getStdOut().writer());

const getInput = @import("./input_handler.zig").getInput;

const COMPILER_JSON_LINK = @import("../constants.zig").COMPILER_JSON_LINK;
const USAGE_INFO = @import("../constants.zig").USAGE_INFO;
const DEFAULT_FILENAME = @import("../constants.zig").DEFAULT_FILENAME;

pub fn main_cli() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try process.argsWithAllocator(allocator);
    defer args.deinit();

    // skip first argument
    _ = args.skip();

    const output_filename: [:0]const u8 = if (args.next()) |filename|
        filename
    else
        DEFAULT_FILENAME;

    // Take a JSON faile from Web
    const json_bytes = try download.downloadContentIntoMemory(
        allocator,
        COMPILER_JSON_LINK,
        0,
    );
    defer {
        json_bytes.body.deinit();
        json_bytes.mime.deinit();
    }

    if (!mem.eql(u8, json_bytes.mime.items, "application/json")) {
        return error.NotAJSON;
    }

    const json_contents = try json.parseFromSlice(
        json.Value,
        allocator,
        json_bytes.body.items,
        .{},
    );
    defer json_contents.deinit();

    const stdout = io.getStdOut().writer();
    const stdin = io.getStdIn().reader();

    const idx = try showZigVersions(
        &json_contents.value,
        &stdin,
        &stdout,
    );
    try stdout.writeByte('\n');
    const version_target_info = try showZigTargets(
        allocator,
        &json_contents.value,
        idx,
        &stdin,
        &stdout,
    );
    defer allocator.free(version_target_info.target_name);

    try stdout.writeByte('\n');
    try downloadContent(
        allocator,
        &version_target_info,
        output_filename,
        &stdout,
    );
}

fn showZigVersions(
    json_value: *const JsonValue,
    stdin: *const Stdin,
    stdout: *const Stdout,
) !usize {
    const tty_config = tty.detectConfig(io.getStdOut());

    try tty_config.setColor(stdout, .yellow);
    try stdout.writeAll("[Select Version]\n");
    try tty_config.setColor(stdout, .reset);

    const total_amount_version = json_value.object.keys().len;
    for (json_value.object.keys(), 0..) |keys, i| {
        // TODO: Align version strings
        try stdout.print("[{}]: {s}\n", .{ i, keys });
    }

    return getInput(
        usize,
        "Enter the number to select version: ",
        total_amount_version,
        stdin,
        stdout,
    );
}

const VersionTargetInfo = struct {
    zig_info: *const JsonValue,
    zig_version: []const u8,
    target_name: []const u8,
};

// NOTE: The return string is allocated, so it should be freed
fn showZigTargets(
    allocator: Allocator,
    json_value: *const JsonValue,
    idx: usize,
    stdin: *const Stdin,
    stdout: *const Stdout,
) !VersionTargetInfo {
    const raw_zig_version = json_value.object.keys()[idx];
    const zig_info = json_value.object.getPtr(raw_zig_version) orelse
        return error.InvalidJSON;
    const zig_version = zig_version: {
        if (mem.eql(u8, raw_zig_version, "master")) {
            break :zig_version (zig_info.object.get("version") orelse return error.InvalidJSON).string;
        } else {
            break :zig_version raw_zig_version;
        }
    };

    const tty_config = tty.detectConfig(io.getStdOut());

    try tty_config.setColor(stdout, .yellow);
    try stdout.print("[Version: {s}] [Targets]\n", .{zig_version});
    try tty_config.setColor(stdout, .reset);

    var iter = zig_info.object.iterator();
    var target_names = try ArrayList([]const u8).initCapacity(allocator, 25);
    defer target_names.deinit();

    fill_container: while (iter.next()) |entry| {
        for ([_][]const u8{
            "version",
            "date",
            "docs",
            "stdDocs",
            "src",
            "notes",
        }) |str| {
            if (mem.eql(u8, str, entry.key_ptr.*)) {
                continue :fill_container;
            }
        }

        try target_names.append(entry.key_ptr.*);
    }

    for (target_names.items, 0..) |target_name, i| {
        // TODO: Align target strings
        try stdout.print("[{}]: {s}\n", .{ i, target_name });
    }

    const target_name_idx = try getInput(
        usize,
        "Enter the number to select target: ",
        target_names.items.len,
        stdin,
        stdout,
    );
    const target_name = target_names.items[target_name_idx];

    const output = try allocator.alloc(u8, target_name.len);
    errdefer allocator.free(output);

    @memcpy(output, target_name);

    return .{
        .zig_info = zig_info,
        .zig_version = zig_version,
        .target_name = output,
    };
}

fn downloadContent(
    allocator: Allocator,
    version_target_info: *const VersionTargetInfo,
    output_filename: []const u8,
    stdout: *const Stdout,
) !void {
    const tty_config = tty.detectConfig(io.getStdOut());

    try tty_config.setColor(stdout, .yellow);
    try stdout.print("[Downloading Content] [Version: {s}, Target: {s}]\n", .{
        version_target_info.zig_version,
        version_target_info.target_name,
    });
    try tty_config.setColor(stdout, .reset);

    // Download zig compiler
    // TODO: Check shasum with the downloaded file in the memory.
    // TODO: Implement a name maker for the tarball.
    const target_info = try getTargetInfo(
        version_target_info.zig_info,
        version_target_info.target_name,
    );
    try download.downloadContentIntoFile(
        allocator,
        true,
        target_info.tarball_url,
        target_info.content_size,
        output_filename,
    );

    try stdout.writeByte('\n');
    try tty_config.setColor(stdout, .yellow);
    try stdout.print("[Download Finished]\n", .{});
    try tty_config.setColor(stdout, .reset);
}

const TargetInfo = struct {
    tarball_url: []const u8,
    shasum: []const u8,
    content_size: u64,
};

fn getTargetInfo(zig_info: *const JsonValue, target_name: []const u8) !TargetInfo {
    var output: TargetInfo = undefined;
    const target_info = zig_info.object.get(target_name) orelse return error.CannotGetTargetInfo;
    output.tarball_url = target_url: {
        const tmp = target_info.object.get("tarball") orelse return error.CannotGetTarballUrl;
        break :target_url tmp.string;
    };
    output.shasum = target_shasum: {
        const tmp = target_info.object.get("shasum") orelse return error.CannotGetTarballUrl;
        break :target_shasum tmp.string;
    };
    output.content_size = content_size: {
        const tmp = target_info.object.get("size") orelse return error.CannotGetTarballUrl;
        break :content_size try fmt.parseInt(u64, tmp.string, 10);
    };

    return output;
}
