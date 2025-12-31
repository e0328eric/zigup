const std = @import("std");
const builtin = @import("builtin");

const http = std.http;

const assert = std.debug.assert;
const max_window_len = std.compress.flate.max_window_len;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Io = std.Io;
const JsonValue = std.json.Value;
const Badepo = @import("badepo").Badepo;

pub const Extension = enum(u1) {
    tarball,
    zip,
};

pub fn downloadContentIntoMemory(
    allocator: Allocator,
    io: Io,
    url: []const u8,
) !struct { body: ArrayList(u8), mime: ArrayList(u8) } {
    var client = http.Client{ .allocator = allocator, .io = io };
    defer client.deinit();

    const uri = try std.Uri.parse(url);
    var req = try client.request(.GET, uri, .{});
    defer req.deinit();

    try req.sendBodiless();
    var response = try req.receiveHead(&.{});

    // Pointers in response.head are invalidated when the response body stream is initialized.
    var content_type = try std.Io.Writer.Allocating.initCapacity(allocator, 10);
    errdefer content_type.deinit();
    const content_type_raw = response.head.content_type orelse "text/plain";
    try content_type.writer.writeAll(content_type_raw);

    var request_buf: [100]u8 = undefined;
    var decompress_buf: [max_window_len]u8 = undefined;
    var decompress: http.Decompress = undefined;
    const reader = response.readerDecompressing(
        &request_buf,
        &decompress,
        &decompress_buf,
    );

    var body = try std.Io.Writer.Allocating.initCapacity(allocator, 100);
    errdefer body.deinit();

    while (true) {
        _ = reader.stream(&body.writer, .unlimited) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
    }

    return .{ .body = body.toArrayList(), .mime = content_type.toArrayList() };
}

pub fn downloadTarball(
    allocator: Allocator,
    io: Io,
    comptime print_progressbar: bool,
    url: []const u8,
    content_size: u64,
    filename_prefix: []const u8,
) !struct { []const u8, Extension } {
    var client = http.Client{ .allocator = allocator, .io = io };
    defer client.deinit();

    const server_header_buffer = try allocator.alloc(u8, 2048);
    defer allocator.free(server_header_buffer);
    const uri = try std.Uri.parse(url);
    var req = try client.request(.GET, uri, .{});
    defer req.deinit();

    try req.sendBodiless();
    var response = try req.receiveHead(&.{});

    //var request_buf: [100]u8 = undefined;
    //const reader = response.reader(&request_buf);
    var request_buf: [100]u8 = undefined;
    var decompress_buf: [max_window_len]u8 = undefined;
    var decompress: http.Decompress = undefined;
    const reader = response.readerDecompressing(
        &request_buf,
        &decompress,
        &decompress_buf,
    );

    const extension, const ext_enum: Extension = extension: {
        const location = std.mem.lastIndexOfScalar(u8, url, '/').?;
        const tmp = std.fs.path.extension(url[location..]);
        // We know that if tmp == ".xz", the extension of which is ".tar.xz"
        break :extension if (std.mem.eql(u8, tmp, ".xz"))
            .{ ".tar.xz", .tarball }
        else
            .{ tmp, .zip };
    };

    const filename = try std.fmt.allocPrint(
        allocator,
        "{s}{s}",
        .{ filename_prefix, extension },
    );
    errdefer allocator.free(filename);

    var file_buf: [4096]u8 = undefined;
    var file = try Io.Dir.cwd().createFile(io, filename, .{});
    defer file.close(io);
    var file_buf_writer = file.writer(io, &file_buf);
    const writer = &file_buf_writer.interface;

    var bytes_read_total: usize = 0;
    var progress_bar = try Badepo.init(allocator, io);
    defer progress_bar.deinit();

    while (true) {
        const bytes_read = reader.stream(writer, .unlimited) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (print_progressbar) {
            try progress_bar.print(bytes_read_total, content_size);
        }
        bytes_read_total += bytes_read;
    }
    try writer.flush();

    return .{ filename, ext_enum };
}
