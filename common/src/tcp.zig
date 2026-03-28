pub const ReadError = net.Stream.Reader.Error || Io.Timeout.Error || error{EndOfStream};

pub fn readTimeout(
    comptime isReady: fn ([]const u8) bool,
    io: Io,
    timeout: Io.Timeout,
    stream: Io.net.Stream,
    buffer: []u8,
    buffer_end: usize,
) ReadError!usize {
    const deadline = timeout.toDeadline(io);

    var reader = stream.reader(io, buffer);
    reader.interface.end = buffer_end;

    while (true) {
        concurrentTimeout(io, deadline, Io.Reader.fillMore, .{&reader.interface}) catch |err| switch (err) {
            error.Canceled, error.Timeout, error.EndOfStream => |e| return e,
            error.ReadFailed => return reader.err.?,
            error.ConcurrencyUnavailable => {
                if (deadline.deadline.compare(.gte, .now(io, deadline.deadline.clock)))
                    return error.Timeout;

                reader.interface.fillMore() catch |fill_err| return switch (fill_err) {
                    error.EndOfStream => |e| e,
                    error.ReadFailed => reader.err.?,
                };
            },
        };

        if (isReady(reader.interface.buffered()))
            return reader.interface.end - buffer_end;
    }
}

const net = Io.net;
const Io = std.Io;

const native_os = @import("builtin").os.tag;
const concurrentTimeout = @import("io.zig").concurrentTimeout;

const std = @import("std");
