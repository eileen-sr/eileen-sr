pub fn packSceneInfo(
    out: *pb.SceneInfo,
    arena: Allocator,
    assets: *const Assets,
    entry: *const MapEntryRow,
    entity_manager: *const Scene.EntityManager,
    player_uid: Login.Uid,
) Allocator.Error!void {
    const slice = entity_manager.entities.slice();

    var entity_info_list = try ArrayList(pb.SceneEntityInfo)
        .initCapacity(arena, entity_manager.active_count);

    var it = entity_manager.iterator();
    while (it.next()) |id| {
        packSceneEntityInfo(entity_info_list.addOneAssumeCapacity(), slice, id, player_uid);
    }

    const floor = assets.floor.map.get(entry.FloorID).?;

    var lighten_section_list: ArrayList(u32) = .empty;

    if (floor.MinimapVolumeData.Sections) |sections| {
        try lighten_section_list.ensureTotalCapacityPrecise(arena, sections.len);

        for (sections) |section| {
            lighten_section_list.appendAssumeCapacity(section.ID);
        }
    }

    out.* = .{
        .entry_id = entry.EntryID.toInt(),
        .plane_id = entry.PlaneID,
        .floor_id = entry.FloorID,
        .entity_list = entity_info_list,
        .lighten_section_list = lighten_section_list,
    };
}

pub fn packSceneEntityInfo(
    out: *pb.SceneEntityInfo,
    slice: MultiArrayList(Scene.Entity).Slice,
    id: u32,
    player_uid: Login.Uid,
) void {
    out.* = .{
        .entity_id = id,
        .motion = .{
            .pos = slice.items(.motion)[id].pos.to(pb.Vector),
            .rot = slice.items(.motion)[id].rot.to(pb.Vector),
        },
        .group_id = slice.items(.ref)[id].group_id,
        .inst_id = slice.items(.ref)[id].inst_id,
    };

    switch (slice.items(.kind)[id]) {
        .avatar => {
            out.entity = .{
                .actor = .{
                    .uid = player_uid.toInt(),
                    .avatar_type = @enumFromInt(slice.items(.kind_data)[id]),
                    .avatar_id = slice.items(.config_id)[id],
                },
            };
        },
        .monster => {
            out.entity = .{
                .npc_monster = .{
                    .monster_id = slice.items(.config_id)[id],
                },
            };
        },
        .npc => {
            out.entity = .{
                .npc = .{
                    .npc_id = slice.items(.config_id)[id],
                },
            };
        },
        .prop => {
            out.entity = .{
                .prop = .{
                    .prop_id = slice.items(.config_id)[id],
                    .prop_state = slice.items(.kind_data)[id],
                    .create_time_ms = 0,
                    .life_time_ms = 0,
                },
            };
        },
    }
}

pub fn packLineupInfo(
    out: *pb.LineupInfo,
    avatar_buf: *[Lineup.Avatar.Slot.count]pb.LineupAvatar,
    slice: MultiArrayList(Lineup.Data).Slice,
    mp: Lineup.Mp,
    index: u32,
) void {
    var avatar_list: ArrayList(pb.LineupAvatar) = .initBuffer(avatar_buf);

    for (slice.items(.slots)[index].values, 0..) |maybe_avatar, slot| if (maybe_avatar) |*avatar| {
        packLineupAvatar(avatar_list.addOneAssumeCapacity(), avatar, @truncate(slot));
    };

    out.* = .{
        .avatar_list = avatar_list,
        .mp = mp.toInt(),
        .name = slice.items(.name)[index].view(),
        .is_virtual = slice.items(.flags)[index].virtual,
        .leader_slot = slice.items(.leader)[index].toInt(),
        .index = index,
        .extra_lineup_type = if (slice.items(.flags)[index].challenge) .LINEUP_CHALLENGE else .LINEUP_NONE,
    };
}

pub fn packLineupAvatar(out: *pb.LineupAvatar, avatar: *const Lineup.Avatar, slot: u32) void {
    out.* = .{
        .slot = slot,
        .id = avatar.id.toInt(),
        .hp = avatar.hp.toInt(),
        .sp = avatar.sp.toInt(),
        .satiety = avatar.satiety.toInt(),
        .avatar_type = .AVATAR_FORMAL_TYPE,
    };
}

pub fn packSceneMonsterWave(
    out: *pb.SceneMonsterWave,
    monster_id_list_buf: *[Battle.max_monsters_per_wave]u32,
    stage: *const StageRow,
) void {
    var monster_id_list: std.ArrayList(u32) = .initBuffer(monster_id_list_buf);
    inline for (0..monster_id_list_buf.len) |i| {
        const id = @field(stage.MonsterList[0], std.fmt.comptimePrint("Monster{d}", .{i}));
        if (id != 0) monster_id_list.appendAssumeCapacity(id);
    }

    out.* = .{ .monster_id_list = monster_id_list };
}

pub fn packBattleAvatar(
    out: *pb.BattleAvatar,
    equipment_buf: *[Lineup.Avatar.Slot.count]pb.BattleEquipment,
    avatar_slice: MultiArrayList(Avatar.Data).Slice,
    equipment_slice: MultiArrayList(Inventory.Equipment).Slice,
    avatar_index: *const Avatar.Index,
    lineup_avatar: *const Lineup.Avatar,
    equipment_index_map: *const HashMap(Inventory.Equipment.UniqueID, u32),
    slot: u32,
) void {
    out.* = .{
        .index = slot,
        .avatar_type = .AVATAR_FORMAL_TYPE,
        .id = lineup_avatar.id.toInt(),
        .level = avatar_slice.items(.level)[avatar_index.toInt()].toInt(),
        .rank = avatar_slice.items(.rank)[avatar_index.toInt()].toInt(),
        .hp = lineup_avatar.hp.toInt(),
        .sp = lineup_avatar.sp.toInt(),
        .promotion = avatar_slice.items(.promotion)[avatar_index.toInt()].toInt(),
        .equipment_list = .initBuffer(equipment_buf[slot .. slot + 1]),
        .skilltree_list = .empty,
    };

    const equipment_unique_id = avatar_slice.items(.equipment_unique_id)[avatar_index.toInt()];
    if (equipment_unique_id == .none) return;

    const equipment_index = equipment_index_map.get(
        @enumFromInt(@intFromEnum(equipment_unique_id)),
    ) orelse return;

    out.equipment_list.appendAssumeCapacity(.{
        .id = equipment_slice.items(.id)[equipment_index].toInt(),
        .level = equipment_slice.items(.level)[equipment_index].toInt(),
        .promotion = equipment_slice.items(.promotion)[equipment_index].toInt(),
        .rank = equipment_slice.items(.rank)[equipment_index].toInt(),
    });
}

const Battle = modules.Battle;
const Lineup = modules.Lineup;
const Login = modules.Login;
const Scene = modules.Scene;
const Avatar = modules.Avatar;
const Inventory = modules.Inventory;
const modules = @import("modules.zig");

const StageRow = Assets.ExcelTables.StageRow;
const MapEntryRow = Assets.ExcelTables.MapEntryRow;
const Assets = @import("Assets.zig");

const Transaction = @import("requests.zig").Transaction;
const pb = @import("proto").pb;

const ArrayList = std.ArrayList;
const MultiArrayList = std.MultiArrayList;
const HashMap = std.AutoArrayHashMapUnmanaged;
const Allocator = std.mem.Allocator;

const std = @import("std");
