pub const LoadError = ExcelTables.LoadError || Floor.LoadError;

tables: ExcelTables,
floor: Floor.Table,
group: Floor.Group.Table,

pub fn load(gpa: Allocator, io: Io) LoadError!Assets {
    var tables = try ExcelTables.load(gpa, io);
    errdefer tables.deinit();

    var floor = try Floor.Table.load(gpa, io, &tables.map_entry);
    errdefer floor.deinit();

    var group = try Floor.Group.Table.load(gpa, io, floor.map.values());
    errdefer group.deinit();

    return .{ .tables = tables, .floor = floor, .group = group };
}

pub fn deinit(assets: *Assets) void {
    assets.tables.deinit();
    assets.floor.deinit();
    assets.group.deinit();
}

pub const ExcelTables = @import("Assets/ExcelTables.zig");
pub const Floor = @import("Assets/Floor.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const std = @import("std");
const Assets = @This();
