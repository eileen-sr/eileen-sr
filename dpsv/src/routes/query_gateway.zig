pub fn handle(
    io: Io,
    gpa: Allocator,
    request: *const http.RequestLine,
    response: *http.Response,
) routes.RouteError!void {
    _ = .{ io, gpa, request };

    try response.respond(.OK, .{ .@"application/json" = ServerDispatchData }, .{
        .retcode = 0,
        .client_secret_key = "",
        .region_name = "eileen_sr",
        .gateway = .{ .ip = "127.0.0.1", .port = 23301 },
        .design_data_relogin = 0,
        .design_data_memo = "",
        .asb_relogin = 0,
        .asb_memo = "",
        .ext = .{
            .data_use_asset_boundle = 0,
            .ex_res_server_url = "",
            .ex_resource_url = "",
            .res_use_asset_boundle = 0,
        },
        .asset_bundle_url = "",
        .lua_url = "",
    });
}

const ServerDispatchData = struct {
    retcode: i32,
    client_secret_key: []const u8,
    region_name: []const u8,
    gateway: ?struct { ip: []const u8, port: u16 } = null,
    stop_begin_time: ?u64 = null,
    stop_end_time: ?u64 = null,
    msg: ?[]const u8 = null,
    design_data_relogin: i32,
    design_data_memo: []const u8,
    asb_relogin: i32,
    asb_memo: []const u8,
    ext: struct {
        data_use_asset_boundle: u1,
        ex_res_server_url: []const u8,
        ex_resource_url: []const u8,
        res_use_asset_boundle: u1,
    },
    asset_bundle_url: []const u8,
    lua_url: []const u8,
};

const Allocator = std.mem.Allocator;
const Io = std.Io;

const http = @import("../http.zig");
const routes = @import("../routes.zig");
const std = @import("std");
