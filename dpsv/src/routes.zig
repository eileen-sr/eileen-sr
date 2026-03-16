const log = std.log.scoped(.routes);

pub const Completion = struct {
    connection: *http.Connection,
    result: HandleRequestError!void,
};

pub const HandleRequestError = Io.Cancelable || Io.net.Stream.Writer.Error;

pub const RouteError = Io.Cancelable || Io.Writer.Error;

const routes: []const struct { [:0]const u8, type } = &.{
    .{ "/query_dispatch", @import("routes/query_dispatch.zig") },
    .{ "/query_gateway", @import("routes/query_gateway.zig") },
};

const Route = blk: {
    var field_names: [routes.len][:0]const u8 = undefined;
    var tag_values: [routes.len]u8 = @splat(0);

    for (routes, 0..) |route, i| {
        const path, _ = route;
        field_names[i] = path;
        tag_values[i] = i;
    }

    break :blk @Enum(u8, .exhaustive, &field_names, &tag_values);
};

pub fn handleRequest(
    gpa: Allocator,
    io: Io,
    conn: *http.Connection,
    request: http.RequestLine,
) Completion {
    var send_buffer: [1024]u8 = undefined;
    var writer = conn.stream.writer(io, &send_buffer);
    var response: http.Response = .init(&writer.interface);

    var split_iterator = std.mem.splitScalar(u8, request.target, '?');
    const path = split_iterator.next().?;
    const query = split_iterator.next() orelse "";
    _ = query;

    const route = std.meta.stringToEnum(Route, path) orelse {
        log.warn("unhandled: {s}", .{path});

        return .{
            .connection = conn,
            .result = response.respond(.@"Not Found", .@"text/plain", "Not Found") catch |err| switch (err) {
                error.WriteFailed => writer.err.?,
            },
        };
    };

    switch (route) {
        inline else => |r| inline for (routes) |pair| {
            const route_path, const Handler = pair;
            if (comptime !std.mem.eql(u8, route_path, @tagName(r))) continue;

            return .{
                .connection = conn,
                .result = Handler.handle(io, gpa, &request, &response) catch |err| switch (err) {
                    error.Canceled => |e| e,
                    error.WriteFailed => writer.err.?,
                },
            };
        } else comptime unreachable,
    }
}

const Allocator = std.mem.Allocator;
const Io = std.Io;

const http = @import("http.zig");
const std = @import("std");
