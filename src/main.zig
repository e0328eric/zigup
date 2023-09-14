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
const DownloadPopup = @import("./DownloadPopup.zig");
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
        null,
        compiler_json_link,
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

    // Initialize ncurses TUI
    _ = ncurses.initscr();
    defer _ = ncurses.endwin();

    // Fix the minimal size of the terminal
    // TODO: Implement the branch in here

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
            '\n' => {
                const idx = cursor.row -| 3;
                try targetMenuEventLoop(allocator, &json_contents.value, idx);
            },
            else => {},
        }
        time.sleep(time.ns_per_ms * 20);

        try main_win.decorate(&json_contents.value, cursor, &max_keydown_row);
    }
}

fn targetMenuEventLoop(
    allocator: Allocator,
    json_value: *const JsonValue,
    idx: usize,
) !void {
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

    var cursor = cursor: {
        var tmp = target_menu.getBegYX();
        tmp.row += 3;
        tmp.col += 1;
        break :cursor tmp;
    };

    var max_keydown_row: usize = undefined;
    var min_keydown_row: usize = undefined;
    try target_menu.decorate(&zig_info, cursor, &max_keydown_row, &min_keydown_row);

    var chr: c_int = 0;
    while (true) {
        chr = ncurses.getch();

        switch (chr) {
            'q' => break,
            'w', ncurses.KEY_UP => cursor.row = @max(cursor.row -| 1, min_keydown_row),
            's', ncurses.KEY_DOWN => cursor.row = @min(cursor.row +| 1, max_keydown_row),
            '\n' => if (target_menu.getTargetName()) |target_name| {
                var title = try ArrayList(u8).initCapacity(allocator, 25);
                defer title.deinit();

                const title_writer = title.writer();
                try title_writer.print("{s}/{s}", .{ zig_version, target_name });
                try downloadZigCompiler(allocator, &zig_info, title.items, target_name);
            },
            else => {},
        }
        time.sleep(time.ns_per_ms * 20);

        try target_menu.decorate(&zig_info, cursor, &max_keydown_row, &min_keydown_row);
    }
}

fn downloadZigCompiler(
    allocator: Allocator,
    zig_info: *const JsonValue,
    title: []const u8,
    target_name: []const u8,
) !void {
    var download_popup = try DownloadPopup.init(
        allocator,
        @intCast(@divTrunc(ncurses.LINES, 4)),
        @intCast(@divTrunc(ncurses.COLS, 8) * 3),
        @intCast(@divTrunc(ncurses.LINES, 5) * 2),
        @intCast(@divTrunc(ncurses.COLS, 16) * 5),
        title,
    );
    defer download_popup.deinit();

    download_popup.preDownloadDecorate();

    var chr: c_int = 0;
    while (true) {
        chr = ncurses.getch();

        switch (chr) {
            'q' => break,
            'a',
            ncurses.KEY_LEFT,
            'd',
            ncurses.KEY_RIGHT,
            => download_popup.state.is_download_choose = !download_popup.state.is_download_choose,
            '\n' => if (download_popup.state.is_download_choose) {
                const target_info = try download_popup.getTargetInfo(zig_info, target_name);
                download_popup.state.is_download_selected = true;

                // TODO: Check shasum with the downloaded file in the memory.
                // TODO: Implement a name maker for the tarball.
                try download.downloadContentIntoFile(
                    allocator,
                    &download_popup,
                    target_info.tarball_url,
                    target_info.content_size,
                    "./test.tar.xz",
                    time.ns_per_ms * 50,
                );

                if (download_popup.state.download_finished) {
                    break;
                }
            } else break,
            else => {},
        }
        time.sleep(time.ns_per_ms * 20);

        download_popup.preDownloadDecorate();
    }
}
