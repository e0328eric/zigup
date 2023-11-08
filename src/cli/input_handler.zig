const std = @import("std");

const fmt = std.fmt;
const io = std.io;
const tty = std.io.tty;

const Stdin = @TypeOf(io.getStdIn().reader());
const Stdout = @TypeOf(io.getStdOut().writer());

pub fn getInput(
    comptime T: type,
    msg: []const u8,
    choose_max_val: T,
    stdin: *const Stdin,
    stdout: *const Stdout,
) !T {
    var buf = [_]u8{0} ** 25;

    const tty_config = tty.detectConfig(io.getStdOut());

    try tty_config.setColor(stdout, .yellow);
    try stdout.writeAll(msg);
    try tty_config.setColor(stdout, .reset);

    while (true) {
        const bytes_read = try stdin.read(&buf);

        const tmp: struct { usize, bool } = blk: {
            break :blk .{ fmt.parseInt(T, buf[0..bytes_read -| 2], 10) catch
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
            continue;
        }

        return tmp[0];
    }
}
