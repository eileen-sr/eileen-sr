const log = std.log.scoped(.inventory);

pub fn onFirstLogin(txn: Transaction, argument: notifies.Argument.FirstLogin) !void {
    _ = argument;

    for (txn.assets.tables.equipment.rows) |row| {
        _ = try txn.modules.inventory.addEquipment(txn.gpa, row.EquipmentID);
    }

    saveMaterialList(txn.io, &txn.modules.inventory, txn.modules.login.uid) catch |err| {
        log.err("failed to save material list: {t}", .{err});
    };

    saveEquipmentList(txn.io, &txn.modules.inventory, txn.modules.login.uid) catch |err| {
        log.err("failed to save equipment list: {t}", .{err});
    };
}

pub fn onEquipmentModified(txn: Transaction, argument: notifies.Argument.EquipmentModified) !void {
    _ = argument;

    saveEquipmentList(txn.io, &txn.modules.inventory, txn.modules.login.uid) catch |err| {
        log.err("failed to save equipment list: {t}", .{err});
    };
}

fn saveMaterialList(io: Io, module: *const Inventory, uid: modules.Login.Uid) !void {
    const old_cancel_protection = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(old_cancel_protection);

    var path_buf: [128]u8 = undefined;
    try store.saveArrayHashMap(
        ItemRow.ID,
        Inventory.Material,
        io,
        store.makePath(store.material_list_path, &path_buf, uid),
        &module.material_map,
    );
}

fn saveEquipmentList(io: Io, module: *const Inventory, uid: modules.Login.Uid) !void {
    const old_cancel_protection = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(old_cancel_protection);

    var path_buf: [128]u8 = undefined;

    try store.saveMultiArray(
        Inventory.Equipment,
        io,
        store.makePath(store.equipment_list_path, &path_buf, uid),
        &module.equipment,
    );

    try store.saveInt(
        u32,
        io,
        store.makePath(store.equipment_uid_path, &path_buf, uid),
        module.unique_id_counter,
    );
}

const Inventory = modules.Inventory;
const modules = @import("../modules.zig");
const store = @import("../store.zig");

const Io = std.Io;
const ItemRow = Assets.ExcelTables.ItemRow;

const Assets = @import("../Assets.zig");
const Transaction = notifies.Transaction;
const notifies = @import("../notifies.zig");
const std = @import("std");
