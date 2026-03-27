pub const Error = error{InvalidSpring};

entry_id: u32,
motion: Motion,
entity_list: std.MultiArrayList(Entity),

pub const init: Scene = .{
    .entry_id = 0,
    .motion = .{},
    .entity_list = .empty,
};

pub const Motion = struct {
    pos: Vector(i32) = .{},
    rot: Vector(i32) = .{},
};

pub fn Vector(comptime T: type) type {
    return struct {
        x: T = 0,
        y: T = 0,
        z: T = 0,

        pub fn from(comptime S: type, s: S) Vector(T) {
            return .{ .x = s.x, .y = s.y, .z = s.z };
        }

        pub fn to(t: Vector(T), comptime S: type) S {
            return .{ .x = t.x, .y = t.y, .z = t.z };
        }
    };
}

pub const Entity = struct {
    id: u32 = 0,
    motion: Motion = .{},
    group_id: u32 = 0,
    inst_id: u32 = 0,
    data: ?union(enum) {
        actor: ActorEntityData,
        monster: MonsterEntityData,
        npc: NpcEntityData,
        prop: PropEntityData,
    } = null,
};

pub const ActorEntityData = struct {
    type: AvatarType = .None,
    avatar_id: u32 = 0,
};

pub const MonsterEntityData = struct {
    monster_id: u32 = 0,
};

pub const NpcEntityData = struct {
    npc_id: u32 = 0,
};

pub const PropEntityData = struct {
    prop_id: u32 = 0,
    prop_state: Assets.ExcelTables.PropRow.State = .Closed,
    create_time_ms: u64 = 0,
    life_time_ms: u32 = 0,
};

pub const AvatarType = enum(i32) {
    None = 0,
    Trial = 1,
    Limit = 2,
    Formal = 3,
};

pub fn getStartMotion(
    assets: *const Assets,
    floor_id: u32,
) ?Motion {
    const floor = assets.floor.map.get(floor_id).?;

    const group = assets.group.map.get(.{
        .floor_id = floor_id,
        .group_id = floor.StartGroupID,
    }).?;

    for (group.AnchorList.?) |anchor| if (anchor.ID == floor.StartAnchorID) {
        return .{
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

    return null;
}

pub fn enterScene(
    scene: *Scene,
    gpa: Allocator,
    assets: *const Assets,
    entry: *const MapEntryRow,
    motion: ?Motion,
    avatars: *std.EnumArray(Lineup.Avatar.Slot, ?Lineup.Avatar),
) Allocator.Error!void {
    const floor = assets.floor.map.get(entry.FloorID).?;

    scene.motion = motion orelse
        getStartMotion(assets, entry.FloorID).?;
    scene.entry_id = @intFromEnum(entry.EntryID);
    scene.entity_list.clearRetainingCapacity();

    var i: usize = 0;
    while (i < 4) : (i += 1) {
        try scene.entity_list.append(gpa, .{
            .id = @truncate(i),
            .motion = scene.motion,
        });
    }

    scene.syncAvatars(avatars);

    for (floor.GroupList) |group_desc| {
        const group = assets.group.map.get(.{
            .floor_id = entry.FloorID,
            .group_id = group_desc.ID,
        }) orelse continue;

        if (group.PropList) |prop_list| {
            for (prop_list) |prop| if (prop.CreateOnInitial) {
                const prop_row = assets.tables.prop.map.get(@enumFromInt(prop.PropID)) orelse continue;

                // We want all doors, gates and exits to be opened by default
                const is_door = std.mem.find(u8, prop_row.PrefabPath, "Door") != null or
                    std.mem.find(u8, prop_row.InitLevelGraph, "Door") != null;
                const is_gate = std.mem.find(u8, prop_row.PrefabPath, "Gate") != null or
                    std.mem.find(u8, prop_row.InitLevelGraph, "Gate") != null;
                const is_exit = if (prop.InitLevelGraph) |g| std.mem.find(u8, g, "_Exit.") != null else false;
                const is_area_block = if (prop.InitLevelGraph) |g| std.mem.find(u8, g, "_AreaBlock_") != null else false;

                try scene.entity_list.append(gpa, .{
                    .id = @truncate(scene.entity_list.len),
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
                    .data = .{
                        .prop = .{
                            .prop_id = prop.PropID,
                            .prop_state = if (!is_door and !is_gate and !is_exit and !is_area_block)
                                if (prop_row.PropType == .PROP_SPRING)
                                    .CheckPointEnable
                                else
                                    prop.State
                            else
                                .Open,
                        },
                    },
                });
            };
        }

        if (group.NPCList) |npc_list| {
            for (npc_list) |npc| if (npc.CreateOnInitial) {
                _ = assets.tables.npc.map.get(@enumFromInt(npc.NPCID)) orelse continue;

                try scene.entity_list.append(gpa, .{
                    .id = @truncate(scene.entity_list.len),
                    .motion = .{
                        .pos = .{
                            .x = @intFromFloat(npc.PosX * 1000),
                            .y = @intFromFloat(npc.PosY * 1000),
                            .z = @intFromFloat(npc.PosZ * 1000),
                        },
                        .rot = .{
                            .y = @intFromFloat(npc.RotY * 1000),
                        },
                    },
                    .group_id = group_desc.ID,
                    .inst_id = npc.ID,
                    .data = .{
                        .npc = .{
                            .npc_id = npc.NPCID,
                        },
                    },
                });
            };
        }

        if (group.MonsterList) |monster_list| {
            for (monster_list) |monster| if (monster.CreateOnInitial) {
                if (assets.tables.npc.map.get(@enumFromInt(monster.NPCMonsterID)) == null) {
                    continue;
                }

                try scene.entity_list.append(gpa, .{
                    .id = @truncate(scene.entity_list.len),
                    .motion = .{
                        .pos = .{
                            .x = @intFromFloat(monster.PosX * 1000),
                            .y = @intFromFloat(monster.PosY * 1000),
                            .z = @intFromFloat(monster.PosZ * 1000),
                        },
                        .rot = .{
                            .y = @intFromFloat(monster.RotY * 1000),
                        },
                    },
                    .group_id = group_desc.ID,
                    .inst_id = monster.ID,
                    .data = .{
                        .monster = .{
                            .monster_id = monster.NPCMonsterID,
                        },
                    },
                });
            };
        }
    }
}

pub fn syncAvatars(
    scene: *Scene,
    avatars: *const std.EnumArray(Lineup.Avatar.Slot, ?Lineup.Avatar),
) void {
    var i: u8 = 0;
    while (i < Lineup.Avatar.Slot.count) : (i += 1) {
        scene.entity_list.items(.motion)[i] = scene.motion;
        scene.entity_list.items(.data)[i] =
            if (avatars.get(@as(Lineup.Avatar.Slot, @enumFromInt(i)))) |avatar| .{
                .actor = .{
                    .avatar_id = avatar.id.toInt(),
                    .type = .Formal,
                },
            } else null;
    }
}

pub fn deinit(scene: *Scene, gpa: Allocator) void {
    scene.entity_list.deinit(gpa);
}

const MapEntryRow = Assets.ExcelTables.MapEntryRow;
const Allocator = std.mem.Allocator;

const pb = @import("proto").pb;

const Login = @import("./Login.zig");
const Lineup = @import("./Lineup.zig");
const Assets = @import("../Assets.zig");
const std = @import("std");

const Scene = @This();
