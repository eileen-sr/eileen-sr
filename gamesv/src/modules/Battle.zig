monster_entity_id_list: std.ArrayList(u32),

pub const init: Battle = .{
    .monster_entity_id_list = .empty,
};

pub fn deinit(battle: *Battle, gpa: Allocator) void {
    battle.monster_entity_id_list.deinit(gpa);
}

pub const max_monsters_per_wave = 5;

const Allocator = std.mem.Allocator;

const std = @import("std");
const Battle = @This();
