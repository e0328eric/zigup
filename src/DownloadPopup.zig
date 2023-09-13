const std = @import("std");
const builtin = @import("builtin");
const window = @import("./window.zig");

const ncurses = switch (builtin.os.tag) {
    .linux, .macos => @cImport({
        @cInclude("ncurses.h");
    }),
    else => @compileError("This program uses <ncurses.h> and targeting OS does not supports it."),
};

const mem = std.mem;
const time = std.time;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Cursor = @import("./cursor.zig");
const JsonValue = std.json.Value;

win: ?*ncurses.WINDOW,
allocator: Allocator,
title: [:0]const u8,
height: usize,
width: usize,
is_download: bool,

const Self = @This();

pub fn init(
    allocator: Allocator,
    height: usize,
    width: usize,
    x: usize,
    y: usize,
    title: []const u8,
) !Self {
    const title_z = try allocator.dupeZ(u8, title);
    errdefer allocator.free(title);

    var self = Self{
        .win = window.createWindow(height, width, x, y),
        .allocator = allocator,
        .title = title_z,
        .height = undefined,
        .width = undefined,
        .is_download = false,
    };

    self.height = @intCast(ncurses.getmaxy(self.win));
    self.width = @intCast(ncurses.getmaxx(self.win));

    return self;
}

pub fn deinit(self: Self) void {
    window.destroyWindow(self.win);
    self.allocator.free(self.title);
}

pub fn decorate(
    self: Self,
    zig_info: *const JsonValue,
    target_name: []const u8,
) !void {
    _ = target_name;
    _ = zig_info;

    _ = ncurses.box(self.win, 0, 0);
    _ = ncurses.mvwprintw(
        self.win,
        0,
        @divTrunc(ncurses.getmaxx(self.win) -| @as(c_int, @intCast(self.title.len)), 2),
        self.title,
    );

    _ = ncurses.mvwprintw(self.win, 3, 3, "Are you sure to download this version?");

    if (self.is_download) {
        _ = ncurses.wattron(self.win, ncurses.COLOR_PAIR(2));
    }
    _ = ncurses.mvwprintw(
        self.win,
        @intCast(@divTrunc(self.height, 4) * 3),
        @intCast(@divTrunc(self.width, 4) - 4),
        "< Yes >",
    );
    if (self.is_download) {
        _ = ncurses.wattroff(self.win, ncurses.COLOR_PAIR(2));
    } else {
        _ = ncurses.wattron(self.win, ncurses.COLOR_PAIR(2));
    }
    _ = ncurses.mvwprintw(
        self.win,
        @intCast(@divTrunc(self.height, 4) * 3),
        @intCast(@divTrunc(self.width, 4) * 3 - 3),
        "< No >",
    );
    if (!self.is_download) {
        _ = ncurses.wattroff(self.win, ncurses.COLOR_PAIR(2));
    }

    // var target_info = zig_info.object.get(target_name) orelse return error.CannotGetTargetInfo;
    // var iter = target_info.object.iterator();
    // var i: c_int = 3;
    // while (iter.next()) |entry| : (i += 1) {
    //     const target_name_null = try self.allocator.dupeZ(u8, entry.key_ptr.*);
    //     defer self.allocator.free(target_name_null);
    //     const foo = try self.allocator.dupeZ(u8, entry.value_ptr.*.string);
    //     defer self.allocator.free(foo);

    //     _ = ncurses.mvwprintw(self.win, i, 1, @ptrCast(target_name_null));
    //     _ = ncurses.mvwprintw(self.win, i, 10, @ptrCast(foo));
    // }

    _ = ncurses.wrefresh(self.win);
}
