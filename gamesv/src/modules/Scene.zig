pub const Error = error{ InvalidSpring, EntityIdNotFound, InvalidEntityKind };

entry_id: u32,
motion: Motion,
entity_manager: EntityManager,

pub const init: Scene = .{
    .entry_id = 0,
    .motion = .{},
    .entity_manager = .init,
};

pub fn Vector(comptime T: type) type {
    const V = @Vector(3, T);

    return struct {
        v: V = @splat(0),

        const Self = @This();

        pub const init: Self = .{};

        pub fn from(s: anytype) Self {
            return .{
                .v = .{
                    s.x,
                    s.y,
                    s.z,
                },
            };
        }

        pub fn to(self: Self, comptime S: type) S {
            return .{
                .x = self.v[0],
                .y = self.v[1],
                .z = self.v[2],
            };
        }
    };
}

pub const Motion = struct {
    pos: Vector(i32) = .{},
    rot: Vector(i32) = .{},
};

pub const OptionalIndex = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn fromIndex(i: usize) OptionalIndex {
        std.debug.assert(i <= std.math.maxInt(u32));
        return @enumFromInt(@as(u32, @intCast(i)));
    }

    pub fn toIndex(self: OptionalIndex) usize {
        std.debug.assert(self != .none);
        return @intCast(@intFromEnum(self));
    }
};

pub const RefId = packed struct(u32) {
    group_id: u8 = 0,
    inst_id: u24 = 0,
};

pub const EntityKind = enum(u2) {
    avatar,
    monster,
    npc,
    prop,
};

pub const AvatarType = enum(u2) {
    None,
    Trial,
    Limit,
    Formal,
};

pub const Entity = struct {
    kind: EntityKind,
    kind_data: u32 = 0,

    config_id: u32 = 0,

    ref: RefId = .{},

    motion: Motion = .{},

    next: OptionalIndex = .none,
    prev: OptionalIndex = .none,
};

pub const EntityManager = struct {
    entities: std.MultiArrayList(Entity) = .{},

    active_head: OptionalIndex = .none,
    active_tail: OptionalIndex = .none,
    inactive_head: OptionalIndex = .none,

    active_count: u32 = 0,

    const Self = @This();

    // Iteration

    pub const Iterator = struct {
        manager: *const Self,
        current: OptionalIndex,

        pub fn next(it: *Iterator) ?u32 {
            const slot = it.current;
            if (slot == .none) return null;

            const idx = slot.toIndex();
            it.current = it.manager.entities.items(.next)[idx];

            return @intCast(idx);
        }
    };

    pub fn iterator(self: *const Self) Iterator {
        return .{
            .manager = self,
            .current = self.active_head,
        };
    }

    // Lifecycle

    pub const init: Self = .{};

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.entities.deinit(allocator);
    }

    pub fn reset(self: *Self) void {
        self.entities.clearRetainingCapacity();

        self.active_head = .none;
        self.active_tail = .none;
        self.inactive_head = .none;

        self.active_count = 0;
    }

    // Internal

    fn linkActiveTail(self: *Self, idx: usize) void {
        const slot = OptionalIndex.fromIndex(idx);
        const next = self.entities.items(.next);
        const prev = self.entities.items(.prev);

        next[idx] = .none;
        prev[idx] = self.active_tail;

        if (self.active_tail != .none) {
            next[self.active_tail.toIndex()] = slot;
        } else {
            self.active_head = slot;
        }

        self.active_tail = slot;
    }

    fn unlinkActive(self: *Self, idx: usize) void {
        const next = self.entities.items(.next);
        const prev = self.entities.items(.prev);

        const prev_slot = prev[idx];
        const next_slot = next[idx];

        if (prev_slot != .none) {
            next[prev_slot.toIndex()] = next_slot;
        } else {
            self.active_head = next_slot;
        }

        if (next_slot != .none) {
            prev[next_slot.toIndex()] = prev_slot;
        } else {
            self.active_tail = prev_slot;
        }

        next[idx] = .none;
        prev[idx] = .none;
    }

    fn pushInactive(self: *Self, idx: usize) void {
        const next = self.entities.items(.next);

        next[idx] = self.inactive_head;
        self.inactive_head = OptionalIndex.fromIndex(idx);
    }

    fn popInactive(self: *Self) ?usize {
        if (self.inactive_head == .none) return null;

        const idx = self.inactive_head.toIndex();
        self.inactive_head = self.entities.items(.next)[idx];

        return idx;
    }

    // Public API

    pub fn create(self: *Self, allocator: Allocator, entity: Entity) !u32 {
        var e = entity;

        e.next = .none;
        e.prev = .none;

        if (self.popInactive()) |idx| {
            self.entities.set(idx, e);
            self.linkActiveTail(idx);

            return @intCast(idx);
        }

        try self.entities.append(allocator, e);

        const idx = self.entities.len - 1;
        self.linkActiveTail(idx);

        self.active_count += 1;

        return @intCast(idx);
    }

    pub fn remove(self: *Self, id: u32) void {
        const idx: usize = @intCast(id);

        self.unlinkActive(idx);
        self.pushInactive(idx);

        self.active_count -= 1;
    }

    pub fn isActive(self: *const Self, id: u32) bool {
        var it = self.iterator();
        while (it.next()) |cur| {
            if (cur == id) return true;
        }

        return false;
    }

    pub fn find(self: *const Self, args: anytype) Error!u32 {
        const slice = self.entities.slice();

        var it = self.iterator();
        _: while (it.next()) |id| {
            inline for (std.meta.fields(@TypeOf(args))) |f| {
                if (slice.items(std.meta.stringToEnum(std.meta.FieldEnum(Entity), f.name).?)[id] != @field(args, f.name)) continue :_;
            }
            return id;
        }
        return error.EntityIdNotFound;
    }

    // Entity fields

    pub fn kind(self: *const Self, id: u32) *EntityKind {
        return &self.entities.items(.kind)[id];
    }

    pub fn kindData(self: *const Self, id: u32) *u32 {
        return &self.entities.items(.kind_data)[id];
    }

    pub fn configId(self: *const Self, id: u32) *u32 {
        return &self.entities.items(.config_id)[id];
    }

    pub fn ref(self: *const Self, id: u32) *RefId {
        return &self.entities.items(.ref)[id];
    }

    pub fn motion(self: *const Self, id: u32) *Motion {
        return &self.entities.items(.motion)[id];
    }
};

