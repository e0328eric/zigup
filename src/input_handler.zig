const std = @import("std");
const builtin = @import("builtin");

const fs = std.fs;
const fmt = std.fmt;
const Io = std.Io;
const tty = std.io.tty;

const NEWLINE_LEN = if (builtin.os.tag == .windows) 2 else 1;

pub fn getInput(
    comptime T: type,
    msg: []const u8,
    choose_max_val: T,
    stdin: *Io.Reader,
    stdout: *Io.Writer,
) !T {
    const tty_config = tty.detectConfig(fs.File.stdout());

    try tty_config.setColor(stdout, .yellow);
    try stdout.writeAll(msg);
    try tty_config.setColor(stdout, .reset);
    try stdout.flush();

    while (true) {
        const buf = try stdin.takeDelimiterInclusive('\n');
        const tmp: struct { usize, bool } = blk: {
            break :blk .{ fmt.parseInt(T, buf[0..buf.len -| NEWLINE_LEN], 10) catch
                break :blk .{ 0, false }, true };
        };
        if (!tmp[1] or tmp[0] >= choose_max_val) {
            try tty_config.setColor(stdout, .red);
            try stdout.writeAll("[ERROR]: ");
            try tty_config.setColor(stdout, .reset);
            try stdout.writeAll("Invalid input found.\n");
            try tty_config.setColor(stdout, .yellow);
            try stdout.writeAll(msg);
            try tty_config.setColor(stdout, .reset);
            try stdout.flush();
            continue;
        }

        return tmp[0];
    }
}
