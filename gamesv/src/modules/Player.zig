nickname: Nickname,
level: Level,
world_level: WorldLevel,
stamina: Stamina,
coins: std.EnumArray(Coin.Kind, Coin),

pub const init: Player = .{
    .nickname = .constant("ReversedRooms"),
    .level = .max,
    .world_level = .max,
    .stamina = .max,
    .coins = .initFill(.limit),
};

pub const Error = Stamina.ConsumeError || Coin.UseError;

pub const Nickname = LimitedString(14);

pub const Level = enum(u32) {
    min = 1,
    max = 60,
    _,

    pub fn toInt(level: Level) u32 {
        return @intFromEnum(level);
    }

    pub fn next(level: Level) Level {
        return switch (level) {
            .max => .max,
            .min, _ => @enumFromInt(@intFromEnum(level) + 1),
        };
    }
};

pub const WorldLevel = enum(u32) {
    min = 0,
    max = 3,
    _,

    pub fn toInt(level: WorldLevel) u32 {
        return @intFromEnum(level);
    }

    pub fn next(level: WorldLevel) WorldLevel {
        return switch (level) {
            .max => .max,
            .min, _ => @enumFromInt(@intFromEnum(level) + 1),
        };
    }
};

pub const Stamina = enum(u32) {
    max = 160,
    _,

    pub const ConsumeError = error{
        NotEnoughStamina,
    };

    pub fn toInt(stamina: Stamina) u32 {
        return @intFromEnum(stamina);
    }

    pub fn fromInt(int: u32) Stamina {
        return @enumFromInt(@min(Stamina.max.toInt(), int));
    }

    pub fn increase(stamina: Stamina, delta: u32) Stamina {
        return .fromInt(stamina.toInt() +| delta);
    }

    pub fn consume(stamina: Stamina, amount: u32) ConsumeError!Stamina {
        return if (stamina.toInt() >= amount)
            .fromInt(stamina.toInt() - amount)
        else
            error.NotEnoughStamina;
    }
};

pub const Coin = enum(u32) {
    pub const Kind = enum { m, h, s };

    // This value is defined by 'ItemRow.PileLimit' of 900001 (SCoin)
    limit = 99999,
    _,

    pub const UseError = error{
        NotEnoughCoins,
    };

    pub fn toInt(coin: Coin) u32 {
        return @intFromEnum(coin);
    }

    pub fn fromInt(int: u32) Coin {
        return @enumFromInt(@min(Coin.limit.toInt(), int));
    }

    pub fn add(coin: Coin, delta: u32) Coin {
        return .fromInt(coin.toInt() +| delta);
    }

    pub fn use(coin: Coin, amount: u32) UseError!Coin {
        return if (coin.toInt() >= amount)
            .fromInt(coin.toInt() - amount)
        else
            error.NotEnoughCoins;
    }
};

const LimitedString = common.mem.LimitedString;

const common = @import("common");
const std = @import("std");
const Player = @This();