pub fn getStartMotion(
    assets: *const Assets,
    floor_id: u32,
) ?Motion {
    const floor = assets.floor.map.get(floor_id) orelse return null;

    const group = assets.group.map.get(.{
        .floor_id = floor_id,
        .group_id = floor.StartGroupID,
    }) orelse return null;

    for (group.AnchorList.?) |anchor| if (anchor.ID == floor.StartAnchorID) {
        return .{ .pos = .{
            .v = .{
                @intFromFloat(anchor.PosX * 1000),
                @intFromFloat(anchor.PosY * 1000),
                @intFromFloat(anchor.PosZ * 1000),
            },
        }, .rot = .{
            .v = .{
                0,
                @intFromFloat(anchor.RotY * 1000),
                0,
            },
        } };
    };

    return null;
}

pub fn getMonsterStageID(
    scene: *const Scene,
    assets: *const Assets,
    monster_entity_id: u32,
    world_level: Player.WorldLevel,
) ?u32 {
    if (scene.entity_manager.kind(monster_entity_id).* != .monster) return null;

    const event = assets.tables.getPlaneEventRow(
        scene.entity_manager.kindData(monster_entity_id).*,
        world_level.toInt(),
    ) orelse return null;

    return event.StageID;
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
    scene.entity_manager.reset();

    var i: usize = 0;
    while (i < Lineup.Avatar.Slot.count) : (i += 1) {
        _ = try scene.entity_manager.create(gpa, .{
            .kind = .avatar,
            .kind_data = @intFromEnum(AvatarType.Formal),
            .ref = .{},
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

                _ = try scene.entity_manager.create(gpa, .{
                    .kind = .prop,
                    .kind_data = PropState.toInt((if (!is_door and !is_gate and !is_exit and !is_area_block)
                        if (prop_row.PropType == .PROP_SPRING)
                            .CheckPointEnable
                        else
                            prop.State
                    else
                        .Open)),
                    .config_id = prop.PropID,
                    .ref = .{
                        .group_id = @intCast(group_desc.ID),
                        .inst_id = @intCast(prop.ID),
                    },
                    .motion = .{
                        .pos = .{
                            .v = .{
                                @intFromFloat(prop.PosX * 1000),
                                @intFromFloat(prop.PosY * 1000),
                                @intFromFloat(prop.PosZ * 1000),
                            },
                        },
                        .rot = .{
                            .v = .{
                                @intFromFloat(prop.RotX * 1000),
                                @intFromFloat(prop.RotY * 1000),
                                @intFromFloat(prop.RotZ * 1000),
                            },
                        },
                    },
                });
            };
        }

        if (group.NPCList) |npc_list| {
            for (npc_list) |npc| if (npc.CreateOnInitial) {
                _ = assets.tables.npc.map.get(@enumFromInt(npc.NPCID)) orelse continue;

                _ = try scene.entity_manager.create(gpa, .{
                    .kind = .npc,
                    .config_id = npc.NPCID,
                    .ref = .{
                        .group_id = @intCast(group_desc.ID),
                        .inst_id = @intCast(npc.ID),
                    },
                    .motion = .{
                        .pos = .{
                            .v = .{
                                @intFromFloat(npc.PosX * 1000),
                                @intFromFloat(npc.PosY * 1000),
                                @intFromFloat(npc.PosZ * 1000),
                            },
                        },
                        .rot = .{
                            .v = .{
                                0,
                                @intFromFloat(npc.RotY * 1000),
                                0,
                            },
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

                _ = try scene.entity_manager.create(gpa, .{
                    .kind = .monster,
                    .kind_data = monster.EventID, // for stages
                    .config_id = monster.NPCMonsterID,
                    .ref = .{
                        .group_id = @intCast(group_desc.ID),
                        .inst_id = @intCast(monster.ID),
                    },
                    .motion = .{
                        .pos = .{
                            .v = .{
                                @intFromFloat(monster.PosX * 1000),
                                @intFromFloat(monster.PosY * 1000),
                                @intFromFloat(monster.PosZ * 1000),
                            },
                        },
                        .rot = .{
                            .v = .{
                                0,
                                @intFromFloat(monster.RotY * 1000),
                                0,
                            },
                        },
                    },
                });
            };
        }
    }
}

pub fn destroyEntities(
    scene: *Scene,
    txn: *const Transaction,
    ids: []const u32,
) !void {
    var entity_id_list: std.ArrayList(u32) = try .initCapacity(txn.arena, ids.len);
    entity_id_list.appendSliceAssumeCapacity(ids);

    for (ids) |id| scene.entity_manager.remove(id);

    try txn.sendMessage(pb.SceneEntityDisappearScNotify{
        .entity_id_list = entity_id_list,
    });
}

pub fn updatePropState(
    scene: *Scene,
    txn: *const Transaction,
    prop_entity_id: u32,
    prop_state: PropState,
) !void {
    const entity_manager = &scene.entity_manager;

    if (entity_manager.kind(prop_entity_id).* != .prop) return error.InvalidEntityKind;
    entity_manager.kindData(prop_entity_id).* = prop_state.toInt();

    var entity_list_buf: [1]pb.SceneEntityInfo = undefined;
    var entity_list: std.ArrayList(pb.SceneEntityInfo) = .initBuffer(&entity_list_buf);

    entity_list.appendAssumeCapacity(.{
        .entity_id = prop_entity_id,
        .motion = .{
            .pos = entity_manager.motion(prop_entity_id).pos.to(pb.Vector),
            .rot = entity_manager.motion(prop_entity_id).rot.to(pb.Vector),
        },
        .group_id = entity_manager.ref(prop_entity_id).group_id,
        .inst_id = entity_manager.ref(prop_entity_id).inst_id,
        .entity = .{
            .prop = .{
                .prop_id = entity_manager.configId(prop_entity_id).*,
                .prop_state = entity_manager.kindData(prop_entity_id).*,
            },
        },
    });

    try txn.sendMessage(pb.SceneEntityUpdateScNotify{
        .entity_list = entity_list,
    });
}

pub fn syncAvatars(
    scene: *Scene,
    avatars: *const std.EnumArray(Lineup.Avatar.Slot, ?Lineup.Avatar),
) void {
    var i: u8 = 0;
    while (i < Lineup.Avatar.Slot.count) : (i += 1) {
        scene.entity_manager.motion(i).* = scene.motion;
        scene.entity_manager.configId(i).* = if (avatars.get(@enumFromInt(i))) |avatar| avatar.id.toInt() else 0;
    }
}

pub fn deinit(scene: *Scene, gpa: Allocator) void {
    scene.entity_manager.deinit(gpa);
}

pub const Saveable = struct {
    entry_id: u32,
    motion: Motion,
};

const MapEntryRow = Assets.ExcelTables.MapEntryRow;
const PropState = Assets.ExcelTables.PropRow.State;
const Allocator = std.mem.Allocator;

const pb = @import("proto").pb;
const Transaction = @import("../requests.zig").Transaction;

const Player = @import("./Player.zig");
const Lineup = @import("./Lineup.zig");
const Assets = @import("../Assets.zig");

const std = @import("std");

const Scene = @This();
