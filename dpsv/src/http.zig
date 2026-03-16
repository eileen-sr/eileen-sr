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

    pub fn isComplete(buffer: []const u8) bool {
        return std.mem.findScalar(u8, buffer, '\r') != null;
    }

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
    stream: Io.net.Stream,

    const ReadRequestLineError = common.tcp.ReadError || RequestLine.ParseError;

    pub fn initPinned(conn: *Connection, stream: Io.net.Stream) void {
        conn.stream = stream;
    }

    pub fn readRequestLine(conn: *Connection, io: Io) ReadCompletion {
        const n_read = common.tcp.readTimeout(
            RequestLine.isComplete,
            io,
            request_timeout,
            conn.stream,
            &conn.recv_buffer,
            0,
        ) catch |err| return .{ .connection = conn, .result = err };

        return .{
            .connection = conn,
            .result = .parse(conn.recv_buffer[0..n_read]),
        };
    }
};

const Io = std.Io;
pub const Method = std.http.Method;

const json = std.json;

const common = @import("common");
const std = @import("std");
