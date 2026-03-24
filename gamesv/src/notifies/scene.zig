const log = std.log.scoped(.scene);

const default_entry_id = 2012101;

pub fn onFirstLogin(txn: Transaction, argument: notifies.Argument.FirstLogin) !void {
    _ = argument;

    const entry = txn.assets.tables.map_entry.map.get(@enumFromInt(default_entry_id)).?;

    txn.modules.scene = .{
        .entry_id = default_entry_id,
        .motion = Scene.getStartMotion(txn.assets, entry.FloorID).?,
    };

    saveScene(txn.io, &txn.modules.scene, txn.modules.login.uid) catch |err| {
        log.err("failed to save scene: {t}", .{err});
    };
}

pub fn onSceneChanged(txn: Transaction, argument: notifies.Argument.SceneChanged) !void {
    _ = argument;

    saveScene(txn.io, &txn.modules.scene, txn.modules.login.uid) catch |err| {
        log.err("failed to save scene: {t}", .{err});
    };
}

fn saveScene(io: Io, module: *const Scene, uid: modules.Login.Uid) !void {
    const old_cancel_protection = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(old_cancel_protection);

    var path_buf: [128]u8 = undefined;

    try store.saveStruct(
        Scene,
        io,
        store.makePath(store.scene_module_path, &path_buf, uid),
        module,
    );
}

const Scene = modules.Scene;
const modules = @import("../modules.zig");
const store = @import("../store.zig");

const Io = std.Io;

const Transaction = notifies.Transaction;
const notifies = @import("../notifies.zig");
const pb = @import("proto").pb;
const std = @import("std");
