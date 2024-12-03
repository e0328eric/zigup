const std = @import("std");
const builtin = @import("builtin");

const fs = std.fs;
const http = std.http;
const io = std.io;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const JsonValue = std.json.Value;
const Badepo = @import("badepo").Badepo;

pub fn downloadContentIntoMemory(
    allocator: Allocator,
    url: []const u8,
    comptime sleep_nanosecs: u64,
) !struct { body: ArrayList(u8), mime: ArrayList(u8) } {
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const server_header_buffer = try allocator.alloc(u8, 2048);
    defer allocator.free(server_header_buffer);
    const uri = try std.Uri.parse(url);
    var req = try client.open(.GET, uri, .{ .server_header_buffer = server_header_buffer });
    defer req.deinit();

    try req.send();
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
        _ = try body_writer.write(buf[0..bytes_read]);
        if (sleep_nanosecs > 0) {
            std.time.sleep(sleep_nanosecs);
        }
    }
    try body_writer.flush();

    const content_type = mime: {
        var output = ArrayList(u8).init(allocator);
        errdefer output.deinit();
        const tmp = req.response.content_type orelse "text/plain";
        try output.appendSlice(tmp);
        break :mime output;
    };
    return .{ .body = body, .mime = content_type };
}

pub fn downloadTarball(
    allocator: Allocator,
    comptime print_progressbar: bool,
    url: []const u8,
    content_size: u64,
    filename_prefix: []const u8,
) !void {
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const server_header_buffer = try allocator.alloc(u8, 2048);
    defer allocator.free(server_header_buffer);
    const uri = try std.Uri.parse(url);
    var req = try client.open(.GET, uri, .{ .server_header_buffer = server_header_buffer });
    defer req.deinit();

    try req.send();
    try req.wait();

    var buf = [_]u8{0} ** 4096;

    const extension = extension: {
        const location = std.mem.lastIndexOfScalar(u8, url, '/').?;
        const tmp = std.fs.path.extension(url[location..]);
        // We know that if tmp == ".xz", the extension of which is ".tar.xz"
        break :extension if (std.mem.eql(u8, tmp, ".xz")) ".tar.xz" else tmp;
    };

    const filename = try std.fmt.allocPrint(
        allocator,
        "{s}{s}",
        .{ filename_prefix, extension },
    );
    defer allocator.free(filename);

    var file = try fs.cwd().createFile(filename, .{});
    defer file.close();
    var file_buf_writer = io.bufferedWriter(file.writer());

    var bytes_read_total: usize = 0;
    var progress_bar = try Badepo.init(allocator);
    defer progress_bar.deinit();

    while (true) {
        const bytes_read = try req.read(&buf);
        bytes_read_total += bytes_read;
        if (bytes_read == 0) break;
        if (print_progressbar) {
            try progress_bar.print(bytes_read_total, content_size, null, .{});
        }
        _ = try file_buf_writer.write(buf[0..bytes_read]);
    }
    try file_buf_writer.flush();
}
