entry_id: u32,
motion: Motion,

pub const init: Scene = .{
    .entry_id = 0,
    .motion = .{},
};

pub const Motion = struct {
    pos: Vector(i32) = .{},
    rot: Vector(i32) = .{},
};

pub fn Vector(comptime T: type) type {
    return struct {
        x: T = 0,
        y: T = 0,
        z: T = 0,

        pub fn from(comptime S: type, s: S) Vector(T) {
            return .{ .x = s.x, .y = s.y, .z = s.z };
        }

        pub fn to(t: Vector(T), comptime S: type) S {
            return .{ .x = t.x, .y = t.y, .z = t.z };
        }
    };
}

pub fn getStartMotion(
    assets: *const Assets,
    entry: *const MapEntryRow,
) ?Motion {
    const floor = assets.floor.map.get(entry.FloorID).?;

    const group = assets.group.map.get(.{
        .floor_id = entry.FloorID,
        .group_id = floor.StartGroupID,
    }).?;

    for (group.AnchorList.?) |anchor| if (anchor.ID == floor.StartAnchorID) {
        return .{
            .pos = .{
                .x = @intFromFloat(anchor.PosX * 1000),
                .y = @intFromFloat(anchor.PosY * 1000),
                .z = @intFromFloat(anchor.PosZ * 1000),
            },
            .rot = .{
                .y = @intFromFloat(anchor.RotY * 1000),
            },
        };
    };

    return null;
}

const MapEntryRow = Assets.ExcelTables.MapEntryRow;

const Assets = @import("../Assets.zig");
const Scene = @This();
