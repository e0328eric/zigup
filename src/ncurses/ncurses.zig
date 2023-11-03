const builtin = @import("builtin");

const ncurses = switch (builtin.os.tag) {
    .linux, .macos => @cImport({
        @cInclude("ncurses.h");
    }),
    else => @compileError("This program uses <ncurses.h> and targeting OS does not supports it."),
};
