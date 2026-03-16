var initialized: bool = false;
var event_io: Io = undefined;
var event: Io.Event = .unset;

pub fn init(io: Io) Termination {
    const was_initialized = @atomicRmw(bool, &initialized, .Xchg, true, .seq_cst);
    std.debug.assert(!was_initialized);

    event_io = io;

    switch (native_os) {
        .windows => initWindows(),
        else => initPosix(),
    }

    return .{};
}

pub inline fn shutdownRequested(t: *const Termination) bool {
    _ = t;
    return event.isSet();
}

pub fn await(t: *const Termination, io: Io) Io.Cancelable!void {
    _ = t;
    try event.wait(io);
}

fn initPosix() void {
    _ = posix.system.sigaction(.INT, &.{
        .handler = .{ .handler = posixCallback },
        .mask = std.mem.zeroes(@FieldType(posix.Sigaction, "mask")),
        .flags = 0,
    }, null);
}

fn initWindows() void {
    _ = SetConsoleCtrlHandler(windowsCallback, windows.TRUE);
}

fn posixCallback(_: posix.SIG) callconv(.c) void {
    event.set(event_io);
}

fn windowsCallback(ctrl_type: windows.DWORD) callconv(.winapi) windows.BOOL {
    if (ctrl_type != CTRL_C_EVENT) return windows.FALSE;

    event.set(event_io);
    return windows.TRUE;
}

extern "kernel32" fn SetConsoleCtrlHandler(
    handler_routine: *const fn (windows.DWORD) callconv(.winapi) windows.BOOL,
    add: windows.BOOL,
) windows.BOOL;

const CTRL_C_EVENT: windows.DWORD = 0;

const Io = std.Io;

const posix = std.posix;
const windows = std.os.windows;
const native_os = builtin.os.tag;

const builtin = @import("builtin");
const std = @import("std");
const Termination = @This();
