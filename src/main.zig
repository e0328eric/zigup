const std = @import("std");
const builtin = @import("builtin");
const download = @import("./download.zig");
const window = @import("./window.zig");

const mem = std.mem;
const json = std.json;
const time = std.time;

const ncurses = switch (builtin.os.tag) {
    .linux, .macos => @cImport({
        @cInclude("ncurses.h");
    }),
    else => @compileError("This program uses <ncurses.h> and targeting OS does not supports it."),
};

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Cursor = @import("./cursor.zig");
const MainWindow = @import("./MainWindow.zig");
const TargetMenu = @import("./TargetMenu.zig");
const JsonValue = std.json.Value;

const DEFAULT_FOREGROUND = @import("./constants.zig").DEFAULT_FOREGROUND;
const DEFAULT_BACKGROUND = @import("./constants.zig").DEFAULT_BACKGROUND;

const compiler_json_link: []const u8 = "https://ziglang.org/download/index.json";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Take a JSON file from Web
    const json_bytes = try download.downloadContentIntoMemory(
        allocator,
        false,
        0,
        compiler_json_link,
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

    // Initialize ncurses TUI
    _ = ncurses.initscr();
    defer _ = ncurses.endwin();

    if (!ncurses.has_colors()) {
        _ = ncurses.endwin();
        std.debug.print("[ERROR]: This terminal does not support colors.\n", .{});
        std.debug.print("[NOTE]: There is a plan to support for non-colorable terminals.\n", .{});
        return error.NonColorableTerminal;
    }
    _ = ncurses.start_color();
    _ = ncurses.use_default_colors();
    _ = ncurses.raw();
    _ = ncurses.keypad(ncurses.stdscr, true);
    _ = ncurses.noecho();
    _ = ncurses.curs_set(0); // make cursor invisible
    // End of the Initialization

    // Making color palettes
    _ = ncurses.init_pair(1, DEFAULT_FOREGROUND, DEFAULT_BACKGROUND);
    _ = ncurses.init_pair(2, DEFAULT_FOREGROUND, ncurses.COLOR_MAGENTA);
    // End of making color palettes

    var main_win = try MainWindow.init(
        allocator,
        @intCast(ncurses.LINES - 1),
        @intCast(ncurses.COLS - 1),
        0,
        0,
        "Zigup",
    );
    defer main_win.deinit();

    var cursor = Cursor{ .row = 3, .col = 2 };
    var max_keydown_row: usize = undefined;
    try main_win.decorate(&json_contents.value, cursor, &max_keydown_row);

    var chr: c_int = 0;
    while (true) {
        chr = ncurses.getch();

        switch (chr) {
            'q' => break,
            'w', ncurses.KEY_UP => cursor.row = @max(cursor.row -| 1, 3),
            's', ncurses.KEY_DOWN => cursor.row = @min(cursor.row +| 1, max_keydown_row),
            '\n' => try targetMenuEventLoop(allocator, &json_contents.value, cursor),
            else => {},
        }
        time.sleep(time.ns_per_ms * 20);

        try main_win.decorate(&json_contents.value, cursor, &max_keydown_row);
    }
}

fn targetMenuEventLoop(
    allocator: Allocator,
    json_value: *const JsonValue,
    cursor: Cursor,
) !void {
    const idx = cursor.row -| 3;
    const raw_zig_version = json_value.object.keys()[idx];
    const zig_info = json_value.object.get(raw_zig_version) orelse return error.InvalidJSON;
    const zig_version = zig_version: {
        if (mem.eql(u8, raw_zig_version, "master")) {
            break :zig_version (zig_info.object.get("version") orelse return error.InvalidJSON).string;
        } else {
            break :zig_version raw_zig_version;
        }
    };

    var target_menu = try TargetMenu.init(
        allocator,
        @intCast(@divTrunc(ncurses.LINES, 2)),
        @intCast(@divTrunc(ncurses.COLS, 2)),
        @intCast(@divTrunc(ncurses.LINES, 4)),
        @intCast(@divTrunc(ncurses.COLS, 4)),
        "Version Info",
        zig_version,
    );
    defer target_menu.deinit();

    try target_menu.decorate(&zig_info, cursor);

    var chr: c_int = 0;
    while (true) {
        chr = ncurses.getch();

        switch (chr) {
            'q' => break,
            else => {},
        }
        time.sleep(time.ns_per_ms * 20);

        try target_menu.decorate(&zig_info, cursor);
    }
}
