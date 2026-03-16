const log = std.log.scoped(.lineup);

const default_lineup: Lineup.Data = .{
    .name = .constant("ReversedRooms"),
    .slots = .init(.{
        .first = .{ .id = @enumFromInt(9025) },
        .second = .{ .id = @enumFromInt(1001) },
        .third = .{ .id = @enumFromInt(1003) },
        .fourth = .{ .id = @enumFromInt(1105) },
    }),
    .leader = Lineup.Avatar.Slot.fromInt(0) catch unreachable,
};

pub fn onFirstLogin(txn: Transaction, argument: notifies.Argument.FirstLogin) !void {
    _ = argument;

    if (txn.modules.lineup.active_index == .none) {
        const index = txn.modules.lineup.list.len;
        try txn.modules.lineup.list.append(txn.gpa, default_lineup);
        txn.modules.lineup.active_index = .fromInt(@intCast(index));

        saveLineupList(txn.io, &txn.modules.lineup, txn.modules.login.uid) catch |err| {
            log.err("failed to save lineup list: {t}", .{err});
        };
    }
}

pub fn onLineupLeaderChanged(txn: Transaction, argument: notifies.Argument.LineupLeaderChanged) !void {
    _ = argument;

    saveLineupList(txn.io, &txn.modules.lineup, txn.modules.login.uid) catch |err| {
        log.err("failed to save lineup list: {t}", .{err});
    };
}

pub fn onLineupSlotsChanged(txn: Transaction, argument: notifies.Argument.LineupSlotsChanged) !void {
    _ = argument;

    saveLineupList(txn.io, &txn.modules.lineup, txn.modules.login.uid) catch |err| {
        log.err("failed to save lineup list: {t}", .{err});
    };
}

fn saveLineupList(io: Io, module: *const Lineup, uid: modules.Login.Uid) !void {
    const old_cancel_protection = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(old_cancel_protection);

    var path_buf: [128]u8 = undefined;
    try store.saveMultiArray(
        Lineup.Data,
        io,
        store.makePath(store.lineup_list_path, &path_buf, uid),
        &module.list,
    );

    try store.saveInt(
        u32,
        io,
        store.makePath(store.active_lineup_path, &path_buf, uid),
        @intFromEnum(module.active_index),
    );
}

const Lineup = modules.Lineup;
const modules = @import("../modules.zig");
const store = @import("../store.zig");

const Io = std.Io;
const Transaction = notifies.Transaction;
const notifies = @import("../notifies.zig");
const std = @import("std");
