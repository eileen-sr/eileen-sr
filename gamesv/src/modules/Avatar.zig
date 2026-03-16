index: HashMap(AvatarRow.ID, Index),
list: MultiArrayList(Data),

pub const init: Avatar = .{
    .index = .empty,
    .list = .empty,
};

pub const Data = struct {
    avatar_id: AvatarRow.ID,
    exp: u32 = 0,
    level: Level = .max,
    promotion: Promotion = .max,
    rank: Rank = .max,
    equipment_unique_id: EquipmentUniqueId = .none,
};

pub const Index = enum(u32) {
    _,

    pub fn fromInt(int: u32) Index {
        return @enumFromInt(int);
    }

    pub fn toInt(index: Index) u32 {
        return @intFromEnum(index);
    }
};

pub fn deinit(avatar: *Avatar, gpa: Allocator) void {
    avatar.index.deinit(gpa);
    avatar.list.deinit(gpa);
}

pub fn add(avatar: *Avatar, gpa: Allocator, data: Data) Allocator.Error!Index {
    if (avatar.index.get(data.avatar_id)) |index|
        return index;

    const index: Index = .fromInt(@truncate(avatar.list.len));
    try avatar.list.append(gpa, data);
    errdefer avatar.list.swapRemove(index.toInt());

    try avatar.index.put(gpa, data.avatar_id, index);
    return index;
}

pub fn reindex(avatar: *Avatar, gpa: Allocator) Allocator.Error!void {
    avatar.index.clearRetainingCapacity();
    try avatar.index.ensureTotalCapacity(gpa, avatar.list.len);

    for (avatar.list.items(.avatar_id), 0..) |id, index| {
        avatar.index.putAssumeCapacity(id, .fromInt(@truncate(index)));
    }
}

pub const EquipmentUniqueId = enum(u32) {
    none = 0,
    _,

    pub fn toInt(euid: EquipmentUniqueId) u32 {
        return @intFromEnum(euid);
    }

    pub fn fromInt(int: u32) EquipmentUniqueId {
        return @enumFromInt(int);
    }
};

pub const Level = enum(u8) {
    min = 1,
    max = 80,
    _,

    pub fn toInt(level: Level) u8 {
        return @intFromEnum(level);
    }

    pub fn fromInt(int: u8) Level {
        debug.assert(int != 0);
        return @enumFromInt(@min(@intFromEnum(Level.max), int));
    }
};

pub const Promotion = enum(u8) {
    min = 0,
    max = 5,
    _,

    pub fn toInt(promotion: Promotion) u32 {
        return @intFromEnum(promotion);
    }

    pub fn fromInt(int: u8) Promotion {
        return @enumFromInt(@min(@intFromEnum(Promotion.max), int));
    }
};

pub const Rank = enum(u8) {
    none = 0,
    max = 6,
    _,

    pub fn toInt(rank: Rank) u32 {
        return @intFromEnum(rank);
    }

    pub fn fromInt(int: u8) Rank {
        return @enumFromInt(@min(@intFromEnum(Rank.max), int));
    }
};

const HashMap = std.AutoArrayHashMapUnmanaged;
const MultiArrayList = std.MultiArrayList;
const Allocator = std.mem.Allocator;

const AvatarRow = Assets.ExcelTables.AvatarRow;
const Assets = @import("../Assets.zig");

const debug = std.debug;
const std = @import("std");
const Avatar = @This();
