const builtin = @import("builtin");

pub const Progressbar = switch (builtin.os.tag) {
    .windows => @import("./Progressbar/windows.zig"),
    .linux, .macos => @import("./Progressbar/posix.zig"),
    else => @compileError("This OS is not supported"),
};
