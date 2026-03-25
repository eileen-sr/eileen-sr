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

    try txn.sendMessage(pb.GetCurSceneInfoScRsp{
        .scene = try packSceneInfo(
            txn.arena,
            txn.assets,
            entry,
            &txn.modules.scene.entity_list,
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
                        .x = @intFromFloat(anchor.PosX * 1000),
                        .y = @intFromFloat(anchor.PosY * 1000),
                        .z = @intFromFloat(anchor.PosZ * 1000),
                    },
                    .rot = .{
                        .y = @intFromFloat(anchor.RotY * 1000),
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
                    &txn.modules.scene.entity_list,
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
    try txn.modules.login.step.ensureExact(.finished);

    if (txn.modules.scene.entry_id == request.entry_id) {
        for (request.entity_motion_list.items) |item| if (item.entity_id < 4) if (item.motion) |motion| {
            txn.modules.scene.motion = .{
                .pos = .from(pb.Vector, motion.pos.?),
                .rot = .from(pb.Vector, motion.rot.?),
            };

            txn.modules.scene.entity_list.items(.motion)[item.entity_id] = txn.modules.scene.motion;

            try txn.notify(.scene_changed, .{});
        };
    }

    try txn.sendMessage(pb.SceneEntityMoveScRsp{});
}

fn packSceneInfo(
    arena: Allocator,
    assets: *const Assets,
    entry: *const MapEntryRow,
    entity_list: *const std.MultiArrayList(Scene.Entity),
    player_uid: Login.Uid,
) Allocator.Error!pb.SceneInfo {
    const slice = entity_list.slice();

    var entity_info_list = try std.ArrayList(pb.SceneEntityInfo)
        .initCapacity(arena, slice.len);

    for (0..slice.len) |i| {
        const out = entity_info_list.addOneAssumeCapacity();
        packEntity(out, slice, i, player_uid);
    }

    const floor = assets.floor.map.get(entry.FloorID).?;

    var lighten_section_list: std.ArrayList(u32) = .empty;

    if (floor.MinimapVolumeData.Sections) |sections| {
        for (sections) |section| {
            try lighten_section_list.append(arena, section.ID);
        }
    }

    return .{
        .entry_id = entry.EntryID.toInt(),
        .plane_id = entry.PlaneID,
        .floor_id = entry.FloorID,
        .entity_list = entity_info_list,
        .lighten_section_list = lighten_section_list,
    };
}

pub fn packEntity(
    out: *pb.SceneEntityInfo,
    slice: std.MultiArrayList(Scene.Entity).Slice,
    index: usize,
    player_uid: Login.Uid,
) void {
    out.* = .{
        .entity_id = slice.items(.id)[index],
        .motion = .{
            .pos = slice.items(.motion)[index].pos.to(pb.Vector),
            .rot = slice.items(.motion)[index].rot.to(pb.Vector),
        },
        .group_id = slice.items(.group_id)[index],
        .inst_id = slice.items(.inst_id)[index],
    };

    if (slice.items(.data)[index]) |data| switch (data) {
        .actor => |actor| {
            out.entity = .{
                .actor = .{
                    .uid = player_uid.toInt(),
                    .avatar_type = @enumFromInt(@intFromEnum(actor.type)),
                    .avatar_id = actor.avatar_id,
                },
            };
        },
        .monster => |monster| {
            out.entity = .{
                .npc_monster = .{
                    .monster_id = monster.monster_id,
                },
            };
        },
        .npc => |npc| {
            out.entity = .{
                .npc = .{
                    .npc_id = npc.npc_id,
                },
            };
        },
        .prop => |prop| {
            out.entity = .{
                .prop = .{
                    .prop_id = prop.prop_id,
                    .prop_state = @intFromEnum(prop.prop_state),
                    .create_time_ms = prop.create_time_ms,
                    .life_time_ms = prop.life_time_ms,
                },
            };
        },
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

pub fn onSpringTransferCsReq(txn: Transaction, request: pb.SpringTransferCsReq) !void {
    try txn.modules.login.step.ensureExact(.finished);

    const floor = txn.assets.floor.map.get(request.floor_id) orelse {
        return txn.sendError(pb.SpringTransferScRsp, .RET_MAZE_NO_FLOOR);
    };

    const floor_id = floor.FloorID;
    const entity_inst_id = txn.modules.scene.entity_list.items(.inst_id)[request.prop_entity_id];

    var anchor_id: ?u32 = null;

    outer: for (floor.GroupList) |group_desc| {
        const group = txn.assets.group.map.get(.{
            .floor_id = floor_id,
            .group_id = group_desc.ID,
        }) orelse continue;

        const prop_list = group.PropList orelse continue;

        for (prop_list) |prop| {
            if (prop.ID == entity_inst_id) {
                anchor_id = prop.AnchorID;
                break :outer;
            }
        }
    }

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
                    .x = @intFromFloat(anchor.PosX * 1000),
                    .y = @intFromFloat(anchor.PosY * 1000),
                    .z = @intFromFloat(anchor.PosZ * 1000),
                },
                .rot = .{
                    .y = @intFromFloat(anchor.RotY * 1000),
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

// TODO: When implemented the entity list
pub fn onInteractPropCsReq(txn: Transaction, request: pb.InteractPropCsReq) !void {
    try txn.sendMessage(pb.InteractPropScRsp{
        .prop_entity_id = request.prop_entity_id,
        .prop_state = 1,
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
