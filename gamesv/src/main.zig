const log = std.log.scoped(.gamesv);

const accept_rearm_delay: Io.Timeout = .{ .duration = .{
    .clock = .awake,
    .raw = .fromSeconds(1),
} };

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

    var assets = Assets.load(gpa, io) catch |err| {
        log.err("asset loading failed: {t}", .{err});
        return 1;
    };

    defer assets.deinit();

    const termination: Termination = .init(io);

    const listen_address = comptime net.IpAddress.parseLiteral("127.0.0.1:23301") catch unreachable;
    var server = listen_address.listen(io, .{ .reuse_address = true }) catch |err| {
        log.err("failed to listen at {f}: {t}", .{ listen_address, err });
        if (err == error.AddressInUse)
            log.info("another instance of this server might be already running", .{});

        return 1;
    };

    defer server.deinit(io);

    var session_pool: Session.Pool = .empty;
    defer session_pool.deinit(gpa);

    const Completion = union(enum) {
        termination: Io.Cancelable!void,
        accept: net.Server.AcceptError!net.Stream,
        accept_rearm: Io.Cancelable!void,
        client_read: Session.ReadCompletion,
        process_all: requests.Completion,
    };

    var completions_buffer: [16]Completion = undefined;
    var select: Io.Select(Completion) = .init(io, &completions_buffer);
    defer select.cancelDiscard();

    select.concurrent(.accept, net.Server.accept, .{ &server, io }) catch {
        log.err("failed to initialize listener, concurrency is not available", .{});
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

    while (!termination.shutdownRequested()) on_completion: switch (select.await() catch
        // main() cannot be canceled.
        unreachable) {
        .termination => break,

        .accept => |accepted| {
            const stream = accepted catch |err| switch (err) {
                error.Canceled => unreachable,

                error.SystemResources,
                error.ProcessFdQuotaExceeded,
                error.SystemFdQuotaExceeded,
                => {
                    select.async(.accept_rearm, Io.Timeout.sleep, .{ accept_rearm_delay, io });
                    continue;
                },

                else => |e| {
                    log.err("accept failed: {t}", .{e});
                    continue :on_completion .{ .accept_rearm = {} };
                },
            };

            const fallible: (Allocator.Error || Io.ConcurrentError)!void = blk: {
                const session = session_pool.create(gpa) catch |err| break :blk err;
                session.initPinned(stream);

                select.concurrent(.client_read, Session.read, .{ session, io }) catch |err| {
                    session_pool.destroy(session);
                    break :blk err;
                };
            };

            fallible catch |err| {
                log.err("connection from {f} discarded: {t}", .{ stream.socket.address, err });
                stream.close(io);
            };

            log.debug("new connection from {f}", .{stream.socket.address});
            continue :on_completion .{ .accept_rearm = {} };
        },
        .accept_rearm => select.concurrent(.accept, net.Server.accept, .{ &server, io }) catch
            select.async(.accept_rearm, Io.Timeout.sleep, .{ accept_rearm_delay, io }),
        .client_read => |completion| {
            const session = completion.session;
            const n_read = completion.result catch |err| {
                if (err == error.EndOfStream)
                    log.debug("client from {f} disconnected", .{session.stream.socket.address})
                else
                    log.err(
                        "failed to receive from {f}: {t}",
                        .{ session.stream.socket.address, err },
                    );

                session.disconnectAndFree(gpa, io);
                session_pool.destroy(session);
                continue;
            };

            session.recv_buffer_end += n_read;
            select.async(.process_all, requests.processAll, .{ gpa, io, &assets, session });
        },
        .process_all => |completion| {
            const session = completion.session;
            const consumed = completion.result catch |err| {
                log.err(
                    "failed to process packets from {f}: {t}",
                    .{ session.stream.socket.address, err },
                );
                session.disconnectAndFree(gpa, io);
                session_pool.destroy(session);
                continue;
            };

            const new_end = session.recv_buffer_end - consumed;
            @memmove(
                session.recv_buffer[0..new_end],
                session.recv_buffer[consumed..session.recv_buffer_end],
            );

            session.recv_buffer_end = new_end;

            select.concurrent(.client_read, Session.read, .{ session, io }) catch |err| {
                log.err("dropping connection from {f}: {t}", .{ session.stream.socket.address, err });
                session.disconnectAndFree(gpa, io);
                session_pool.destroy(session);
            };
        },
    };

    log.info("shutting down...", .{});
    return 0;
}

const DebugAllocator = std.heap.DebugAllocator;
const Allocator = std.mem.Allocator;

const Termination = common.Termination;
const Io = std.Io;

const net = std.Io.net;
const debug = std.debug;

const Assets = @import("Assets.zig");
const Session = @import("Session.zig");
const requests = @import("requests.zig");
const protocol = @import("protocol.zig");

const common = @import("common");
const std = @import("std");
