pub const Error = Avatar.Slot.Error || Mp.Error;

list: MultiArrayList(Data),
active_index: Index,

pub const init: Lineup = .{
    .list = .empty,
    .active_index = .none,
};

pub fn deinit(lineup: *Lineup, gpa: Allocator) void {
    lineup.list.deinit(gpa);
}

pub const Data = struct {
    name: Name,
    slots: EnumArray(Avatar.Slot, ?Avatar),
    leader: Avatar.Slot,
    flags: Flags = .default,
    mp: Mp = .max,
};

pub const Name = LimitedString(15);

pub const Index = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn fromInt(int: u32) Index {
        return @enumFromInt(int);
    }

    pub fn toInt(index: Index) u32 {
        return @intFromEnum(index);
    }
};

pub const Flags = packed struct {
    pub const default: Flags = .{
        .challenge = false,
        .virtual = false,
    };

    challenge: bool,
    virtual: bool,
};

pub const Mp = enum(u8) {
    exhausted = 0,
    max = 4,
    _,

    pub fn fromInt(int: u32) Mp {
        const casted = std.math.cast(u8, int) orelse return .max;
        return @enumFromInt(@min(@intFromEnum(Mp.max), casted));
    }

    pub fn toInt(mp: Mp) u8 {
        return @intFromEnum(mp);
    }

    pub const Error = error{
        MpExhausted,
    };

    pub fn consume(mp: Mp) Mp.Error!Mp {
        if (mp == .exhausted) return error.MpExhausted;
        return .fromInt(mp.toInt() - 1);
    }
};

pub const Avatar = struct {
    id: AvatarRow.ID,
    skill_cast_cnt: u32 = 0,
    hp: Hp = .max,
    sp: Sp = .ready,
    satiety: Satiety = .full,

    pub const Slot = enum(u8) {
        first = 0,
        second = 1,
        third = 2,
        fourth = 3,

        pub const last = Slot.fourth;
        pub const count = 4;

        pub const Error = error{
            LineupOutOfBounds,
        };

        pub fn fromInt(int: u32) Slot.Error!Slot {
            return std.enums.fromInt(Slot, int) orelse return error.LineupOutOfBounds;
        }

        pub fn toInt(slot: Slot) u8 {
            return @intFromEnum(slot);
        }
    };

    pub const Hp = enum(u16) {
        exhausted = 0,
        max = 10000,
        _,

        pub fn fromInt(int: u32) Hp {
            const casted = std.math.cast(u16, int) orelse return .max;
            return @enumFromInt(@min(@intFromEnum(Hp.max), casted));
        }

        pub fn toInt(hp: Hp) u16 {
            return @intFromEnum(hp);
        }
    };

    pub const Sp = enum(u16) {
        exhausted = 0,
        ready = 10000,
        _,

        pub fn fromInt(int: u32) Sp {
            const casted = std.math.cast(u16, int) orelse return .max;
            return @enumFromInt(@min(@intFromEnum(Sp.ready), casted));
        }

        pub fn toInt(sp: Sp) u16 {
            return @intFromEnum(sp);
        }
    };

    pub const Satiety = enum(u8) {
        starved = 0,
        full = 100,
        _,

        pub fn fromInt(int: u32) Sp {
            const casted = std.math.cast(u8, int) orelse return .max;
            return @enumFromInt(@min(@intFromEnum(Satiety.full), casted));
        }

        pub fn toInt(s: Satiety) u16 {
            return @intFromEnum(s);
        }
    };
};

const LimitedString = common.mem.LimitedString;
const AvatarRow = Assets.ExcelTables.AvatarRow;
const MultiArrayList = std.MultiArrayList;
const EnumArray = std.EnumArray;
const Allocator = std.mem.Allocator;

const Assets = @import("../Assets.zig");
const common = @import("common");
const std = @import("std");
const Lineup = @This();
