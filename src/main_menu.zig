const std = @import("std");
const builtin = @import("builtin");

const ncurses = switch (builtin.os.tag) {
    .linux, .macos => @cImport({
        @cInclude("ncurses.h");
    }),
    else => @compileError("This program uses <ncurses.h> and targeting OS does not supports it."),
};

const Allocator = std.mem.Allocator;
const Cursor = @import("./cursor.zig");
const JsonValue = std.json.Value;

pub fn createWindow(
    height: usize,
    width: usize,
    x: usize,
    y: usize,
) ?*ncurses.WINDOW {
    var win = ncurses.newwin(@intCast(height), @intCast(width), @intCast(x), @intCast(y));
    _ = ncurses.refresh();

    return win;
}

pub fn destroyWindow(win: ?*ncurses.WINDOW) void {
    _ = ncurses.delwin(win);
}

pub fn decorateMainWindow(
    win: ?*ncurses.WINDOW,
    allocator: Allocator,
    json: *const JsonValue,
    cursor: Cursor,
) !void {
    const title = "Zigup";
    var acs_hline = ncurses.NCURSES_ACS('q');

    _ = ncurses.wattron(win, ncurses.COLOR_PAIR(1));
    _ = ncurses.box(win, 0, 0);
    _ = ncurses.mvwprintw(win, 0, @divTrunc(ncurses.COLS -| @as(c_int, title.len), 2), title);

    _ = ncurses.mvwprintw(win, 1, 4, "Version");
    _ = ncurses.mvwhline(win, 2, 1, acs_hline, ncurses.COLS -| 3);

    for (json.object.keys(), 3..) |keys, i| {
        const keys_null = try allocator.dupeZ(u8, keys);
        defer allocator.free(keys_null);
        if (cursor.row == i) {
            _ = ncurses.wattron(win, ncurses.COLOR_PAIR(2));
            _ = ncurses.mvwprintw(win, @intCast(i), 4, @ptrCast(keys_null));
            _ = ncurses.wattroff(win, ncurses.COLOR_PAIR(2));
        } else {
            _ = ncurses.mvwprintw(win, @intCast(i), 4, @ptrCast(keys_null));
        }
    }

    _ = ncurses.wmove(win, @intCast(cursor.row), @intCast(cursor.col));

    _ = ncurses.wrefresh(win);
    _ = ncurses.wattroff(win, ncurses.COLOR_PAIR(1));
}
