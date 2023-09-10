const std = @import("std");
const builtin = @import("builtin");
const main_menu = @import("./main_menu.zig");
const download = @import("./download.zig");

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

const compiler_json_link: []const u8 = "https://ziglang.org/download/index.json";

const DEFAULT_FOREGROUND: c_short = -1;
const DEFAULT_BACKGROUND: c_short = -1;

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

    var main_win = main_menu.createWindow(@intCast(ncurses.LINES - 1), @intCast(ncurses.COLS - 1), 0, 0);
    defer main_menu.destroyWindow(main_win);

    var cursor = Cursor{ .row = 3, .col = 2 };
    try main_menu.decorateMainWindow(main_win, allocator, &json_contents.value, cursor);

    var chr: c_int = 0;
    while (true) {
        chr = ncurses.getch();

        switch (chr) {
            'q' => break,
            'w', ncurses.KEY_UP => cursor.row = @max(cursor.row -| 1, 3),
            's', ncurses.KEY_DOWN => cursor.row = @min(
                cursor.row +| 1,
                @as(usize, @intCast(@max(0, ncurses.LINES - 3))),
            ),
            '\n' => try dumpJSON(allocator, &json_contents.value, cursor),
            else => {},
        }
        time.sleep(time.ns_per_ms * 20);

        main_menu.destroyWindow(main_win);
        main_win = main_menu.createWindow(
            @intCast(ncurses.LINES - 1),
            @intCast(ncurses.COLS - 1),
            0,
            0,
        );
        try main_menu.decorateMainWindow(main_win, allocator, &json_contents.value, cursor);
    }
}

const JsonValue = std.json.Value;
fn dumpJSON(allocator: Allocator, json_value: *const JsonValue, cursor: Cursor) !void {
    var win = main_menu.createWindow(
        @intCast(@divTrunc(ncurses.LINES, 2)),
        @intCast(@divTrunc(ncurses.COLS, 2)),
        @intCast(@divTrunc(ncurses.LINES, 4)),
        @intCast(@divTrunc(ncurses.COLS, 4)),
    );
    defer main_menu.destroyWindow(win);
    try decorateDumpJson(win, allocator, json_value, cursor);

    var chr: c_int = 0;
    while (true) {
        chr = ncurses.getch();

        switch (chr) {
            'q' => break,
            else => {},
        }
        time.sleep(time.ns_per_ms * 20);

        main_menu.destroyWindow(win);
        win = main_menu.createWindow(
            @intCast(@divTrunc(ncurses.LINES, 2)),
            @intCast(@divTrunc(ncurses.COLS, 2)),
            @intCast(@divTrunc(ncurses.LINES, 4)),
            @intCast(@divTrunc(ncurses.COLS, 4)),
        );

        try decorateDumpJson(win, allocator, json_value, cursor);
    }
}

fn decorateDumpJson(
    win: ?*ncurses.WINDOW,
    allocator: Allocator,
    json_value: *const JsonValue,
    cursor: Cursor,
) !void {
    const idx = cursor.row -| 3;
    const zig_version = json_value.object.keys()[idx];
    const zig_info = json_value.object.get(zig_version) orelse return error.InvalidJSON;

    const title = "Version Info";

    const zig_version_null = zig_version: {
        if (mem.eql(u8, zig_version, "master")) {
            const master_version = (zig_info.object.get("version") orelse return error.InvalidJSON).string;
            break :zig_version try allocator.dupeZ(u8, master_version);
        } else {
            break :zig_version try allocator.dupeZ(u8, zig_version);
        }
    };
    defer allocator.free(zig_version_null);

    _ = ncurses.box(win, 0, 0);
    _ = ncurses.mvwprintw(win, 0, @divTrunc(ncurses.getmaxx(win) -| @as(c_int, title.len), 2), title);
    _ = ncurses.mvwprintw(win, 1, 1, "Version: ");
    _ = ncurses.mvwprintw(win, 1, @intCast(1 + "Version: ".len), @ptrCast(zig_version_null));

    var iter = zig_info.object.iterator();
    var i: c_int = 3;
    event_loop: while (iter.next()) |entry| {
        for ([_][]const u8{ "version", "date", "docs", "stdDocs", "src", "notes" }) |str| {
            if (mem.eql(u8, str, entry.key_ptr.*)) {
                continue :event_loop;
            }
        }

        const target_info = &entry.value_ptr.object;
        const tarball_null = try allocator.dupeZ(u8, target_info.get("tarball").?.string);
        defer allocator.free(tarball_null);

        _ = ncurses.mvwprintw(win, i, 1, @ptrCast(tarball_null));
        i += 1;
    }
    _ = ncurses.wrefresh(win);
}
