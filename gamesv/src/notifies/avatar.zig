const log = std.log.scoped(.avatar);

pub fn onFirstLogin(txn: Transaction, argument: notifies.Argument.FirstLogin) !void {
    _ = argument;

    for (txn.assets.tables.avatar.rows) |row| if (row.Release) {
        _ = try txn.modules.avatar.add(txn.gpa, .{ .avatar_id = row.AvatarID });
    };

    saveAvatarList(txn.io, &txn.modules.avatar, txn.modules.login.uid) catch |err| {
        log.err("failed to save avatar list: {t}", .{err});
    };
}

pub fn onAvatarModified(txn: Transaction, argument: notifies.Argument.AvatarModified) !void {
    _ = argument;

    saveAvatarList(txn.io, &txn.modules.avatar, txn.modules.login.uid) catch |err| {
        log.err("failed to save avatar list: {t}", .{err});
    };
}

fn saveAvatarList(io: Io, module: *const Avatar, uid: modules.Login.Uid) !void {
    const old_cancel_protection = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(old_cancel_protection);

    var path_buf: [128]u8 = undefined;
    try store.saveMultiArray(
        Avatar.Data,
        io,
        store.makePath(store.avatar_list_path, &path_buf, uid),
        &module.list,
    );
}

const Avatar = modules.Avatar;
const modules = @import("../modules.zig");
const store = @import("../store.zig");

const Io = std.Io;

const Transaction = notifies.Transaction;
const notifies = @import("../notifies.zig");
const std = @import("std");
