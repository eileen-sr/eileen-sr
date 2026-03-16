const log = std.log.scoped(.requests);

pub const Completion = struct {
    session: *Session,
    result: Error!usize,
};

pub const Error = error{
    CorruptedPacket,
} || net.Stream.Writer.Error || Allocator.Error;

pub const HandlerError = modules.LogicError || Io.Writer.Error || Allocator.Error || Io.Cancelable;

pub fn processAll(gpa: Allocator, io: Io, assets: *const Assets, session: *Session) Completion {
    var consumed: usize = 0;
    var send_buffer: [4096]u8 = undefined;
    var writer = session.stream.writer(io, &send_buffer);

    while (protocol.NetPacket.deserialize(session.recv_buffer[consumed..session.recv_buffer_end])) |packet| {
        consumed += packet.size();

        processOne(gpa, io, assets, session, &writer, packet) catch |err| {
            return .{ .session = session, .result = err };
        };
    } else |err| return .{ .session = session, .result = switch (err) {
        error.NotCorrect => error.CorruptedPacket,
        error.NotComplete => return .{
            .session = session,
            .result = if (writer.interface.flush()) consumed else |flush_err| switch (flush_err) {
                error.WriteFailed => writer.err.?,
            },
        },
    } };
}

fn processOne(
    gpa: Allocator,
    io: Io,
    assets: *const Assets,
    session: *Session,
    writer: *net.Stream.Writer,
    packet: protocol.NetPacket,
) Error!void {
    @setEvalBranchQuota(1_000_000);

    log.debug(
        "received packet with cmd_id {d} from {f}",
        .{ packet.cmd_id, session.stream.socket.address },
    );

    if (std.enums.fromInt(proto.CmdType, packet.cmd_id)) |id| switch (id) {
        inline else => |cmd_id| search: inline for (namespaces) |namespace| {
            const Message = proto.TypeOf(cmd_id);
            inline for (@typeInfo(namespace).@"struct".decls) |decl| {
                if (@typeInfo(@TypeOf(@field(namespace, decl.name))).@"fn".params[1].type != Message)
                    continue;

                var arena: ArenaAllocator = .init(gpa);
                defer arena.deinit();

                var reader: Io.Reader = .fixed(packet.body);
                const message = proto.decodeMessage(&reader, arena.allocator(), Message) catch
                    return error.CorruptedPacket;

                const txn: Transaction = .{
                    .io = io,
                    .gpa = gpa,
                    .arena = arena.allocator(),
                    .assets = assets,
                    .modules = &session.modules,
                    .time = .now(io, .real),
                    .writer = &writer.interface,
                };

                @field(namespace, decl.name)(txn, message) catch |err| switch (@as(HandlerError, err)) {
                    error.WriteFailed => return writer.err.?,
                    error.OutOfMemory => |e| return e,
                    else => |e| log.err(
                        "{s}: logic error occurred: {t}",
                        .{ decl.name, e },
                    ),
                };

                log.info("successfully processed message of type {t}", .{cmd_id});
                break :search;
            }
        } else log.warn("no handler registered for message {t}", .{cmd_id}),
    } else {
        log.err(
            "received illegal cmd_id ({d}) from {f}",
            .{ packet.cmd_id, session.stream.socket.address },
        );
    }
}

pub const Transaction = struct {
    io: Io,
    gpa: Allocator,
    arena: Allocator,
    assets: *const Assets,
    modules: *modules.Container,
    time: Io.Timestamp,
    writer: *Io.Writer,

    pub inline fn sendMessage(txn: *const Transaction, message: anytype) Io.Writer.Error!void {
        try protocol.NetPacket.serialize(txn.writer, message);
    }

    pub inline fn sendError(
        txn: *const Transaction,
        comptime Message: type,
        retcode: proto.pb.Retcode,
    ) Io.Writer.Error!void {
        try txn.sendMessage(Message{ .retcode = @intFromEnum(retcode) });
    }

    pub inline fn notify(
        txn: *const Transaction,
        comptime notify_type: notifies.Type,
        argument: @FieldType(notifies.Argument, @tagName(notify_type)),
    ) !void {
        const notify_txn: notifies.Transaction = .{
            .io = txn.io,
            .gpa = txn.gpa,
            .arena = txn.arena,
            .assets = txn.assets,
            .modules = txn.modules,
            .time = txn.time,
        };

        try notifies.dispatch(notify_txn, notify_type, argument);
    }
};

const namespaces: []const type = &.{
    @import("requests/avatar.zig"),
    @import("requests/item.zig"),
    @import("requests/mail.zig"),
    @import("requests/player.zig"),
    @import("requests/tutorial.zig"),
    @import("requests/lineup.zig"),
    @import("requests/mission.zig"),
    @import("requests/quest.zig"),
    @import("requests/challenge.zig"),
    @import("requests/shop.zig"),
    @import("requests/scene.zig"),
    @import("requests/battle.zig"),
    @import("requests/maze.zig"),
};

const Io = std.Io;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const net = std.Io.net;

const notifies = @import("notifies.zig");
const modules = @import("modules.zig");
const Assets = @import("Assets.zig");
const Session = @import("Session.zig");
const protocol = @import("protocol.zig");
const proto = @import("proto");
const std = @import("std");
