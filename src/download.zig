const std = @import("std");

const fs = std.fs;
const http = std.http;
const io = std.io;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub fn downloadContentIntoMemory(
    allocator: Allocator,
    comptime print_meg: bool,
    comptime sleep_nanosecs: u64,
    url: []const u8,
) !struct { body: ArrayList(u8), mime: ArrayList(u8) } {
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse(url);
    var headers = http.Headers.init(allocator);
    defer headers.deinit();
    try headers.append("accept", "*/*");

    var req = try client.request(.GET, uri, headers, .{});
    defer req.deinit();

    try req.start();
    try req.wait();

    var body = try ArrayList(u8).initCapacity(allocator, comptime std.math.pow(usize, 2, 15));
    errdefer body.deinit();

    var buf = [_]u8{0} ** 4096;
    const content_length: usize = @intCast(req.response.content_length orelse 0);
    var bytes_read_total: usize = 0;
    while (true) {
        const bytes_read = try req.reader().read(&buf);
        bytes_read_total += bytes_read;
        if (bytes_read == 0) break;
        if (print_meg) {
            if (content_length > 0) {
                std.debug.print("Downloading {}/{}\n", .{ bytes_read_total, content_length });
            } else {
                std.debug.print("Downloading {} bytes total.\n", .{bytes_read_total});
            }
        }
        try body.appendSlice(buf[0..bytes_read]);
        if (sleep_nanosecs > 0) {
            std.time.sleep(sleep_nanosecs);
        }
    }

    const content_type = mime: {
        var output = ArrayList(u8).init(allocator);
        errdefer output.deinit();
        const tmp = req.response.headers.getFirstValue("Content-Type") orelse "text/plain";
        try output.appendSlice(tmp);
        break :mime output;
    };
    return .{ .body = body, .mime = content_type };
}

pub fn downloadContentIntoFile(
    allocator: Allocator,
    url: []const u8,
    filepath: []const u8,
) !void {
    const content = try downloadContentIntoMemory(allocator, url);
    defer {
        content.body.deinit();
        content.mime.deinit();
    }

    const body = content.body;

    var file = try fs.cwd().createFile(filepath, .{});
    defer file.close();

    var file_buf_writer = io.bufferedWriter(file.writer());
    try file_buf_writer.writer().writeAll(body.items);
}
