const std = @import("std");
const download = @import("./download.zig");

const fmt = std.fmt;
const json = std.json;
const mem = std.mem;
const process = std.process;
const time = std.time;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Io = std.Io;
const JsonValue = std.json.Value;

const getInput = @import("./input_handler.zig").getInput;

const COMPILER_JSON_LINK = @import("./constants.zig").COMPILER_JSON_LINK;
const USAGE_INFO = @import("./constants.zig").USAGE_INFO;
const DEFAULT_FILENAME = @import("./constants.zig").DEFAULT_FILENAME;

pub fn main(init: process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    var args = try init.minimal.args.iterateAllocator(allocator);
    defer args.deinit();

    // skip first argument
    _ = args.skip();

    const output_filename: [:0]const u8 = if (args.next()) |filename|
        filename
    else
        DEFAULT_FILENAME;

    // Take a JSON faile from Web
    var json_bytes = try download.downloadContentIntoMemory(
        allocator,
        io,
        COMPILER_JSON_LINK,
    );
    defer {
        json_bytes.body.deinit(allocator);
        json_bytes.mime.deinit(allocator);
    }

    if (!mem.eql(u8, json_bytes.mime.items, "application/json")) {
        return error.NotAJSON;
    }

    const json_contents = try json.parseFromSlice(
        json.Value,
        allocator,
        json_bytes.body.items,
        .{},
    );
    defer json_contents.deinit();

    var stdin_buf: [2048]u8 = undefined;
    var stdout_buf: [2048]u8 = undefined;
    var stdin_reader = Io.File.stdin().reader(io, &stdin_buf);
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buf);
    const stdin = &stdin_reader.interface;
    const stdout = &stdout_writer.interface;

    const idx = try showZigVersions(
        io,
        &json_contents.value,
        stdin,
        stdout,
    );
    try stdout.writeByte('\n');
    try stdout.flush();

    const version_target_info = try showZigTargets(
        allocator,
        io,
        &json_contents.value,
        idx,
        stdin,
        stdout,
    );
    defer allocator.free(version_target_info.target_name);

    try stdout.writeByte('\n');
    try stdout.flush();

    try downloadContent(
        allocator,
        io,
        &version_target_info,
        output_filename,
        stdout,
    );
}

fn showZigVersions(
    io: Io,
    json_value: *const JsonValue,
    stdin: *Io.Reader,
    stdout: *Io.Writer,
) !usize {
    const tty_mod = try Io.Terminal.Mode.detect(io, Io.File.stdout(), false, true);
    const tty_term = Io.Terminal{ .writer = stdout, .mode = tty_mod };

    try tty_term.setColor(.yellow);
    try stdout.writeAll("[Select Version]\n");
    try tty_term.setColor(.reset);

    const total_amount_version = json_value.object.keys().len;
    for (json_value.object.keys(), 0..) |keys, i| {
        // TODO: Align version strings
        try stdout.print("[{}]: {s}\n", .{ i, keys });
    }
    try stdout.flush();

    return getInput(
        usize,
        io,
        "Enter the number to select version: ",
        total_amount_version,
        stdin,
        stdout,
    );
}

const VersionTargetInfo = struct {
    zig_info: *const JsonValue,
    zig_version: []const u8,
    target_name: []const u8,
};

// NOTE: The return string is allocated, so it should be freed
fn showZigTargets(
    allocator: Allocator,
    io: Io,
    json_value: *const JsonValue,
    idx: usize,
    stdin: *Io.Reader,
    stdout: *Io.Writer,
) !VersionTargetInfo {
    const raw_zig_version = json_value.object.keys()[idx];
    const zig_info = json_value.object.getPtr(raw_zig_version) orelse
        return error.InvalidJSON;
    const zig_version = zig_version: {
        if (mem.eql(u8, raw_zig_version, "master")) {
            break :zig_version (zig_info.object.get("version") orelse return error.InvalidJSON).string;
        } else {
            break :zig_version raw_zig_version;
        }
    };

    const tty_mod = try Io.Terminal.Mode.detect(io, Io.File.stdout(), false, true);
    const tty_term = Io.Terminal{ .writer = stdout, .mode = tty_mod };

    try tty_term.setColor(.yellow);
    try stdout.print("[Version: {s}] [Targets]\n", .{zig_version});
    try tty_term.setColor(.reset);

    var iter = zig_info.object.iterator();
    var target_names = try ArrayList([]const u8).initCapacity(allocator, 25);
    defer target_names.deinit(allocator);

    fill_container: while (iter.next()) |entry| {
        for ([_][]const u8{
            "version",
            "date",
            "docs",
            "stdDocs",
            "src",
            "notes",
        }) |str| {
            if (mem.eql(u8, str, entry.key_ptr.*)) {
                continue :fill_container;
            }
        }

        try target_names.append(allocator, entry.key_ptr.*);
    }

    for (target_names.items, 0..) |target_name, i| {
        // TODO: Align target strings
        try stdout.print("[{}]: {s}\n", .{ i, target_name });
    }
    try stdout.flush();

    const target_name_idx = try getInput(
        usize,
        io,
        "Enter the number to select target: ",
        target_names.items.len,
        stdin,
        stdout,
    );
    const target_name = target_names.items[target_name_idx];

    const output = try allocator.alloc(u8, target_name.len);
    errdefer allocator.free(output);

    @memcpy(output, target_name);

    return .{
        .zig_info = zig_info,
        .zig_version = zig_version,
        .target_name = output,
    };
}

