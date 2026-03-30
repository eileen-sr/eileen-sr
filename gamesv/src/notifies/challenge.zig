const log = std.log.scoped(.challenge);

pub fn onFirstLogin(txn: Transaction, argument: notifies.Argument.FirstLogin) !void {
    _ = argument;

    for (txn.assets.tables.challenge_maze_config.rows) |row| {
        try txn.modules.challenge.map.put(txn.gpa, row.ChallengeMazeID, .initEmpty());
    }

    saveChallengeList(txn.io, &txn.modules.challenge, txn.modules.login.uid) catch |err| {
        log.err("failed to save challenge list: {t}", .{err});
    };
}

pub fn onChallengeFinished(txn: Transaction, argument: notifies.Argument.ChallengeFinished) !void {
    _ = argument;

    saveChallengeList(txn.io, &txn.modules.challenge, txn.modules.login.uid) catch |err| {
        log.err("failed to save challenge list: {t}", .{err});
    };
}

fn saveChallengeList(io: Io, module: *const Challenge, uid: modules.Login.Uid) !void {
    const old_cancel_protection = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(old_cancel_protection);

    var path_buf: [128]u8 = undefined;
    try store.saveArrayHashMap(
        ChallengeMazeConfigRow.ID,
        Challenge.Stars,
        io,
        store.makePath(store.challenge_list_path, &path_buf, uid),
        &module.map,
    );
}

const Challenge = modules.Challenge;
const modules = @import("../modules.zig");
const store = @import("../store.zig");

const ChallengeMazeConfigRow = Assets.ExcelTables.ChallengeMazeConfigRow;
const Assets = @import("../Assets.zig");

const Io = std.Io;

const Transaction = notifies.Transaction;
const notifies = @import("../notifies.zig");
const std = @import("std");
