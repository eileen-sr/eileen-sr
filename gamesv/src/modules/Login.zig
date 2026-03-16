step: Step,
uid: Uid,

pub const init: Login = .{
    .step = .pre_get_token,
    .uid = .none,
};

pub fn onPlayerTokenGot(login: *Login, uid: Uid) void {
    debug.assert(login.step == .pre_get_token);
    debug.assert(uid != .none);

    login.uid = uid;
    login.step = .has_player_token;
}

pub fn onPlayerLoginSuccess(login: *Login) void {
    debug.assert(login.step == .has_player_token);
    login.step = .waiting_key_packets;
}

pub fn onAllKeyPacketsReturn(login: *Login) void {
    debug.assert(login.step == .waiting_key_packets);
    login.step = .finished;
}

pub const Uid = enum(u32) {
    none = 0,
    _,

    pub inline fn fromInt(int: u32) Uid {
        return @enumFromInt(int);
    }

    pub inline fn toInt(uid: Uid) u32 {
        debug.assert(uid != .none);
        return @intFromEnum(uid);
    }
};

pub const Step = enum {
    pre_get_token,
    has_player_token,
    waiting_key_packets,
    finished,

    pub const EnsureError = error{
        UnexpectedLoginStep,
    };

    pub fn ensureExact(cur: Step, desired: Step) EnsureError!void {
        if (cur != desired) return error.UnexpectedLoginStep;
    }

    pub fn ensureAtLeast(cur: Step, least: Step) EnsureError!void {
        if (@intFromEnum(cur) < @intFromEnum(least)) return error.UnexpectedLoginStep;
    }
};

const debug = std.debug;
const std = @import("std");
const Login = @This();
