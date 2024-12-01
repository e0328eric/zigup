const std = @import("std");
const window = @import("./window.zig");
const fmt = std.fmt;
const ncurses = @import("./ncurses.zig");

const mem = std.mem;
const time = std.time;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Cursor = @import("./cursor.zig");
const JsonValue = std.json.Value;

pub const TargetInfo = struct {
    tarball_url: []const u8,
    shasum: []const u8,
    content_size: u64,
};

pub const DownloadState = packed struct {
    is_download_choose: bool,
    is_download_selected: bool,
    download_finished: bool,
};

win: ?*ncurses.WINDOW,
allocator: Allocator,
title: [:0]const u8,
height: usize,
width: usize,
x: usize,
y: usize,
state: DownloadState,

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

    return Self{
        .win = window.createWindow(height, width, x, y),
        .allocator = allocator,
        .title = title_z,
        .height = height,
        .width = width,
        .x = x,
        .y = y,
        .state = @bitCast(@as(u3, 0)),
    };
}

pub fn deinit(self: Self) void {
    window.destroyWindow(self.win);
    self.allocator.free(self.title);
}

pub fn getTargetInfo(self: Self, zig_info: *const JsonValue, target_name: []const u8) !TargetInfo {
    _ = self;

    var output: TargetInfo = undefined;
    const target_info = zig_info.object.get(target_name) orelse return error.CannotGetTargetInfo;
    output.tarball_url = target_url: {
        const tmp = target_info.object.get("tarball") orelse return error.CannotGetTarballUrl;
        break :target_url tmp.string;
    };
    output.shasum = target_shasum: {
        const tmp = target_info.object.get("shasum") orelse return error.CannotGetTarballUrl;
        break :target_shasum tmp.string;
    };
    output.content_size = content_size: {
        const tmp = target_info.object.get("size") orelse return error.CannotGetTarballUrl;
        break :content_size try fmt.parseInt(u64, tmp.string, 10);
    };

    return output;
}

pub fn preDownloadDecorate(
    self: Self,
) void {
    _ = ncurses.box(self.win, 0, 0);
    _ = ncurses.mvwprintw(
        self.win,
        0,
        @divTrunc(ncurses.getmaxx(self.win) -| @as(c_int, @intCast(self.title.len)), 2),
        self.title,
    );

    _ = ncurses.mvwprintw(self.win, 3, 3, "Are you sure to download this version?");

    if (self.state.is_download_choose) {
        _ = ncurses.wattron(self.win, ncurses.COLOR_PAIR(2));
    }
    _ = ncurses.mvwprintw(
        self.win,
        @intCast(@divTrunc(self.height, 4) * 3),
        @intCast(@divTrunc(self.width, 4) - 4),
        "< Yes >",
    );
    if (self.state.is_download_choose) {
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
    if (!self.state.is_download_choose) {
        _ = ncurses.wattroff(self.win, ncurses.COLOR_PAIR(2));
    }

    _ = ncurses.wrefresh(self.win);
}

pub fn downloadDecorate(
    self: *Self,
    bytes_read_total: u64,
    content_size: u64,
) !void {
    window.destroyWindow(self.win);
    self.win = window.createWindow(self.height, self.width, self.x, self.y);

    _ = ncurses.box(self.win, 0, 0);
    _ = ncurses.mvwprintw(
        self.win,
        0,
        @divTrunc(ncurses.getmaxx(self.win) -| @as(c_int, @intCast(self.title.len)), 2),
        self.title,
    );
    _ = ncurses.mvwprintw(self.win, 3, 3, "Downloading...");

    const info = try fmt.allocPrintZ(self.allocator, "{} of total {}", .{
        bytes_read_total,
        content_size,
    });
    defer self.allocator.free(info);

    _ = ncurses.mvwprintw(self.win, 4, 3, info);

    const progress_bar_len = self.width -| 9;
    if (progress_bar_len > 5) {
        // zig fmt: off
        const portion = @as(usize, @intFromFloat(
            @as(f64, @floatFromInt(bytes_read_total * progress_bar_len)) / @as(f64, @floatFromInt(content_size))
        ));
        // zig fmt: on

        _ = ncurses.mvwprintw(self.win, 5, 3, "[");
        for (0..progress_bar_len) |i| {
            if (i < portion) {
                _ = ncurses.mvwprintw(self.win, 5, @intCast(i + 4), "=");
            } else {
                _ = ncurses.mvwprintw(self.win, 5, @intCast(i + 4), " ");
            }
        }
        _ = ncurses.mvwprintw(self.win, 5, @intCast(self.width -| 4), "]");
    }

    _ = ncurses.wrefresh(self.win);
}
