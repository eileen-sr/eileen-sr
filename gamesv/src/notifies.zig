// The idea is similar to NotifyManager::Notify, where it can dispatch various "notifies" to different modules.

const log = std.log.scoped(.notifies);
pub const Error = Allocator.Error || Io.Cancelable || modules.LogicError;

pub const Type = enum {
    first_login,
    lineup_leader_changed,
    lineup_slots_changed,
    lineup_name_changed,
    lineup_index_changed,
    avatar_modified,
    equipment_modified,
    scene_changed,
};

pub const Argument = union(Type) {
    pub const FirstLogin = struct {};

    pub const LineupLeaderChanged = struct {
        new_slot: modules.Lineup.Avatar.Slot,
    };

    pub const LineupSlotsChanged = struct {};

    pub const LineupNameChanged = struct {};

    pub const LineupIndexChanged = struct {};

    pub const AvatarModified = struct {
        avatar_id: Assets.ExcelTables.AvatarRow.ID,
    };

    pub const EquipmentModified = struct {
        equipment_unique_id: u32,
    };

    pub const SceneChanged = struct {};

    first_login: FirstLogin,
    lineup_leader_changed: LineupLeaderChanged,
    lineup_slots_changed: LineupSlotsChanged,
    lineup_name_changed: LineupNameChanged,
    lineup_index_changed: LineupIndexChanged,
    avatar_modified: AvatarModified,
    equipment_modified: EquipmentModified,
    scene_changed: SceneChanged,
};

// A subset of requests.Transaction.
// Doesn't have a way of sending messages because this notify system
// shouldn't interfere with networking.
pub const Transaction = struct {
    io: Io,
    gpa: Allocator,
    arena: Allocator,
    assets: *const Assets,
    modules: *modules.Container,
    time: Io.Timestamp,
};

pub fn dispatch(
    txn: Transaction,
    comptime notify_type: Type,
    argument: @FieldType(Argument, @tagName(notify_type)),
) Error!void {
    inline for (namespaces) |namespace| inline for (@typeInfo(namespace).@"struct".decls) |decl| {
        const function = @field(namespace, decl.name);
        const fn_info = @typeInfo(@TypeOf(function)).@"fn";
        if (fn_info.params[1].type.? != @TypeOf(argument)) continue;

        function(txn, argument) catch |err| switch (@as(Error, err)) {
            error.Canceled, error.OutOfMemory => |e| return e,
            else => |e| log.err(
                @typeName(namespace) ++ "." ++ decl.name ++ " failed: {t}",
                .{e},
            ),
        };
    };
}

const namespaces: []const type = &.{
    @import("notifies/avatar.zig"),
    @import("notifies/lineup.zig"),
    @import("notifies/inventory.zig"),
    @import("notifies/scene.zig"),
};

const Allocator = std.mem.Allocator;
const Io = std.Io;

const Assets = @import("Assets.zig");
const modules = @import("modules.zig");
const std = @import("std");
