pub const ReadError = net.Socket.ReceiveError || Io.Timeout.Error || error{EndOfStream};

pub fn readTimeout(
    comptime isReady: fn ([]const u8) bool,
    io: Io,
    timeout: Io.Timeout,
    stream: Io.net.Stream,
    buffer: []u8,
    buffer_end: usize,
) ReadError!usize {
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

const net = Io.net;
const Io = std.Io;
const std = @import("std");
