pub const DEFAULT_FOREGROUND: c_short = -1;
pub const DEFAULT_BACKGROUND: c_short = -1;

pub const MIN_HEIGHT: usize = 10;
pub const MIN_WIDTH: usize = 10;

pub const TAR_XZ_MIME: []const u8 = "application/x-xz";
pub const ZIP_MIME: []const u8 = "application/zip";
pub const OS_SPECIFIC: []const u8 = "application/octet-stream";

pub const COMPILER_JSON_LINK: []const u8 = "https://ziglang.org/download/index.json";

pub const DEFAULT_FILENAME: [:0]const u8 = "zig-compiler";

pub const USAGE_INFO: []const u8 =
    \\ Usage:
    \\     zigup <OUTPUT-FILENAME>
    \\
    \\ Note:
    \\     OUTPUT-FILENAME can not contain an extension suffix.
;
