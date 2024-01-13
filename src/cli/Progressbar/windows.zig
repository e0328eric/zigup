const std = @import("std");
const win = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", {});
    @cInclude("windows.h");
});

const log = std.log;
const io = std.io;
const log10Int = std.math.log10_int;

stdout: win.HANDLE,
length: usize,

const Self = @This();

pub fn init() !Self {
    var output: Self = undefined;

    output.stdout = win.GetStdHandle(win.STD_OUTPUT_HANDLE);
    if (output.stdout == win.INVALID_HANDLE_VALUE) {
        log.err("cannot get the stdout handle", .{});
        return error.CannotGetStdHandle;
    }

    var console_info: win.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (win.GetConsoleScreenBufferInfo(output.stdout, &console_info) != win.TRUE) {
        log.err("cannot get the console screen buffer info", .{});
        return error.CannotGetConsoleScreenBufInfo;
    }

    // The length of the progress bar is (1/2)*width
    output.length = @divTrunc(@as(usize, @intCast(console_info.dwSize.X)), 2);

    return output;
}

pub fn print(
    self: *Self,
    current: usize,
    total: usize,
) !void {
    std.debug.assert(current <= total);

    var stdout_buf = io.bufferedWriter(io.getStdOut().writer());
    const stdout = stdout_buf.writer();

    var console_info: win.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (win.GetConsoleScreenBufferInfo(self.stdout, &console_info) != win.TRUE) {
        log.err("cannot get the console screen buffer info", .{});
        return error.CannotGetConsoleScreenBufInfo;
    }
    const cursor_pos = console_info.dwCursorPosition;

    _ = win.SetConsoleCursorPosition(self.stdout, .{ .X = 0, .Y = cursor_pos.Y });

    const raw_progress_len = blk: {
        const to_discard = 2 * log10Int(total) + 6;
        break :blk self.length -| to_discard;
    };
    const percent = @divTrunc(current * raw_progress_len, total);

    try stdout.writeByte('[');
    for (0..raw_progress_len) |j| {
        if (j <= percent) {
            try stdout.writeByte('=');
        } else {
            try stdout.writeByte(' ');
        }
    }
    try stdout.print("] {}/{}", .{ current, total });
    try stdout_buf.flush();
}
