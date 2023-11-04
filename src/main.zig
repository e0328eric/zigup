const use_ncurses = @import("zigup_build").use_ncurses;

pub fn main() !void {
    if (use_ncurses) {
        return @import("./ncurses/main_ncurses.zig").main_ncurses();
    } else {
        return @import("./cli/main_cli.zig").main_cli();
    }
}
