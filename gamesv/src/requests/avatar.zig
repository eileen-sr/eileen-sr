pub fn onGetAvatarDataCsReq(txn: Transaction, request: pb.GetAvatarDataCsReq) !void {
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    const avatar = &txn.modules.avatar;

    var avatar_list: std.ArrayList(pb.Avatar) = try .initCapacity(
        txn.arena,
        avatar.list.len,
    );

    const list = avatar.list.slice();

    for (
        list.items(.avatar_id),
        list.items(.exp),
        list.items(.level),
        list.items(.promotion),
        list.items(.rank),
        list.items(.equipment_unique_id),
    ) |avatar_id, exp, level, promotion, rank, euid| avatar_list.appendAssumeCapacity(.{
        .avatar_id = avatar_id.toInt(),
        .exp = exp,
        .level = level.toInt(),
        .promotion = promotion.toInt(),
        .rank = rank.toInt(),
        .equipment_unique_id = euid.toInt(),
    });

    try txn.sendMessage(pb.GetAvatarDataScRsp{
        .is_all = request.is_get_all,
        .avatar_list = avatar_list,
    });
}

pub fn onDressAvatarCsReq(txn: Transaction, request: pb.DressAvatarCsReq) !void {
    try txn.modules.login.step.ensureExact(.finished);

    const avatar = &txn.modules.avatar;
    const inventory = &txn.modules.inventory;

    const avatar_index = avatar.index.get(@enumFromInt(request.avatar_id)) orelse {
        return txn.sendError(pb.DressAvatarScRsp, .RET_AVATAR_NOT_EXIST);
    };

    const equipment_index = inventory.equipment_index.get(@enumFromInt(request.equipment_unique_id)) orelse {
        return txn.sendError(pb.DressAvatarScRsp, .RET_AVATAR_DRESS_NO_EQUIPMENT);
    };

    const avatar_list = avatar.list.slice();
    const equipment_list = inventory.equipment.slice();

    const prev_euid = avatar_list.items(.equipment_unique_id)[avatar_index.toInt()];

    if (prev_euid != .none) {
        if (inventory.equipment_index.get(@enumFromInt(@intFromEnum(prev_euid)))) |prev_index| {
            equipment_list.items(.belong_avatar_id)[prev_index] = .none;
        }
    }

    equipment_list.items(.belong_avatar_id)[equipment_index] = @enumFromInt(request.avatar_id);
    avatar_list.items(.equipment_unique_id)[avatar_index.toInt()] = @enumFromInt(request.equipment_unique_id);

    try txn.notify(.avatar_modified, .{ .avatar_id = @enumFromInt(request.avatar_id) });
    try txn.notify(.equipment_modified, .{ .equipment_unique_id = request.equipment_unique_id });

    var player_sync: pb.PlayerSyncScNotify = .{
        .avatar_sync = .init,
    };

    try player_sync.avatar_sync.?.avatar_list.append(txn.arena, .{
        .avatar_id = avatar_list.items(.avatar_id)[avatar_index.toInt()].toInt(),
        .exp = avatar_list.items(.exp)[avatar_index.toInt()],
        .level = avatar_list.items(.level)[avatar_index.toInt()].toInt(),
        .promotion = avatar_list.items(.promotion)[avatar_index.toInt()].toInt(),
        .rank = avatar_list.items(.rank)[avatar_index.toInt()].toInt(),
        .equipment_unique_id = avatar_list.items(.equipment_unique_id)[avatar_index.toInt()].toInt(),
    });

    try txn.sendMessage(player_sync);
    try txn.sendMessage(pb.DressAvatarScRsp.init);
}

pub fn onTakeOffEquipmentCsReq(txn: Transaction, request: pb.TakeOffEquipmentCsReq) !void {
    try txn.modules.login.step.ensureExact(.finished);

    const avatar = &txn.modules.avatar;
    const inventory = &txn.modules.inventory;

    const avatar_index = avatar.index.get(@enumFromInt(request.avatar_id)) orelse {
        return txn.sendError(pb.DressAvatarScRsp, .RET_AVATAR_NOT_EXIST);
    };

    const avatar_list = avatar.list.slice();
    const equipment_list = inventory.equipment.slice();

    const prev_euid = avatar_list.items(.equipment_unique_id)[avatar_index.toInt()];

    if (prev_euid != .none) {
        if (inventory.equipment_index.get(@enumFromInt(@intFromEnum(prev_euid)))) |prev_index| {
            equipment_list.items(.belong_avatar_id)[prev_index] = .none;
        }
    }

    avatar_list.items(.equipment_unique_id)[avatar_index.toInt()] = .none;

    try txn.notify(.avatar_modified, .{ .avatar_id = @enumFromInt(request.avatar_id) });

    var player_sync: pb.PlayerSyncScNotify = .{
        .avatar_sync = .init,
    };

    try player_sync.avatar_sync.?.avatar_list.append(txn.arena, .{
        .avatar_id = avatar_list.items(.avatar_id)[avatar_index.toInt()].toInt(),
        .exp = avatar_list.items(.exp)[avatar_index.toInt()],
        .level = avatar_list.items(.level)[avatar_index.toInt()].toInt(),
        .promotion = avatar_list.items(.promotion)[avatar_index.toInt()].toInt(),
        .rank = avatar_list.items(.rank)[avatar_index.toInt()].toInt(),
        .equipment_unique_id = avatar_list.items(.equipment_unique_id)[avatar_index.toInt()].toInt(),
    });

    try txn.sendMessage(player_sync);
    try txn.sendMessage(pb.TakeOffEquipmentScRsp.init);
}

const Transaction = @import("../requests.zig").Transaction;
const pb = @import("proto").pb;
const std = @import("std");
