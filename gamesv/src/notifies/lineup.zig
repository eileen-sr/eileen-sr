const log = std.log.scoped(.lineup);

pub fn onFirstLogin(txn: Transaction, argument: notifies.Argument.FirstLogin) !void {
    _ = argument;

    if (txn.modules.lineup.active_index == .none) {
        const index = txn.modules.lineup.list.len;

        inline for (0..6) |i| {
            try txn.modules.lineup.list.append(txn.gpa, .initEmpty(
                .constant(std.fmt.comptimePrint("Team {}", .{i + 1})),
                .default,
            ));
        }

        // default lineup
        txn.modules.lineup.list.items(.slots)[index] = .init(.{
            .first = .{ .id = @enumFromInt(9025) },
            .second = .{ .id = @enumFromInt(1001) },
            .third = .{ .id = @enumFromInt(1003) },
            .fourth = .{ .id = @enumFromInt(1105) },
        });

        try txn.modules.lineup.list.append(txn.gpa, .initEmpty(
            .empty,
            .{
                .challenge = true,
                .virtual = false,
            },
        ));

        txn.modules.lineup.active_index = .fromInt(@intCast(index));

        saveLineupList(txn.io, &txn.modules.lineup, txn.modules.login.uid) catch |err| {
            log.err("failed to save lineup list: {t}", .{err});
        };

        saveActiveLineup(txn.io, &txn.modules.lineup, txn.modules.login.uid) catch |err| {
            log.err("failed to save active lineup: {t}", .{err});
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

pub fn onLineupNameChanged(txn: Transaction, argument: notifies.Argument.LineupNameChanged) !void {
    _ = argument;

    saveLineupList(txn.io, &txn.modules.lineup, txn.modules.login.uid) catch |err| {
        log.err("failed to save lineup list: {t}", .{err});
    };
}

pub fn onLineupIndexChanged(txn: Transaction, argument: notifies.Argument.LineupIndexChanged) !void {
    _ = argument;

    saveActiveLineup(txn.io, &txn.modules.lineup, txn.modules.login.uid) catch |err| {
        log.err("failed to save active lineup: {t}", .{err});
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
}

fn saveActiveLineup(io: Io, module: *const Lineup, uid: modules.Login.Uid) !void {
    const old_cancel_protection = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(old_cancel_protection);

    var path_buf: [128]u8 = undefined;
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
