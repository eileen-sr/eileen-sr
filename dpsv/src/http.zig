const request_timeout: Io.Timeout = .{ .duration = .{
    .raw = .fromSeconds(5),
    .clock = .awake,
} };

pub const ReadCompletion = struct {
    connection: *Connection,
    result: Connection.ReadRequestLineError!RequestLine,
};

pub const RequestLine = struct {
    method: Method,
    target: []const u8,

    pub const ParseError = error{
        InvalidMethod,
        MissingComponents,
    };

    pub fn parse(buffer: []const u8) ParseError!RequestLine {
        var reader: Io.Reader = .fixed(buffer);
        const method_str = reader.takeDelimiter(' ') catch null orelse return error.MissingComponents;
        const method = std.meta.stringToEnum(Method, method_str) orelse return error.InvalidMethod;
        const target = reader.takeDelimiter(' ') catch null orelse return error.MissingComponents;

        return .{ .method = method, .target = target };
    }
};

pub const Response = struct {
    writer: *Io.Writer,

    const json_options: json.Stringify.Options = .{
        .emit_null_optional_fields = false,
    };

    pub const Status = enum(u16) {
        OK = 200,
        @"Not Found" = 404,
        @"Internal Server Error" = 500,
    };

    pub const ContentType = union(enum) {
        @"text/plain": void,
        @"application/json": type,

        pub fn Type(ct: ContentType) type {
            return switch (ct) {
                .@"text/plain" => []const u8,
                .@"application/json" => |T| T,
            };
        }
    };

    pub fn init(writer: *Io.Writer) Response {
        return .{ .writer = writer };
    }

    pub fn respond(
        rsp: *Response,
        status: Status,
        comptime ct: ContentType,
        content: ct.Type(),
    ) Io.Writer.Error!void {
        try rsp.writer.print("HTTP/1.1 {0d} {0t}\r\n", .{status});
        try rsp.writer.print("Content-Type: {t}\r\n", .{ct});
        try rsp.writer.print("Content-Length: {d}\r\n\r\n", .{contentLength(ct, content)});

        switch (ct) {
            .@"text/plain" => try rsp.writer.writeAll(content),
            .@"application/json" => try rsp.writer.print("{f}", .{json.fmt(content, json_options)}),
        }

        try rsp.writer.flush();
    }

    fn contentLength(comptime ct: ContentType, content: ct.Type()) u64 {
        return switch (ct) {
            .@"text/plain" => content.len,
            .@"application/json" => {
                var buf: [128]u8 = undefined;
                var discarding: Io.Writer.Discarding = .init(&buf);
                discarding.writer.print("{f}", .{json.fmt(content, json_options)}) catch unreachable;

                return discarding.fullCount();
            },
        };
    }
};

pub const Connection = struct {
    recv_buffer: [1024]u8,
    stream: net.Stream,

    const ReadRequestLineError = error{
        EndOfStream,
        StreamTooLong,
    } || net.Stream.Reader.Error || Io.ConcurrentError || RequestLine.ParseError;

    pub fn initPinned(conn: *Connection, stream: net.Stream) void {
        conn.stream = stream;
    }

    pub fn readRequestLine(conn: *Connection, io: Io) ReadCompletion {
        return .{
            .result = concurrentTimeout(io, request_timeout, readRequestLineInner, .{ conn, io }),
            .connection = conn,
        };
    }

    fn readRequestLineInner(conn: *Connection, io: Io) ReadRequestLineError!RequestLine {
        var reader = conn.stream.reader(io, &conn.recv_buffer);
        const line = reader.interface.takeDelimiterInclusive('\r') catch |err| return switch (err) {
            error.EndOfStream, error.StreamTooLong => |e| e,
            error.ReadFailed => reader.err.?,
        };

        return .parse(line);
    }
};

const Io = std.Io;
pub const Method = std.http.Method;

const net = std.Io.net;
const json = std.json;
const concurrentTimeout = common.io.concurrentTimeout;

const common = @import("common");
const std = @import("std");
