const std = @import("std");
const builtin = @import("builtin");
const download = @import("./download.zig");

const windows = if (IS_WINDOWS) @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", {});
    @cInclude("windows.h");
}) else {};
//
// wiindows related constants
const IS_WINDOWS = builtin.os.tag == .windows;
const TRUE = windows.TRUE;
const FALSE = windows.FALSE;

const mem = std.mem;
const json = std.json;
const time = std.time;
const process = std.process;
const io = std.io;

const Allocator = std.mem.Allocator;

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

    // std.debug.print("{s}\n", .{json_bytes.body.items});

    const stdout = io.getStdOut().writer();
    try stdout.print("\x1b[35mHello, World!\x1b[0m\n", .{});
}
