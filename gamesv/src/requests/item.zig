pub fn onGetBagCsReq(txn: Transaction, request: pb.GetBagCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);
    const inventory = &txn.modules.inventory;

    var material_list = try ArrayList(pb.Material).initCapacity(
        txn.arena,
        inventory.material_map.entries.len,
    );

    var equipment_list = try ArrayList(pb.Equipment).initCapacity(
        txn.arena,
        inventory.equipment.len,
    );

    for (inventory.material_map.keys(), inventory.material_map.values()) |id, count| {
        material_list.appendAssumeCapacity(.{
            .tid = id.toInt(),
            .num = count.toInt(),
        });
    }

    const equipment = inventory.equipment.slice();

    for (
        equipment.items(.unique_id),
        equipment.items(.id),
        equipment.items(.level),
        equipment.items(.exp),
        equipment.items(.rank),
        equipment.items(.belong_avatar_id),
        equipment.items(.protection),
        equipment.items(.promotion),
    ) |uid, id, level, exp, rank, belong_avatar_id, protection, promotion| {
        equipment_list.appendAssumeCapacity(.{
            .unique_id = uid.toInt(),
            .tid = id.toInt(),
            .level = level.toInt(),
            .exp = exp,
            .rank = rank.toInt(),
            .belong_avatar_id = belong_avatar_id.toInt(),
            .is_protected = protection == .protected,
            .promotion = promotion.toInt(),
        });
    }

    try txn.sendMessage(pb.GetBagScRsp{
        .material_list = material_list,
        .equipment_list = equipment_list,
    });
}

const ArrayList = std.ArrayList;

const Transaction = @import("../requests.zig").Transaction;
const pb = @import("proto").pb;
const std = @import("std");
