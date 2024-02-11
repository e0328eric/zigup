# zigup
ncurses and simple cli powered simple zig compiler downloader

## How to download?
Now, run this command to install zigup.
```console
$ zig build --prefix-exe-dir ~/.local/bin -Doptimize=ReleaseSafe
```

In default, if the operating system is either macos or linux, then it uses a
`ncurses` library.
On the other hand, Windows does not use it. Instead, it runs with simple cli.

However, there is a switch to decide whether it uses `nucrses`. If you want not
to use `ncurses` in POSIX, then run like this:
```console
$ zig build -Dncurses=false --prefix-exe-dir ~/.local/bin -Doptimize=ReleaseSafe
```
