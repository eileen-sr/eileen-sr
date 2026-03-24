const floor_dir_path = "assets/floor/";

FloorID: u32,
FloorName: []const u8,
StartGroupID: u32,
StartAnchorID: u32,
GroupList: []const GroupDescription,
DefaultGroupIDList: []const u32,
PlaneID: u32 = 0, // set by loader.
MinimapVolumeData: MinimapVolumeDescription,

pub const GroupDescription = struct {
    ID: u32,
    Name: []const u8,
    PosX: f32,
    PosY: f32,
    PosZ: f32,
    IsDelete: bool,
};

pub const MinimapVolumeDescription = struct { Sections: ?[]const struct { ID: u32 } };

pub const LoadError = Io.Cancelable || Allocator.Error || error{
    JsonParseFailed,
    InputOutput,
};

pub const Table = struct {
    const Map = HashMap(u32, Floor);

    arena: ArenaAllocator,
    map: Map,

    pub fn load(gpa: Allocator, io: Io, map_entries: *const MapEntryTable) LoadError!Table {
        const Result = union(enum) { one: LoadError!Entry };
        const Select = Io.Select(Result);

        const select_buf: []Result = try gpa.alloc(Result, map_entries.rows.len);
        defer gpa.free(select_buf);

        var arena: ArenaAllocator = .init(gpa);
        errdefer arena.deinit();

        var select: Select = .init(io, select_buf);
        defer select.cancelDiscard();

        var map: Map = .empty;
        try map.ensureTotalCapacity(arena.allocator(), map_entries.rows.len);

        for (map_entries.rows) |row| select.async(
            .one,
            loadOne,
            .{ gpa, arena.allocator(), io, row.PlaneID, row.FloorID },
        );

        while (map.entries.len != map_entries.rows.len) {
            const result = try select.await();
            const entry = try result.one;

            map.putAssumeCapacity(entry.floor_id, entry.config);
        }

        return .{ .map = map, .arena = arena };
    }

    const Entry = struct { floor_id: u32, config: Floor };

    fn loadOne(gpa: Allocator, arena: Allocator, io: Io, plane_id: u32, floor_id: u32) LoadError!Entry {
        // floor_dir_path, 20 chars for u32, then 'P', '_F', '.json'
        var path_buf: [floor_dir_path.len + 20 + 1 + 2 + 5]u8 = undefined;
        const path = std.fmt.bufPrint(
            &path_buf,
            "{s}P{d}_F{d}.json",
            .{ floor_dir_path, plane_id, floor_id },
        ) catch unreachable;

        const cwd: Io.Dir = .cwd();
        var file = cwd.openFile(io, path, .{}) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => return error.InputOutput,
        };

        defer file.close(io);

        var read_buffer: [4096]u8 = undefined;
        var file_reader = file.reader(io, &read_buffer);

        var json_reader: json.Reader = .init(gpa, &file_reader.interface);
        defer json_reader.deinit();

        var config = json.parseFromTokenSourceLeaky(Floor, arena, &json_reader, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        }) catch return error.JsonParseFailed;

        config.PlaneID = plane_id;

        return .{ .floor_id = floor_id, .config = config };
    }

    pub fn deinit(t: *Table) void {
        t.arena.deinit();
    }
};

pub const Group = @import("Floor/Group.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;
const HashMap = std.AutoArrayHashMapUnmanaged;
const ArenaAllocator = std.heap.ArenaAllocator;

const MapEntryTable = @FieldType(ExcelTables, "map_entry");
const ExcelTables = @import("ExcelTables.zig");

const json = std.json;
const std = @import("std");
const Floor = @This();
