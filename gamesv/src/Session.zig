const read_timeout: Io.Timeout = .{ .duration = .{
    .clock = .awake,
    .raw = .fromSeconds(30),
} };

list_node: DoublyLinkedList.Node,
recv_buffer: [16384]u8,
stream: net.Stream,
recv_buffer_end: usize,
modules: @import("modules.zig").Container,

pub const ReadError = net.Stream.Reader.Error || Io.ConcurrentError || Io.Timeout.Error || error{EndOfStream};

pub const ReadCompletion = struct {
    session: *Session,
    result: ReadError!usize,
};

pub fn initPinned(session: *Session, stream: net.Stream) void {
    session.stream = stream;
    session.recv_buffer_end = 0;
    session.modules = .init;
}

pub fn deinit(session: *Session, gpa: Allocator) void {
    session.modules.deinit(gpa);
}

pub fn disconnect(session: *Session, io: Io) void {
    session.stream.close(io);
}

pub fn disconnectAndFree(session: *Session, gpa: Allocator, io: Io) void {
    session.disconnect(io);
    session.deinit(gpa);
}

pub fn read(session: *Session, io: Io) ReadCompletion {
    return .{
        .session = session,
        .result = concurrentTimeout(io, read_timeout, readInner, .{ session, io }),
    };
}

fn readInner(session: *Session, io: Io) ReadError!usize {
    var reader = session.stream.reader(io, &session.recv_buffer);
    reader.interface.end = session.recv_buffer_end;

    while (!protocol.NetPacket.isComplete(reader.interface.buffered()))
        reader.interface.fillMore() catch |err| return switch (err) {
            error.EndOfStream => |e| e,
            error.ReadFailed => reader.err.?,
        };

    return reader.interface.end - session.recv_buffer_end;
}

pub const Pool = struct {
    pub const empty: Pool = .{
        .active_list = .{},
        .free_list = .{},
    };

    active_list: DoublyLinkedList,
    free_list: DoublyLinkedList,

    pub fn deinit(pool: *Pool, gpa: Allocator) void {
        for ([_]?*DoublyLinkedList.Node{
            pool.active_list.first,
            pool.free_list.first,
        }, 0..) |first, list| {
            var next = first;
            while (next) |node| {
                next = node.next;

                const session: *Session = @alignCast(@fieldParentPtr("list_node", node));
                if (list == 0) session.deinit(gpa);

                gpa.destroy(session);
            }
        }
    }

    pub fn create(pool: *Pool, gpa: Allocator) Allocator.Error!*Session {
        if (pool.free_list.pop()) |node| {
            pool.active_list.append(node);
            return @alignCast(@fieldParentPtr("list_node", node));
        } else {
            const session = try gpa.create(Session);
            session.list_node = .{};
            pool.active_list.append(&session.list_node);
            return session;
        }
    }

    pub fn destroy(pool: *Pool, session: *Session) void {
        pool.active_list.remove(&session.list_node);
        pool.free_list.append(&session.list_node);
    }
};

const DoublyLinkedList = std.DoublyLinkedList;
const Allocator = std.mem.Allocator;
const Io = std.Io;

const net = std.Io.net;
const concurrentTimeout = common.io.concurrentTimeout;

const protocol = @import("protocol.zig");
const common = @import("common");
const std = @import("std");
const Session = @This();
