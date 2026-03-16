pub fn handle(
    io: Io,
    gpa: Allocator,
    request: *const http.RequestLine,
    response: *http.Response,
) routes.RouteError!void {
    _ = .{ io, gpa, request };

    const region_list: [1]ServerData = .{.{
        .dispatch_url = "http://127.0.0.1:10001/query_gateway",
        .name = "eileen_sr",
        .title = "Eileen-SR",
        .display_name = "Eileen SR",
        .env_type = "2",
    }};

    const data: GlobalDispatchData = .{
        .retcode = 0,
        .region_list = &region_list,
    };

    try response.respond(.OK, .{ .@"application/json" = GlobalDispatchData }, data);
}

const GlobalDispatchData = struct {
    retcode: i32,
    region_list: []const ServerData,
};

const ServerData = struct {
    dispatch_url: []const u8,
    name: []const u8,
    title: []const u8,
    display_name: []const u8,
    env_type: []const u8,
};

const Allocator = std.mem.Allocator;
const Io = std.Io;

const http = @import("../http.zig");
const routes = @import("../routes.zig");
const std = @import("std");
