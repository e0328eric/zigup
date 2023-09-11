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
zig_version: [:0]const u8,

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
    };
}

pub fn deinit(self: Self) void {
    window.destroyWindow(self.win);
    self.allocator.free(self.title);
    self.allocator.free(self.zig_version);
}

pub fn decorate(
    self: Self,
    zig_info: *const JsonValue,
    cursor: Cursor,
) !void {
    _ = cursor;

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
    event_loop: while (iter.next()) |entry| {
        for ([_][]const u8{ "version", "date", "docs", "stdDocs", "src", "notes" }) |str| {
            if (mem.eql(u8, str, entry.key_ptr.*)) {
                continue :event_loop;
            }
        }

        const target_info = &entry.value_ptr.object;
        const tarball_null = try self.allocator.dupeZ(u8, target_info.get("tarball").?.string);
        defer self.allocator.free(tarball_null);

        _ = ncurses.mvwprintw(self.win, i, 1, @ptrCast(tarball_null));
        i += 1;
    }
    _ = ncurses.wrefresh(self.win);
}
