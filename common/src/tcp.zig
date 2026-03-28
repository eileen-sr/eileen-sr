pub const ReadError = net.Socket.ReceiveError || Io.Timeout.Error || error{ EndOfStream, AccessDenied };

const net_receive_supports_tcp = native_os != .windows;

pub fn readTimeout(
    comptime isReady: fn ([]const u8) bool,
    io: Io,
    timeout: Io.Timeout,
    stream: Io.net.Stream,
    buffer: []u8,
    buffer_end: usize,
) ReadError!usize {
    if (!net_receive_supports_tcp)
        return readTimeoutDumb(isReady, io, timeout, stream, buffer, buffer_end) catch |err| switch (err) {
            // Worst case scenario.
            error.ConcurrencyUnavailable => return readRetarded(isReady, io, stream, buffer, buffer_end),
            else => |e| return e,
        };

    var n_read: usize = 0;
    const deadline = timeout.toDeadline(io);

    while (true) {
        const free = buffer[n_read + buffer_end ..];

        const message = stream.socket.receiveTimeout(io, free, deadline) catch |err| switch (err) {
            error.ConcurrencyUnavailable => try stream.socket.receive(io, free),
            else => |e| return e,
        };

        if (message.data.len == 0) return error.EndOfStream;
        n_read += message.data.len;

        if (isReady(buffer[0 .. n_read + buffer_end]))
            return n_read;
    }
}

// Until net_read is not an Io.Operation, there's no other way to
// enforce a timeout on it through the std.Io API.
fn readTimeoutDumb(
    comptime isReady: fn ([]const u8) bool,
    io: Io,
    timeout: Io.Timeout,
    stream: Io.net.Stream,
    buffer: []u8,
    buffer_end: usize,
) (ReadError || Io.ConcurrentError)!usize {
    const Awaitee = union(enum) {
        net_read: Io.Reader.Error!void,
        timeout: Io.Cancelable!void,
    };

    var reader = stream.reader(io, buffer);
    reader.interface.end = buffer_end;

    var select: Io.Select(Awaitee) = .init(io, &.{});
    defer select.cancelDiscard();

    try select.concurrent(.timeout, Io.Timeout.sleep, .{ timeout, io });
    try select.concurrent(.net_read, Io.Reader.fillMore, .{&reader.interface});

    while (true) switch (try select.await()) {
        .timeout => return error.Timeout,
        .net_read => |net_read| {
            net_read catch |err| switch (err) {
                error.EndOfStream => |e| return e,
                error.ReadFailed => return reader.err.?,
            };

            if (isReady(reader.interface.buffered()))
                return reader.interface.end - buffer_end;

            try select.concurrent(.net_read, Io.Reader.fillMore, .{&reader.interface});
        },
    };
}

// Retarded implementation: no timeout at all
fn readRetarded(
    comptime isReady: fn ([]const u8) bool,
    io: Io,
    stream: Io.net.Stream,
    buffer: []u8,
    buffer_end: usize,
) ReadError!usize {
    var reader = stream.reader(io, "");
    var n_read: usize = 0;

    while (true) {
        const r = reader.interface.readSliceShort(buffer[0 .. n_read + buffer_end]) catch return reader.err.?;
        if (r == 0) return error.EndOfStream;

        n_read += r;

        if (isReady(buffer[0 .. n_read + buffer_end]))
            return n_read;
    }
}

const net = Io.net;
const Io = std.Io;

const native_os = builtin.os.tag;

const builtin = @import("builtin");
const std = @import("std");