fn downloadContent(
    allocator: Allocator,
    io: Io,
    version_target_info: *const VersionTargetInfo,
    output_filename: []const u8,
    stdout: *Io.Writer,
) !void {
    const tty_mod = try Io.Terminal.Mode.detect(io, Io.File.stdout(), false, true);
    const tty_term = Io.Terminal{ .writer = stdout, .mode = tty_mod };

    try tty_term.setColor(.yellow);
    try stdout.print("[Downloading Content] [Version: {s}, Target: {s}]\n", .{
        version_target_info.zig_version,
        version_target_info.target_name,
    });
    try tty_term.setColor(.reset);
    try stdout.flush();

    // Download zig compiler
    // TODO: Check shasum with the downloaded file in the memory.
    // TODO: Implement a name maker for the tarball.
    const target_info = try getTargetInfo(
        version_target_info.zig_info,
        version_target_info.target_name,
    );
    const downloaded_filename, const ext = try download.downloadTarball(
        allocator,
        io,
        true,
        target_info.tarball_url,
        target_info.content_size,
        output_filename,
    );
    defer allocator.free(downloaded_filename);
    try stdout.writeByte('\n');

    try tty_term.setColor(.yellow);
    try stdout.print("[Decompressing archive]\n", .{});
    try tty_term.setColor(.reset);
    try stdout.flush();

    Io.Dir.cwd().createDir(io, output_filename, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    switch (ext) {
        .tarball => {
            // TODO: make a progressbar for decompressing
            var output_dir = try Io.Dir.cwd().openDir(io, output_filename, .{});
            defer output_dir.close(io);

            var tar_buf: [std.compress.flate.max_window_len]u8 = undefined;
            var tar_file = try Io.Dir.cwd().openFile(io, downloaded_filename, .{});
            defer tar_file.close(io);
            var tar_file_reader = tar_file.reader(io, &tar_buf);

            const decompress_buf = try allocator.alloc(u8, std.compress.flate.max_window_len);
            errdefer allocator.free(decompress_buf);
            var decompressor = try std.compress.xz.Decompress.init(
                &tar_file_reader.interface,
                allocator,
                decompress_buf,
            );
            defer decompressor.deinit();

            try std.tar.pipeToFileSystem(
                io,
                output_dir,
                &decompressor.reader,
                .{},
            );
            try Io.Dir.cwd().deleteFile(io, downloaded_filename);
        },
        .zip => {
            // TODO: make a progressbar for decompressing
            var output_dir = try Io.Dir.cwd().openDir(io, output_filename, .{});
            defer output_dir.close(io);

            var zip_buf: [std.compress.flate.max_window_len]u8 = undefined;
            var zip_file = try Io.Dir.cwd().openFile(io, downloaded_filename, .{});
            defer zip_file.close(io);
            var zip_file_reader = zip_file.reader(io, &zip_buf);

            var diag: std.zip.Diagnostics = .{ .allocator = allocator };
            defer diag.deinit();
            try std.zip.extract(
                output_dir,
                &zip_file_reader,
                .{ .diagnostics = &diag },
            );
            try Io.Dir.cwd().deleteFile(io, downloaded_filename);
        },
    }

    try tty_term.setColor(.yellow);
    try stdout.print("[Download Finished]\n", .{});
    try tty_term.setColor(.reset);
    try stdout.flush();
}

const TargetInfo = struct {
    tarball_url: []const u8,
    shasum: []const u8,
    content_size: u64,
};

fn getTargetInfo(zig_info: *const JsonValue, target_name: []const u8) !TargetInfo {
    var output: TargetInfo = undefined;
    const target_info = zig_info.object.get(target_name) orelse return error.CannotGetTargetInfo;
    output.tarball_url = target_url: {
        const tmp = target_info.object.get("tarball") orelse return error.CannotGetTarballUrl;
        break :target_url tmp.string;
    };
    output.shasum = target_shasum: {
        const tmp = target_info.object.get("shasum") orelse return error.CannotGetTarballUrl;
        break :target_shasum tmp.string;
    };
    output.content_size = content_size: {
        const tmp = target_info.object.get("size") orelse return error.CannotGetTarballUrl;
        break :content_size try fmt.parseInt(u64, tmp.string, 10);
    };

    return output;
}
