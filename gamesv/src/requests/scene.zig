pub fn onGetCurSceneInfoCsReq(txn: Transaction, request: pb.GetCurSceneInfoCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    const entry_id = txn.modules.scene.entry_id;
    const entry = txn.assets.tables.map_entry.map.get(@enumFromInt(entry_id)).?;

    try txn.sendMessage(pb.GetCurSceneInfoScRsp{
        .scene = try packSceneInfo(
            txn.arena,
            txn.assets,
            entry,
            txn.modules.scene.motion,
            txn.modules.login.uid,
        ),
    });

    if (txn.modules.login.step == .waiting_key_packets)
        txn.modules.login.onAllKeyPacketsReturn();

    std.log.scoped(.scene).info(
        "entering maze {d} (plane={d}, floor={d})",
        .{ entry_id, entry.PlaneID, entry.FloorID },
    );
}

pub fn onEnterMazeCsReq(txn: Transaction, request: pb.EnterMazeCsReq) !void {
    try txn.modules.login.step.ensureExact(.finished);

    const entry = txn.assets.tables.map_entry.map.get(@enumFromInt(request.entry_id)) orelse {
        return txn.sendError(pb.EnterMazeScRsp, .RET_MAZE_MAP_NOT_EXIST);
    };

    if (request.plane_id != 0 and entry.PlaneID != request.plane_id) {
        return txn.sendError(pb.EnterMazeScRsp, .RET_PLANE_ID_NOT_MATCH);
    }

    if (request.floor_id != 0 and entry.FloorID != request.floor_id) {
        return txn.sendError(pb.EnterMazeScRsp, .RET_FLOOR_ID_NOT_MATCH);
    }

    if (Scene.getStartMotion(txn.assets, entry)) |motion| {
        txn.modules.scene.entry_id = entry.EntryID.toInt();
        txn.modules.scene.motion = motion;
    }

    if (txn.modules.scene.entry_id != entry.EntryID.toInt()) {
        return txn.sendError(pb.EnterMazeScRsp, .RET_SCENE_ENTRY_ID_NOT_MATCH);
    }

    try txn.notify(.scene_changed, .{});

    try txn.sendMessage(pb.EnterMazeScRsp{
        .maze = .{
            .id = entry.PlaneID,
            .map_entry_id = entry.EntryID.toInt(),
            .floor = .{
                .floor_id = entry.FloorID,
                .scene = try packSceneInfo(
                    txn.arena,
                    txn.assets,
                    entry,
                    txn.modules.scene.motion,
                    txn.modules.login.uid,
                ),
            },
        },
    });

    std.log.scoped(.scene).info(
        "entering maze {d} (plane={d}, floor={d})",
        .{ entry.EntryID, entry.PlaneID, entry.FloorID },
    );
}

pub fn onSceneEntityMoveCsReq(txn: Transaction, request: pb.SceneEntityMoveCsReq) !void {
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    for (request.entity_motion_list.items) |item| if (item.entity_id == 0) if (item.motion) |motion| {
        txn.modules.scene = .{
            .entry_id = request.entry_id,
            .motion = .{
                .pos = .from(pb.Vector, motion.pos.?),
                .rot = .from(pb.Vector, motion.rot.?),
            },
        };

        try txn.notify(.scene_changed, .{});
    };

    try txn.sendMessage(pb.SceneEntityMoveScRsp{});
}

fn packSceneInfo(
    arena: Allocator,
    assets: *const Assets,
    entry: *const MapEntryRow,
    motion: Scene.Motion,
    uid: Login.Uid,
) Allocator.Error!pb.SceneInfo {
    var entity_list: std.ArrayList(pb.SceneEntityInfo) = .empty;

    try entity_list.append(arena, .{
        .motion = .{
            .pos = motion.pos.to(pb.Vector),
            .rot = motion.rot.to(pb.Vector),
        },
        .entity = .{
            .actor = .{
                .uid = uid.toInt(),
            },
        },
    });

    for (assets.floor.map.get(entry.FloorID).?.GroupList) |group_desc| {
        const group = assets.group.map.get(.{
            .floor_id = entry.FloorID,
            .group_id = group_desc.ID,
        }).?;

        if (group.PropList) |prop_list| for (prop_list) |prop| if (prop.CreateOnInitial) {
            const entity_id: u32 = @truncate(entity_list.items.len);

            try entity_list.append(arena, .{
                .entity_id = entity_id,
                .motion = .{
                    .pos = .{
                        .x = @intFromFloat(prop.PosX * 1000),
                        .y = @intFromFloat(prop.PosY * 1000),
                        .z = @intFromFloat(prop.PosZ * 1000),
                    },
                    .rot = .{
                        .x = @intFromFloat(prop.RotX * 1000),
                        .y = @intFromFloat(prop.RotY * 1000),
                        .z = @intFromFloat(prop.RotZ * 1000),
                    },
                },
                .group_id = group_desc.ID,
                .inst_id = prop.ID,
                .entity = .{ .prop = .{
                    .prop_id = prop.PropID,
                    .prop_state = 1,
                } },
            });
        };
    }

    return .{
        .entry_id = entry.EntryID.toInt(),
        .plane_id = entry.PlaneID,
        .floor_id = entry.FloorID,
        .entity_list = entity_list,
    };
}

