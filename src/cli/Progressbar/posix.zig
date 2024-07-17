const std = @import("std");
const c = @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("unistd.h");
});

const log = std.log;
const io = std.io;
const log10Int = std.math.log10_int;

stdout: @TypeOf(io.bufferedWriter(io.getStdOut().writer())),
length: usize,

const Self = @This();

pub fn init() !Self {
    var output: Self = undefined;

    const stdout = io.getStdOut();

    var win_info: c.winsize = undefined;
    if (c.ioctl(std.posix.STDOUT_FILENO, c.TIOCGWINSZ, &win_info) < 0) {
        log.err("Cannot get the terminal size", .{});
        return error.TermSizeNotObtained;
    }

    output.stdout = io.bufferedWriter(stdout.writer());
    output.length = @as(usize, @intCast(win_info.ws_col));

    return output;
}

pub fn print(
    self: *Self,
    current: usize,
    total: usize,
) !void {
    var writer = self.stdout.writer();

    const raw_progress_len = blk: {
        const to_discard = 2 * log10Int(total) + 8;
        break :blk self.length -| to_discard;
    };
    const percent = @divTrunc(current * raw_progress_len, total);

    try writer.writeByte('[');
    for (0..raw_progress_len) |j| {
        if (j <= percent) {
            try writer.writeByte('=');
        } else {
            try writer.writeByte(' ');
        }
    }
    try writer.print("] {}/{}\r", .{ current, total });
    try self.stdout.flush();
}
