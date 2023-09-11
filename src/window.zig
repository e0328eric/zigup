const std = @import("std");
const builtin = @import("builtin");

const ncurses = switch (builtin.os.tag) {
    .linux, .macos => @cImport({
        @cInclude("ncurses.h");
    }),
    else => @compileError("This program uses <ncurses.h> and targeting OS does not supports it."),
};

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
