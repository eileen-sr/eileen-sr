pub fn onGetCurSceneInfoCsReq(txn: Transaction, request: pb.GetCurSceneInfoCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    const entry_id = txn.modules.scene.entry_id;
    const entry = txn.assets.tables.map_entry.map.get(@enumFromInt(entry_id)).?;

    try txn.modules.scene.enterScene(
        txn.gpa,
        txn.assets,
        entry,
        txn.modules.scene.motion,
        &txn.modules.lineup.list.items(.slots)[@intFromEnum(txn.modules.lineup.active_index)],
    );

    var scene_info: pb.SceneInfo = .init;
    try encoding.packSceneInfo(
        &scene_info,
        txn.arena,
        txn.assets,
        entry,
        &txn.modules.scene.entity_manager,
        txn.modules.login.uid,
    );

    try txn.sendMessage(pb.GetCurSceneInfoScRsp{
        .scene = scene_info,
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

    if (txn.assets.floor.map.get(entry.FloorID) == null) {
        return txn.sendError(pb.EnterMazeScRsp, .RET_MAZE_NO_FLOOR);
    }

    if (request.plane_id != 0 and entry.PlaneID != request.plane_id) {
        return txn.sendError(pb.EnterMazeScRsp, .RET_PLANE_ID_NOT_MATCH);
    }

    if (request.floor_id != 0 and entry.FloorID != request.floor_id) {
        return txn.sendError(pb.EnterMazeScRsp, .RET_FLOOR_ID_NOT_MATCH);
    }

    var motion: ?Scene.Motion = null;
    if (request.config_id != 0) if (txn.assets.group.map.get(.{ .floor_id = entry.FloorID, .group_id = request.group_id })) |anchor_group| {
        for (anchor_group.PropList.?) |prop| if (prop.ID == request.config_id) {
            for (anchor_group.AnchorList.?) |anchor| if (anchor.ID == prop.AnchorID) {
                motion = .{
                    .pos = .{
                        .v = .{
                            @intFromFloat(anchor.PosX * 1000),
                            @intFromFloat(anchor.PosY * 1000),
                            @intFromFloat(anchor.PosZ * 1000),
                        },
                    },
                    .rot = .{
                        .v = .{
                            0,
                            @intFromFloat(anchor.RotY * 1000),
                            0,
                        },
                    },
                };
            };

            break;
        };
    } else if (Scene.getStartMotion(txn.assets, entry.FloorID)) |m| {
        motion = m;
    };

    try txn.modules.scene.enterScene(
        txn.gpa,
        txn.assets,
        entry,
        motion,
        &txn.modules.lineup.list.items(.slots)[@intFromEnum(txn.modules.lineup.active_index)],
    );

    try txn.notify(.scene_changed, .{});

    var scene_info: pb.SceneInfo = .init;
    try encoding.packSceneInfo(
        &scene_info,
        txn.arena,
        txn.assets,
        entry,
        &txn.modules.scene.entity_manager,
        txn.modules.login.uid,
    );

    try txn.sendMessage(pb.EnterMazeScRsp{
        .maze = .{
            .id = entry.PlaneID,
            .map_entry_id = entry.EntryID.toInt(),
            .floor = .{
                .floor_id = entry.FloorID,
                .scene = scene_info,
            },
        },
    });

    std.log.scoped(.scene).info(
        "entering maze {d} (plane={d}, floor={d})",
        .{ entry.EntryID, entry.PlaneID, entry.FloorID },
    );
}

pub fn onSceneEntityMoveCsReq(txn: Transaction, request: pb.SceneEntityMoveCsReq) !void {
    try txn.modules.login.step.ensureExact(.finished);

    if (txn.modules.scene.entry_id == request.entry_id) {
        for (request.entity_motion_list.items) |item| if (item.entity_id < 4) if (item.motion) |motion| {
            txn.modules.scene.motion = .{
                .pos = .from(motion.pos.?),
                .rot = .from(motion.rot.?),
            };

            txn.modules.scene.entity_manager.motion(item.entity_id).* = txn.modules.scene.motion;

            try txn.notify(.scene_changed, .{});
        };
    }

    try txn.sendMessage(pb.SceneEntityMoveScRsp{});
}

pub fn onStartCocoonStageCsReq(txn: Transaction, request: pb.StartCocoonStageCsReq) !void {
    const log = std.log.scoped(.start_cocoon_stage);
    const wave_limit = 5;

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
    var monster_id_list_buf: [wave_limit * Battle.max_monsters_per_wave]u32 = undefined;

    var avatar_list: std.ArrayList(pb.BattleAvatar) = .initBuffer(&avatar_buf);
    var wave_list: std.ArrayList(pb.SceneMonsterWave) = .initBuffer(&wave_buf);

    for (0..request.wave) |wave| {
        const stage_id = cocoon.StageIDList[wave % cocoon.StageIDList.len];
        const stage = txn.assets.tables.stage.map.get(@enumFromInt(stage_id)) orelse continue;

        encoding.packSceneMonsterWave(
            wave_list.addOneAssumeCapacity(),
            monster_id_list_buf[wave * Battle.max_monsters_per_wave ..][0..Battle.max_monsters_per_wave],
            stage,
        );
    }

    for (slots.values, 0..) |maybe_avatar, i| if (maybe_avatar) |lineup_avatar| {
        const avatar_index = avatar.index.get(lineup_avatar.id) orelse continue;
        const battle_avatar = avatar_list.addOneAssumeCapacity();

        encoding.packBattleAvatar(
            battle_avatar,
            &equipment_buf,
            avatar_slice,
            equipment_slice,
            &avatar_index,
            &lineup_avatar,
            &inventory.equipment_index,
            @truncate(i),
        );
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

pub fn onSpringTransferCsReq(txn: Transaction, request: pb.SpringTransferCsReq) !void {
    try txn.modules.login.step.ensureExact(.finished);

    const floor = txn.assets.floor.map.get(request.floor_id) orelse {
        return txn.sendError(pb.SpringTransferScRsp, .RET_MAZE_NO_FLOOR);
    };

    const floor_id = floor.FloorID;
    const entity_ref = txn.modules.scene.entity_manager.ref(request.prop_entity_id);

    var anchor_id: ?u32 = null;

    if (txn.assets.group.map.get(.{
        .floor_id = floor_id,
        .group_id = entity_ref.group_id,
    })) |group| if (group.PropList) |prop_list| {
        for (prop_list) |prop| {
            if (prop.ID == entity_ref.inst_id) {
                anchor_id = prop.AnchorID;

                break;
            }
        }
    };

    const resolved_anchor_id = anchor_id orelse
        return Scene.Error.InvalidSpring;

    for (floor.GroupList) |group_desc| {
        const group = txn.assets.group.map.get(.{
            .floor_id = floor_id,
            .group_id = group_desc.ID,
        }) orelse continue;

        const anchor_list = group.AnchorList orelse continue;

        for (anchor_list) |anchor| {
            if (anchor.ID != resolved_anchor_id) continue;

            txn.modules.scene.motion = .{
                .pos = .{
                    .v = .{
                        @intFromFloat(anchor.PosX * 1000),
                        @intFromFloat(anchor.PosY * 1000),
                        @intFromFloat(anchor.PosZ * 1000),
                    },
                },
                .rot = .{
                    .v = .{
                        0,
                        @intFromFloat(anchor.RotY * 1000),
                        0,
                    },
                },
            };

            try txn.notify(.scene_changed, .{});

            try txn.sendMessage(pb.SceneEntityMoveScNotify{
                .entity_id = txn.modules.lineup.list.items(.leader)[txn.modules.lineup.active_index.toInt()].toInt(),
                .motion = .{
                    .pos = txn.modules.scene.motion.pos.to(pb.Vector),
                    .rot = txn.modules.scene.motion.rot.to(pb.Vector),
                },
            });

            return txn.sendMessage(pb.SpringTransferScRsp.init);
        }
    }

    return Scene.Error.InvalidSpring;
}

// The treasure boxes won't be opened without this handler.
// However, some challenge's props still need to be handled manually.
pub fn onInteractPropCsReq(txn: Transaction, request: pb.InteractPropCsReq) !void {
    std.log.scoped(.interact_prop).debug("prop_entity_id: {}, interact_id: {}", request);

    const interact = txn.assets.tables.interact.map.get(@enumFromInt(request.interact_id)) orelse {
        return try txn.sendError(pb.InteractPropScRsp, .RET_INTERACT_CONFIG_NOT_EXIST);
    };

    try txn.sendMessage(pb.InteractPropScRsp{
        .prop_entity_id = request.prop_entity_id,
        .prop_state = interact.TargetState,
    });
}

// TODO: Implement this correctly
// I don't really know how to correctly handle this,
// but maybe the idea is to get the LevelGraph from the prop entity or quest,
// and depending on the triggers do one thing or the other,
// for example: "Config/Level/Maze/Chapter01/Town/Town_Chapter01_EntryFor1-1.json"
// contains a start task that is "EnterMap", then we should move the player to the target map.
pub fn onWaitCustomStringCsReq(txn: Transaction, request: pb.WaitCustomStringCsReq) !void {
    const log = std.log.scoped(.wait_custom_string);

    switch (request.key.?) {
        .prop_entity_id => |v| {
            log.debug("string: {s}, prop_entity_id: {}", .{
                request.custom_string,
                v,
            });
        },
        .sub_mission_id => |v| {
            log.debug("string: {s}, sub_mission_id: {}", .{
                request.custom_string,
                v,
            });
        },
    }

    try txn.sendMessage(pb.WaitCustomStringScRsp{
        .custom_string = request.custom_string,
        .key = if (request.key) |k| switch (k) {
            .prop_entity_id => |v| .{ .prop_entity_id = v },
            .sub_mission_id => |v| .{ .sub_mission_id = v },
        } else null,
    });
}

// TODO: implement battle buff
pub fn onSceneCastSkillCsReq(txn: Transaction, request: pb.SceneCastSkillCsReq) !void {
    try txn.modules.login.step.ensureExact(.finished);
    if (request.hit_target_entity_id_list.items.len == 0) return try txn.sendMessage(pb.SceneCastSkillScRsp{});

    const monster_entity_id_list = &txn.modules.battle.monster_entity_id_list;
    monster_entity_id_list.clearRetainingCapacity();

    if (request.cast_entity_id < 4) {
        for (request.hit_target_entity_id_list.items) |id| if (txn.modules.scene.entity_manager.kind(id).* == .monster) {
            try monster_entity_id_list.append(txn.gpa, id);
        };
    } else {
        try monster_entity_id_list.append(txn.gpa, request.cast_entity_id);
    }

    try monster_entity_id_list.appendSlice(txn.gpa, request.assist_monster_entity_id_list.items);
    if (monster_entity_id_list.items.len == 0) return try txn.sendMessage(pb.SceneCastSkillScRsp{});

    var stage_id_list: std.ArrayList(u32) = try .initCapacity(txn.arena, monster_entity_id_list.items.len);
    for (monster_entity_id_list.items) |monster_entity_id| {
        stage_id_list.addOneAssumeCapacity().* = txn.modules.scene.getMonsterStageID(
            txn.assets,
            monster_entity_id,
            txn.modules.player.world_level,
        ) orelse {
            return try txn.sendError(pb.SceneCastSkillScRsp, .RET_STAGE_CONFIG_NOT_EXIST);
        };
    }

    const lineup = &txn.modules.lineup;
    const avatar = &txn.modules.avatar;
    const inventory = &txn.modules.inventory;

    const avatar_slice = avatar.list.slice();
    const equipment_slice = inventory.equipment.slice();

    const index = try lineup.getRequestIndex(
        lineup.active_index.toInt(),
        @enumFromInt(@intFromBool(txn.modules.challenge.stage != .none)),
    );
    const slots = lineup.list.items(.slots)[index];

    var avatar_buf: [Lineup.Avatar.Slot.count]pb.BattleAvatar = undefined;
    var equipment_buf: [Lineup.Avatar.Slot.count]pb.BattleEquipment = undefined;

    var monster_id_list_buf = try txn.arena.alloc(u32, stage_id_list.items.len * Battle.max_monsters_per_wave);

    var avatar_list: std.ArrayList(pb.BattleAvatar) = .initBuffer(&avatar_buf);
    var wave_list: std.ArrayList(pb.SceneMonsterWave) = try .initCapacity(txn.arena, stage_id_list.items.len);

    for (stage_id_list.items, 0..) |stage_id, wave| {
        const stage = txn.assets.tables.stage.map.get(@enumFromInt(stage_id)) orelse continue;

        encoding.packSceneMonsterWave(
            wave_list.addOneAssumeCapacity(),
            monster_id_list_buf[wave * Battle.max_monsters_per_wave ..][0..Battle.max_monsters_per_wave],
            stage,
        );
    }

    for (slots.values, 0..) |maybe_avatar, i| if (maybe_avatar) |lineup_avatar| {
        const avatar_index = avatar.index.get(lineup_avatar.id) orelse continue;
        const battle_avatar = avatar_list.addOneAssumeCapacity();

        encoding.packBattleAvatar(
            battle_avatar,
            &equipment_buf,
            avatar_slice,
            equipment_slice,
            &avatar_index,
            &lineup_avatar,
            &inventory.equipment_index,
            @truncate(i),
        );
    };

    try txn.sendMessage(pb.SceneCastSkillScRsp{
        .battle_info = .{
            .logic_random_seed = @truncate(@as(u96, @bitCast(txn.time.toNanoseconds()))),
            .stage_id = stage_id_list.items[0],
            .monster_wave_list = wave_list,
            .battle_avatar_list = avatar_list,
        },
    });
}

const Battle = modules.Battle;
const Avatar = modules.Avatar;
const Inventory = modules.Inventory;
const Scene = modules.Scene;
const Lineup = modules.Lineup;
const Allocator = std.mem.Allocator;
const MapEntryRow = Assets.ExcelTables.MapEntryRow;

const Assets = @import("../Assets.zig");
const modules = @import("../modules.zig");
const encoding = @import("../encoding.zig");

const Transaction = @import("../requests.zig").Transaction;
const pb = @import("proto").pb;

const std = @import("std");