pub fn onStartCocoonStageCsReq(txn: Transaction, request: pb.StartCocoonStageCsReq) !void {
    const log = std.log.scoped(.start_cocoon_stage);
    const wave_limit = 5;
    const max_monsters_per_wave = 5;

    try txn.modules.login.step.ensureExact(.finished);

    if (request.wave == 0 or request.wave > wave_limit) {
        return txn.sendError(pb.StartCocoonStageScRsp, .RET_STAGE_COCOON_WAVE_NOT_VALID);
    }

    const world_level = txn.modules.player.world_level;
    const cocoon = txn.assets.tables.getCocoonRow(request.cocoon_id, world_level.toInt()) orelse {
        log.err(
            "cocoon with id {d}, world level {d} doesn't exist",
            .{ request.cocoon_id, world_level.toInt() },
        );
        return txn.sendError(pb.StartCocoonStageScRsp, .RET_STAGE_NOT_FOUND);
    };

    const lineup = &txn.modules.lineup;
    const avatar = &txn.modules.avatar;
    const inventory = &txn.modules.inventory;

    const avatar_slice = avatar.list.slice();
    const equipment_slice = inventory.equipment.slice();

    const slots = lineup.list.items(.slots)[lineup.active_index.toInt()];

    var avatar_buf: [Lineup.Avatar.Slot.count]pb.BattleAvatar = undefined;
    var equipment_buf: [Lineup.Avatar.Slot.count]pb.BattleEquipment = undefined;

    var wave_buf: [wave_limit]pb.SceneMonsterWave = undefined;
    var monster_id_list_buf: [wave_limit * max_monsters_per_wave]u32 = undefined;

    var avatar_list: std.ArrayList(pb.BattleAvatar) = .initBuffer(&avatar_buf);
    var wave_list: std.ArrayList(pb.SceneMonsterWave) = .initBuffer(&wave_buf);

    for (0..request.wave) |wave| {
        var monster_id_list: std.ArrayList(u32) = .initBuffer(
            monster_id_list_buf[wave * max_monsters_per_wave ..][0..max_monsters_per_wave],
        );

        const stage_id = cocoon.StageIDList[wave % cocoon.StageIDList.len];
        const stage = txn.assets.tables.stage.map.get(@enumFromInt(stage_id)) orelse continue;

        inline for (0..max_monsters_per_wave) |i| {
            const id = @field(stage.MonsterList[0], std.fmt.comptimePrint("Monster{d}", .{i}));
            if (id != 0) monster_id_list.appendAssumeCapacity(id);
        }

        wave_list.appendAssumeCapacity(.{ .monster_id_list = monster_id_list });
    }

    for (slots.values, 0..) |maybe_avatar, i| if (maybe_avatar) |lineup_avatar| {
        const avatar_index = avatar.index.get(lineup_avatar.id) orelse continue;
        const battle_avatar = avatar_list.addOneAssumeCapacity();

        battle_avatar.* = .{
            .index = @truncate(i),
            .avatar_type = .AVATAR_FORMAL_TYPE,
            .id = lineup_avatar.id.toInt(),
            .level = avatar_slice.items(.level)[avatar_index.toInt()].toInt(),
            .rank = avatar_slice.items(.rank)[avatar_index.toInt()].toInt(),
            .hp = lineup_avatar.hp.toInt(),
            .sp = lineup_avatar.sp.toInt(),
            .promotion = avatar_slice.items(.promotion)[avatar_index.toInt()].toInt(),
            .equipment_list = .initBuffer(equipment_buf[i .. i + 1]),
            .skilltree_list = .empty,
        };

        const equipment_unique_id = avatar_slice.items(.equipment_unique_id)[avatar_index.toInt()];
        if (equipment_unique_id == .none) continue;

        const equipment_index = inventory.equipment_index.get(
            @enumFromInt(@intFromEnum(equipment_unique_id)),
        ) orelse continue;

        battle_avatar.equipment_list.appendAssumeCapacity(.{
            .id = equipment_slice.items(.id)[equipment_index].toInt(),
            .level = equipment_slice.items(.level)[equipment_index].toInt(),
            .promotion = equipment_slice.items(.promotion)[equipment_index].toInt(),
            .rank = equipment_slice.items(.rank)[equipment_index].toInt(),
        });
    };

    try txn.sendMessage(pb.StartCocoonStageScRsp{
        .wave = request.wave,
        .prop_entity_id = request.prop_entity_id,
        .cocoon_id = request.cocoon_id,
        .battle_info = .{
            .logic_random_seed = @truncate(@as(u96, @bitCast(txn.time.toNanoseconds()))),
            .stage_id = cocoon.StageID,
            .monster_wave_list = wave_list,
            .battle_avatar_list = avatar_list,
        },
    });
}

const Login = modules.Login;
const Scene = modules.Scene;
const Lineup = modules.Lineup;
const Allocator = std.mem.Allocator;
const MapEntryRow = Assets.ExcelTables.MapEntryRow;

const Assets = @import("../Assets.zig");
const modules = @import("../modules.zig");

const Transaction = @import("../requests.zig").Transaction;
const pb = @import("proto").pb;
const std = @import("std");
