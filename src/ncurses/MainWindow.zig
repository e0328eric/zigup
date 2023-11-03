const std = @import("std");
const window = @import("./window.zig");
const ncurses = @import("./ncurses.zig");

const Allocator = std.mem.Allocator;
const Cursor = @import("./cursor.zig");
const JsonValue = std.json.Value;

win: ?*ncurses.WINDOW,
allocator: Allocator,
title: [:0]const u8,

const Self = @This();

pub fn init(
    allocator: Allocator,
    height: usize,
    width: usize,
    x: usize,
    y: usize,
    title: []const u8,
) !Self {
    return Self{
        .win = window.createWindow(height, width, x, y),
        .allocator = allocator,
        .title = try allocator.dupeZ(u8, title),
    };
}

pub fn deinit(self: Self) void {
    window.destroyWindow(self.win);
    self.allocator.free(self.title);
}

pub fn refresh(self: *const Self) void {
    _ = ncurses.wrefresh(self.win);
}

pub fn decorate(self: Self, json: *const JsonValue, cursor: Cursor, max_keydown_row: *usize) !void {
    var acs_hline = ncurses.NCURSES_ACS('q');

    _ = ncurses.wattron(self.win, ncurses.COLOR_PAIR(1));
    _ = ncurses.box(self.win, 0, 0);
    _ = ncurses.mvwprintw(
        self.win,
        0,
        @divTrunc(ncurses.COLS -| @as(c_int, @intCast(self.title.len)), 2),
        self.title,
    );

    _ = ncurses.mvwprintw(self.win, 1, 4, "Version");
    _ = ncurses.mvwhline(self.win, 2, 1, acs_hline, ncurses.COLS -| 3);

    for (json.object.keys(), 3..) |keys, i| {
        const keys_null = try self.allocator.dupeZ(u8, keys);
        defer self.allocator.free(keys_null);
        if (cursor.row == i) {
            _ = ncurses.wattron(self.win, ncurses.COLOR_PAIR(2));
            _ = ncurses.mvwprintw(self.win, @intCast(i), 4, @ptrCast(keys_null));
            _ = ncurses.wattroff(self.win, ncurses.COLOR_PAIR(2));
        } else {
            _ = ncurses.mvwprintw(self.win, @intCast(i), 4, @ptrCast(keys_null));
        }
    }
    max_keydown_row.* = @min(json.object.keys().len + 2, @as(usize, @intCast(ncurses.LINES - 3)));

    _ = ncurses.wmove(self.win, @intCast(cursor.row), @intCast(cursor.col));

    _ = ncurses.wrefresh(self.win);
    _ = ncurses.wattroff(self.win, ncurses.COLOR_PAIR(1));
}
