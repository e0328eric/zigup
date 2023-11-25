const std = @import("std");
const ncurses = @import("./ncurses.zig");

pub fn createWindow(
    height: usize,
    width: usize,
    x: usize,
    y: usize,
) ?*ncurses.WINDOW {
    const win = ncurses.newwin(@intCast(height), @intCast(width), @intCast(x), @intCast(y));
    _ = ncurses.refresh();

    return win;
}

pub fn destroyWindow(win: ?*ncurses.WINDOW) void {
    _ = ncurses.delwin(win);
}
