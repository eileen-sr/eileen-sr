pub const LoadError = error{
    OpenFailed,
    JsonParseFailed,
} || Io.Cancelable || Allocator.Error;

arena: ArenaAllocator,
avatar: Table("AvatarExcelTable.json", AvatarRow, "AvatarID"),
main_mission: Table("MainMissionExcelTable.json", MainMissionRow, "MainMissionID"),
equipment: Table("EquipmentExcelTable.json", EquipmentRow, "EquipmentID"),
item: Table("ItemExcelTable.json", ItemRow, "ItemID"),
stage: Table("StageExcelTable.json", StageRow, "StageID"),
cocoon: Table("CocoonExcelTable.json", CocoonRow, "CocoonID"),
map_entry: Table("MapEntryExcelTable.json", MapEntryRow, "EntryID"),
monster: Table("MonsterExcelTable.json", MonsterRow, "MonsterID"),
prop: Table("PropExcelTable.json", PropRow, "PropID"),
npc: Table("NPCDataExcelTable.json", NpcRow, "NPCID"),
tutorial: Table("TutorialDataExcelTable.json", TutorialRow, "TutorialID"),
tutorial_guide: Table("TutorialGuideDataExcelTable.json", TutorialGuideRow, "ID"),

pub fn load(gpa: Allocator, io: Io) LoadError!ExcelTables {
    var results: blk: {
        const field_infos = @typeInfo(ExcelTables).@"struct".fields;
        var field_names: [field_infos.len - 1][:0]const u8 = undefined;
        var field_types: [field_infos.len - 1]type = undefined;

        for (field_infos[1..], 0..) |field, i| {
            field_names[i] = field.name;
            field_types[i] = LoadError!field.type;
        }

        break :blk @Struct(.auto, null, &field_names, &field_types, &@splat(.{}));
    } = undefined;

    var et: ExcelTables = undefined;
    et.arena = .init(gpa);
    errdefer et.arena.deinit();

    var group: Io.Group = .init;
    defer group.cancel(io);

    inline for (@typeInfo(ExcelTables).@"struct".fields[1..]) |field| {
        group.async(
            io,
            field.type.load,
            .{ gpa, et.arena.allocator(), io, &@field(results, field.name) },
        );
    }

    try group.await(io);

    inline for (@typeInfo(ExcelTables).@"struct".fields[1..]) |field| {
        @field(et, field.name) = try @field(results, field.name);
    }

    return et;
}

pub fn deinit(et: *ExcelTables) void {
    et.arena.deinit();
}

pub fn getCocoonRow(et: *const ExcelTables, cocoon_id: u32, world_level: u32) ?*const CocoonRow {
    for (et.cocoon.rows) |*row| {
        if (row.CocoonID.toInt() == cocoon_id and row.WorldLevel == world_level)
            return row;
    } else return null;
}

pub fn Table(comptime filename: []const u8, comptime Row: type, comptime index_key: []const u8) type {
    return struct {
        rows: []const Row,
        map: HashMap(@FieldType(Row, index_key), *const Row),

        pub fn load(gpa: Allocator, arena: Allocator, io: Io, out: *LoadError!@This()) Io.Cancelable!void {
            out.* = loadInner(gpa, arena, io) catch |err| switch (err) {
                error.Canceled => return error.Canceled,
                else => |e| e,
            };
        }

        fn loadInner(gpa: Allocator, arena: Allocator, io: Io) LoadError!@This() {
            const cwd: Io.Dir = .cwd();

            var file = cwd.openFile(io, "assets/tables/" ++ filename, .{}) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => return error.OpenFailed,
            };

            defer file.close(io);

            var read_buffer: [4096]u8 = undefined;
            var file_reader = file.reader(io, &read_buffer);

            var json_reader: json.Reader = .init(gpa, &file_reader.interface);
            defer json_reader.deinit();

            const rows = json.parseFromTokenSourceLeaky([]const Row, arena, &json_reader, .{
                .allocate = .alloc_always,
                .ignore_unknown_fields = true,
            }) catch return error.JsonParseFailed;

            var result: @This() = .{
                .rows = rows,
                .map = .empty,
            };

            for (rows) |*row| {
                try result.map.put(arena, @field(row, index_key), row);
            }

            return result;
        }
    };
}

pub const AvatarRow = @import("ExcelTables/AvatarRow.zig");
pub const MainMissionRow = @import("ExcelTables/MainMissionRow.zig");
pub const EquipmentRow = @import("ExcelTables/EquipmentRow.zig");
pub const ItemRow = @import("ExcelTables/ItemRow.zig");
pub const StageRow = @import("ExcelTables/StageRow.zig");
pub const CocoonRow = @import("ExcelTables/CocoonRow.zig");
pub const MapEntryRow = @import("ExcelTables/MapEntryRow.zig");
pub const MonsterRow = @import("ExcelTables/MonsterRow.zig");
pub const PropRow = @import("ExcelTables/PropRow.zig");
pub const NpcRow = @import("ExcelTables/NpcRow.zig");
pub const TutorialRow = @import("ExcelTables/TutorialRow.zig");
pub const TutorialGuideRow = @import("ExcelTables/TutorialGuideRow.zig");

const json = std.json;

const Io = std.Io;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const HashMap = std.AutoArrayHashMapUnmanaged;

const std = @import("std");
const ExcelTables = @This();
