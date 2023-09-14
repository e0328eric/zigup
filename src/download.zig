const std = @import("std");

const fs = std.fs;
const http = std.http;
const io = std.io;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const DownloadPopup = @import("./DownloadPopup.zig");
const JsonValue = std.json.Value;

pub fn downloadContentIntoMemory(
    allocator: Allocator,
    download_popup: ?*DownloadPopup,
    url: []const u8,
    content_size: ?u64,
    comptime sleep_nanosecs: u64,
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

    var bytes_read_total: usize = 0;
    var body_writer = io.bufferedWriter(body.writer());
    while (true) {
        const bytes_read = try req.reader().read(&buf);
        bytes_read_total += bytes_read;
        if (bytes_read == 0) break;
        if (download_popup) |dp| {
            try dp.downloadDecorate(@intCast(bytes_read_total), content_size.?);
        }
        _ = try body_writer.write(buf[0..bytes_read]);
        if (sleep_nanosecs > 0) {
            std.time.sleep(sleep_nanosecs);
        }
    }
    try body_writer.flush();

    if (download_popup) |dp| {
        dp.state.download_finished = true;
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
    download_popup: ?*DownloadPopup,
    url: []const u8,
    content_size: ?u64,
    filepath: []const u8,
    comptime sleep_nanosecs: u64,
) !void {
    var file = try fs.cwd().createFile(filepath, .{});
    defer file.close();
    var file_buf_writer = io.bufferedWriter(file.writer());

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

    var buf = try allocator.alloc(u8, 2000000);
    defer allocator.free(buf);
    @memset(buf, 0);

    var bytes_read_total: usize = 0;
    while (true) {
        const bytes_read = try req.reader().read(buf);
        bytes_read_total += bytes_read;
        if (bytes_read == 0) break;
        if (download_popup) |dp| {
            try dp.downloadDecorate(@intCast(bytes_read_total), content_size.?);
        }
        _ = try file_buf_writer.write(buf[0..bytes_read]);
        if (sleep_nanosecs > 0) {
            std.time.sleep(sleep_nanosecs);
        }
    }
    try file_buf_writer.flush();

    if (download_popup) |dp| {
        dp.state.download_finished = true;
    }
}
