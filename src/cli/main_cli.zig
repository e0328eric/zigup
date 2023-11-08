const std = @import("std");
const builtin = @import("builtin");
const download = @import("./download.zig");

const fmt = std.fmt;
const io = std.io;
const json = std.json;
const mem = std.mem;
const process = std.process;
const time = std.time;
const tty = std.io.tty;

const Allocator = std.mem.Allocator;
const JsonValue = std.json.Value;
const Stdin = @TypeOf(io.getStdIn().reader());
const Stdout = @TypeOf(io.getStdOut().writer());

const getInput = @import("./input_handler.zig").getInput;

const COMPILER_JSON_LINK = @import("../constants.zig").COMPILER_JSON_LINK;
const USAGE_INFO = @import("../constants.zig").USAGE_INFO;

// global variable
var output_filename: [:0]const u8 = undefined;

pub fn main_cli() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try process.argsWithAllocator(allocator);
    defer args.deinit();

    // skip first argument
    _ = args.skip();

    output_filename = if (args.next()) |filename| filename else {
        std.log.err("[ERROR]: there is no output filename\n", .{});
        std.log.err(USAGE_INFO, .{});
        return error.NoFilenameGiven;
    };

    // Take a JSON faile from Web
    const json_bytes = try download.downloadContentIntoMemory(
        allocator,
        COMPILER_JSON_LINK,
        null,
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

    const idx = try show_zig_versions(&json_contents.value, &stdin, &stdout);
    try stdout.writeByte('\n');
    _ = try show_zig_targets(&json_contents.value, idx, &stdin, &stdout);
}

fn show_zig_versions(
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

fn show_zig_targets(
    json_value: *const JsonValue,
    idx: usize,
    stdin: *const Stdin,
    stdout: *const Stdout,
) !usize {
    const raw_zig_version = json_value.object.keys()[idx];
    const zig_info = json_value.object.get(raw_zig_version) orelse return error.InvalidJSON;
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
    var total_amount_target: usize = 0;
    event_loop: while (iter.next()) |entry| {
        for ([_][]const u8{ "version", "date", "docs", "stdDocs", "src", "notes" }) |str| {
            if (mem.eql(u8, str, entry.key_ptr.*)) {
                continue :event_loop;
            }
        }

        // TODO: Align target strings
        try stdout.print("[{}]: {s}\n", .{ total_amount_target, entry.key_ptr.* });

        total_amount_target += 1;
    }

    return getInput(
        usize,
        "Enter the number to select target: ",
        total_amount_target,
        stdin,
        stdout,
    );
}
