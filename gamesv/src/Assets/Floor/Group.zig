const group_dir_path = "assets/group/";

AnchorList: ?[]const AnchorDescription = null,
MonsterList: ?[]const MonsterDescription = null,
PropList: ?[]const PropDescription = null,
NPCList: ?[]const NpcDescription = null,

pub const AnchorDescription = struct {
    ID: u32,
    PosX: f32,
    PosY: f32,
    PosZ: f32,
    RotY: f32,
};

pub const MonsterDescription = struct {
    ID: u32,
    CreateOnInitial: bool,
    NPCMonsterID: u32,
    PosX: f32,
    PosZ: f32,
    PosY: f32,
    RotY: f32,
    EventID: u32,
};

pub const PropDescription = struct {
    ID: u32,
    InitLevelGraph: ?[]const u8,
    State: @import("../ExcelTables/PropRow.zig").State,
    CreateOnInitial: bool,
    PropID: u32,
    AnchorID: u32,
    PosX: f32,
    PosZ: f32,
    PosY: f32,
    RotX: f32,
    RotZ: f32,
    RotY: f32,
};

pub const NpcDescription = struct {
    ID: u32,
    NPCID: u32,
    CreateOnInitial: bool,
    PosX: f32,
    PosZ: f32,
    PosY: f32,
    RotY: f32,
};

pub const ID = packed struct {
    floor_id: u32,
    group_id: u32,
};

pub const Table = struct {
    const Map = HashMap(ID, Group);

    arena: ArenaAllocator,
    map: Map,

    pub fn load(gpa: Allocator, io: Io, floors: []const Floor) LoadError!Table {
        const Result = union(enum) { one: LoadError!Entry };
        const Select = Io.Select(Result);

        var groups_count: usize = 0;
        for (floors) |floor|
            groups_count += floor.GroupList.len;

        const select_buf: []Result = try gpa.alloc(Result, groups_count);
        defer gpa.free(select_buf);

        var arena: ArenaAllocator = .init(gpa);
        errdefer arena.deinit();

        var select: Select = .init(io, select_buf);
        defer select.cancelDiscard();

        var map: Map = .empty;
        try map.ensureTotalCapacity(arena.allocator(), groups_count);

        for (floors) |floor| for (floor.GroupList) |group| select.async(
            .one,
            loadOne,
            .{ gpa, arena.allocator(), io, floor.PlaneID, floor.FloorID, group.ID },
        );

        while (map.entries.len != groups_count) {
            const result = try select.await();
            const entry = try result.one;

            map.putAssumeCapacity(entry.id, entry.config);
        }

        return .{ .map = map, .arena = arena };
    }

    const Entry = struct { id: ID, config: Group };

    fn loadOne(
        gpa: Allocator,
        arena: Allocator,
        io: Io,
        plane_id: u32,
        floor_id: u32,
        group_id: u32,
    ) LoadError!Entry {
        // floor_dir_path, 50 chars for u32, then 'Groups_P', '_F', '/LevelGroup_P' '_F', '_G', '.json'
        var path_buf: [group_dir_path.len + 50 + 8 + 2 + 13 + 2 + 2 + 5]u8 = undefined;
        const path = std.fmt.bufPrint(
            &path_buf,
            "{0s}Groups_P{1d}_F{2d}/LevelGroup_P{1d}_F{2d}_G{3d}.json",
            .{ group_dir_path, plane_id, floor_id, group_id },
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

        const config = json.parseFromTokenSourceLeaky(Group, arena, &json_reader, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        }) catch return error.JsonParseFailed;

        return .{
            .id = .{ .floor_id = floor_id, .group_id = group_id },
            .config = config,
        };
    }

    pub fn deinit(t: *Table) void {
        t.arena.deinit();
    }
};

const Io = std.Io;
const Allocator = std.mem.Allocator;
const HashMap = std.AutoArrayHashMapUnmanaged;
const ArenaAllocator = std.heap.ArenaAllocator;

const LoadError = Floor.LoadError;
const Floor = @import("../Floor.zig");

const json = std.json;
const std = @import("std");
const Group = @This();
