pub const Error = Material.UseError;

material_map: HashMap(ItemRow.ID, Material),
equipment_index: HashMap(Equipment.UniqueID, u32),
equipment: MultiArrayList(Equipment),
unique_id_counter: u32,

pub const init: Inventory = .{
    .material_map = .empty,
    .equipment_index = .empty,
    .equipment = .empty,
    .unique_id_counter = 1,
};

pub fn deinit(inventory: *Inventory, gpa: Allocator) void {
    inventory.material_map.deinit(gpa);
    inventory.equipment_index.deinit(gpa);
    inventory.equipment.deinit(gpa);
}

pub fn addEquipment(inventory: *Inventory, gpa: Allocator, id: EquipmentRow.ID) Allocator.Error!Equipment.UniqueID {
    const unique_id: Equipment.UniqueID = .fromInt(inventory.unique_id_counter);

    try inventory.equipment.append(gpa, .{
        .id = id,
        .unique_id = unique_id,
    });

    inventory.unique_id_counter += 1;

    try inventory.equipment_index.put(
        gpa,
        unique_id,
        @truncate(inventory.equipment.len - 1),
    );

    return unique_id;
}

pub fn addMaterial(inventory: *Inventory, gpa: Allocator, id: ItemRow.ID, amount: u32) Allocator.Error!Material {
    const prev = inventory.material_map.get(id) orelse .zero;
    const new = prev.add(amount);

    try inventory.material_map.put(gpa, id, new);
    return new;
}

pub fn reindex(inventory: *Inventory, gpa: Allocator) Allocator.Error!void {
    inventory.equipment_index.clearRetainingCapacity();
    try inventory.equipment_index.ensureTotalCapacity(gpa, inventory.equipment.len);

    for (inventory.equipment.items(.unique_id), 0..) |unique_id, index| {
        inventory.equipment_index.putAssumeCapacity(unique_id, @truncate(index));
    }
}

pub const Material = enum(u32) {
    zero = 0,
    limit = 99999,
    _,

    pub const UseError = error{
        NotEnoughMaterial,
    };

    pub fn toInt(material: Material) u32 {
        return @intFromEnum(material);
    }

    pub fn fromInt(int: u32) Material {
        return @min(@intFromEnum(Material.limit), int);
    }

    pub fn add(material: Material, amount: u32) Material {
        return .fromInt(material.toInt() + amount);
    }

    pub fn use(material: Material, amount: u32) UseError!Material {
        if (material.toInt() < amount) return error.NotEnoughMaterial;
        return .fromInt(material.toInt() - amount);
    }
};

pub const Equipment = struct {
    id: EquipmentRow.ID,
    unique_id: UniqueID,
    level: Level = .max,
    exp: u32 = 0,
    rank: Rank = .max,
    belong_avatar_id: BelongAvatarID = .none,
    protection: Protection = .none,
    promotion: Promotion = .max,

    pub const UniqueID = enum(u32) {
        none = 0,
        _,

        pub fn fromInt(int: u32) UniqueID {
            return @enumFromInt(int);
        }

        pub fn toInt(uid: UniqueID) u32 {
            return @intFromEnum(uid);
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

    pub const Rank = enum(u8) {
        none = 0,
        max = 5,
        _,

        pub fn toInt(rank: Rank) u32 {
            return @intFromEnum(rank);
        }

        pub fn fromInt(int: u8) Rank {
            return @enumFromInt(@min(@intFromEnum(Rank.max), int));
        }
    };

    pub const BelongAvatarID = enum(u32) {
        none = 0,
        _,

        pub fn fromRowID(id: AvatarRow.ID) BelongAvatarID {
            return @enumFromInt(@intFromEnum(id));
        }

        pub fn toInt(id: BelongAvatarID) u32 {
            return @intFromEnum(id);
        }
    };

    pub const Protection = enum {
        none,
        protected,
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
};

const ItemRow = Assets.ExcelTables.ItemRow;
const AvatarRow = Assets.ExcelTables.AvatarRow;
const EquipmentRow = Assets.ExcelTables.EquipmentRow;
const Assets = @import("../Assets.zig");

const HashMap = std.AutoArrayHashMapUnmanaged;
const MultiArrayList = std.MultiArrayList;
const Allocator = std.mem.Allocator;

const debug = std.debug;
const std = @import("std");
const Inventory = @This();
