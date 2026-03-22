// Logic errors are the conditions that signify a misbehaving client.
// For example: trying to perform an operation that is illegal in the active state.
// Example of a non-logic-error: attempt to switch to a character that is not yet unlocked.
// General rules:
// * if the condition can be represented by an erroneous retcode, it's not a logic error.
// * if the condition is not representable by an erroneous retcode, it's a logic error.
// * RET_FAIL and RET_SERVER_INTERNAL_ERROR are not reasonable retcodes for an invalid client behavior.
pub const LogicError = Login.Step.EnsureError || Player.Error || Lineup.Error || Inventory.Error;

pub const Container = struct {
    login: Login,
    player: Player,
    avatar: Avatar,
    lineup: Lineup,
    inventory: Inventory,
    scene: Scene,

    pub const init: Container = .{
        .login = .init,
        .player = .init,
        .avatar = .init,
        .lineup = .init,
        .inventory = .init,
        .scene = .init,
    };

    pub fn deinit(container: *Container, gpa: Allocator) void {
        container.avatar.deinit(gpa);
        container.lineup.deinit(gpa);
        container.inventory.deinit(gpa);
    }

    pub fn isFirstLogin(container: *const Container) bool {
        return container.avatar.list.len == 0;
    }
};

pub const Login = @import("modules/Login.zig");
pub const Player = @import("modules/Player.zig");
pub const Avatar = @import("modules/Avatar.zig");
pub const Lineup = @import("modules/Lineup.zig");
pub const Inventory = @import("modules/Inventory.zig");
pub const Scene = @import("modules/Scene.zig");

const Allocator = std.mem.Allocator;
const std = @import("std");
