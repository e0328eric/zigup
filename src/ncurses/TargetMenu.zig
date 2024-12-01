const std = @import("std");
const window = @import("./window.zig");
const ncurses = @import("./ncurses.zig");

const mem = std.mem;
const time = std.time;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Cursor = @import("./cursor.zig");
const JsonValue = std.json.Value;

win: ?*ncurses.WINDOW,
allocator: Allocator,
title: [:0]const u8,
zig_version: [:0]const u8,
target_name: ?[]const u8,

const Self = @This();

pub fn init(
    allocator: Allocator,
    height: usize,
    width: usize,
    x: usize,
    y: usize,
    title: []const u8,
    zig_version: []const u8,
) !Self {
    const title_z = try allocator.dupeZ(u8, title);
    errdefer allocator.free(title);
    const version_z = try allocator.dupeZ(u8, zig_version);
    errdefer allocator.free(version_z);

    return Self{
        .win = window.createWindow(height, width, x, y),
        .allocator = allocator,
        .title = title_z,
        .zig_version = version_z,
        .target_name = null,
    };
}

pub fn deinit(self: Self) void {
    window.destroyWindow(self.win);
    self.allocator.free(self.title);
    self.allocator.free(self.zig_version);
}

pub fn refresh(self: *const Self) void {
    _ = ncurses.wrefresh(self.win);
}

pub inline fn resize(self: Self, height: usize, width: usize) void {
    window.resizeWindow(self.win, height, width);
}

pub fn getBegYX(self: *const Self) Cursor {
    return .{
        .row = @intCast(ncurses.getbegy(self.win)),
        .col = @intCast(ncurses.getbegx(self.win)),
    };
}

pub fn decorate(
    self: *Self,
    zig_info: *const JsonValue,
    cursor: Cursor,
    max_keydown_row: *usize,
    min_keydown_row: *usize,
) !void {
    _ = ncurses.box(self.win, 0, 0);
    _ = ncurses.mvwprintw(
        self.win,
        0,
        @divTrunc(ncurses.getmaxx(self.win) -| @as(c_int, @intCast(self.title.len)), 2),
        self.title,
    );
    _ = ncurses.mvwprintw(self.win, 1, 1, "Version: ");
    _ = ncurses.mvwprintw(self.win, 1, @intCast(1 + "Version: ".len), @ptrCast(self.zig_version));

    var iter = zig_info.object.iterator();
    var i: c_int = 3;
    const win_beg_y = ncurses.getbegy(self.win);
    min_keydown_row.* = @intCast(win_beg_y + 3);
    event_loop: while (iter.next()) |entry| {
        for ([_][]const u8{ "version", "date", "docs", "stdDocs", "src", "notes" }) |str| {
            if (mem.eql(u8, str, entry.key_ptr.*)) {
                continue :event_loop;
            }
        }

        const target_name_null = try self.allocator.dupeZ(u8, entry.key_ptr.*);
        defer self.allocator.free(target_name_null);

        if (cursor.row == i + win_beg_y) {
            self.target_name = entry.key_ptr.*;
            _ = ncurses.wattron(self.win, ncurses.COLOR_PAIR(2));
            _ = ncurses.mvwprintw(self.win, i, 1, @ptrCast(target_name_null));
            _ = ncurses.wattroff(self.win, ncurses.COLOR_PAIR(2));
        } else {
            _ = ncurses.mvwprintw(self.win, i, 1, @ptrCast(target_name_null));
        }

        i += 1;
    }
    max_keydown_row.* = @intCast(win_beg_y + @min(i, ncurses.getmaxy(self.win)) -| 1);

    _ = ncurses.wrefresh(self.win);
}

pub fn getTargetName(self: Self) ?[]const u8 {
    return self.target_name;
}
