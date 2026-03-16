const log = std.log.scoped(.dpsv);

pub const std_options: std.Options = .{
    .log_level = .debug,
};

pub fn main() u8 {
    var debug_allocator: DebugAllocator(.{}) = .init;
    defer if (debug.runtime_safety) {
        debug.assert(.ok == debug_allocator.deinit());
    };

    const gpa = if (debug.runtime_safety)
        debug_allocator.allocator()
    else
        std.heap.smp_allocator;

    var threaded: Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var termination: Termination = .init(io);

    const listen_address = comptime net.IpAddress.parseLiteral("127.0.0.1:10001") catch unreachable;

    var server = listen_address.listen(io, .{ .reuse_address = true }) catch |err| {
        log.err("failed to listen at {f}: {t}", .{ listen_address, err });
        if (err == error.AddressInUse)
            log.info("another instance of this server might be already running", .{});

        return 1;
    };

    defer server.deinit(io);

    var connection_pool: MemoryPool(http.Connection) = .empty;
    defer connection_pool.deinit(gpa);

    const Completion = union(enum) {
        termination: Io.Cancelable!void,
        accept: net.Server.AcceptError!net.Stream,
        client_read: http.ReadCompletion,
        handle_request: routes.Completion,
    };

    var completions_buffer: [16]Completion = undefined;
    var select: Io.Select(Completion) = .init(io, &completions_buffer);
    defer select.cancelDiscard();

    select.concurrent(.accept, net.Server.accept, .{ &server, io }) catch {
        log.err("failed to initialize because concurrency is not available", .{});
        return 1;
    };

    select.concurrent(.termination, Termination.await, .{ &termination, io }) catch {
        // We won't be notified about the termination by select.
    };

    std.debug.print(
        \\    _______ __               _____ ____ 
        \\   / ____(_) /__  ___  ____ / ___// __ \
        \\  / __/ / / / _ \/ _ \/ __ \\__ \/ /_/ /
        \\ / /___/ / /  __/  __/ / / /__/ / _, _/ 
        \\/_____/_/_/\___/\___/_/ /_/____/_/ |_|  
        \\
    , .{});

    log.info("listening at {f}", .{listen_address});

    while (!termination.shutdownRequested()) switch (select.await() catch
        // main() cannot be canceled
        unreachable) {
        .termination => break,

        .accept => |accepted| {
            while (true) {
                if (select.concurrent(.accept, net.Server.accept, .{ &server, io })) break else |_| {
                    log.err("failed to re-arm accept", .{});
                    io.sleep(.fromSeconds(1), .awake) catch unreachable;
                }
            }

            const stream = accepted catch |err| {
                log.err("accept failed: {t}", .{err});
                continue;
            };

            const fallible: (Allocator.Error || Io.ConcurrentError)!void = blk: {
                const conn = connection_pool.create(gpa) catch |err| break :blk err;
                conn.initPinned(stream);

                select.concurrent(
                    .client_read,
                    http.Connection.readRequestLine,
                    .{ conn, io },
                ) catch |err| {
                    connection_pool.destroy(conn);
                    break :blk err;
                };
            };

            fallible catch |err| {
                log.err("connection from {f} discarded: {t}", .{ stream.socket.address, err });
                stream.close(io);
            };

            log.debug("new connection from {f}", .{stream.socket.address});
        },
        .client_read => |completion| {
            const connection = completion.connection;
            const request = completion.result catch |err| {
                log.debug(
                    "failed to receive request from {f}: {t}",
                    .{ connection.stream.socket.address, err },
                );

                connection.stream.close(io);
                connection_pool.destroy(@alignCast(connection));
                continue;
            };

            if (request.method != .GET) {
                log.debug(
                    "unsupported request method {f}: {t}",
                    .{ connection.stream.socket.address, request.method },
                );

                connection.stream.close(io);
                connection_pool.destroy(@alignCast(connection));
                continue;
            }

            log.debug(
                "received request from {f}: {s}",
                .{ connection.stream.socket.address, request.target },
            );

            select.async(.handle_request, routes.handleRequest, .{ gpa, io, connection, request });
        },
        .handle_request => |completion| {
            const connection = completion.connection;
            completion.result catch |err| log.debug(
                "failed to process request from {f}: {t}",
                .{ connection.stream.socket.address, err },
            );

            connection.stream.close(io);
            connection_pool.destroy(@alignCast(connection));
        },
    };

    log.info("shutting down...", .{});
    return 0;
}

const DebugAllocator = std.heap.DebugAllocator;
const MemoryPool = std.heap.MemoryPool;
const Allocator = std.mem.Allocator;

const Termination = common.Termination;
const Io = std.Io;

const debug = std.debug;
const net = Io.net;

const routes = @import("routes.zig");
const http = @import("http.zig");

const common = @import("common");
const std = @import("std");
