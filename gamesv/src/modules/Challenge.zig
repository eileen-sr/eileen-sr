map: HashMap(ChallengeMazeConfigRow.ID, Stars),
challenge_id: ChallengeMazeConfigRow.ID,
stage: Stage,
round_cnt: u32,

pub const init: Challenge = .{
    .map = .empty,
    .challenge_id = @enumFromInt(0),
    .stage = .none,
    .round_cnt = 0,
};

pub const Stage = enum {
    none,
    low,
    high,
};

pub const Stars = std.bit_set.IntegerBitSet(3);

pub fn deinit(challenge: *Challenge, gpa: Allocator) void {
    challenge.map.deinit(gpa);
}

const HashMap = std.AutoArrayHashMapUnmanaged;
const Allocator = std.mem.Allocator;

const ChallengeMazeConfigRow = Assets.ExcelTables.ChallengeMazeConfigRow;
const Assets = @import("../Assets.zig");

const std = @import("std");
const Challenge = @This();
