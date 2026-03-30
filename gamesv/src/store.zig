pub const player_module_path = "store/player/{d}/player.bytes";
pub const avatar_list_path = "store/player/{d}/avatar_list.bytes";
pub const lineup_list_path = "store/player/{d}/lineup_list.bytes";
pub const active_lineup_path = "store/player/{d}/active_lineup.bytes";
pub const material_list_path = "store/player/{d}/material_list.bytes";
pub const equipment_list_path = "store/player/{d}/equipment_list.bytes";
pub const equipment_uid_path = "store/player/{d}/equipment_uid.bytes";
pub const scene_module_path = "store/player/{d}/scene.bytes";
pub const challenge_list_path = "store/player/{d}/challenge_list.bytes";

pub fn loadModules(gpa: Allocator, io: Io, uid: Uid, container: *modules.Container) !void {
    var path_buf: [128]u8 = undefined;

    const old_cancel_protection = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(old_cancel_protection);

    if (try readStruct(modules.Player, io, makePath(player_module_path, &path_buf, uid))) |player| {
        container.player = player;
    }

    if (try readStruct(modules.Scene.Saveable, io, makePath(scene_module_path, &path_buf, uid))) |scene| {
        container.scene = .{
            .entry_id = scene.entry_id,
            .motion = scene.motion,
            .entity_manager = .init,
        };
    }

    const avatar_list = try readMultiArray(
        modules.Avatar.Data,
        io,
        makePath(avatar_list_path, &path_buf, uid),
        gpa,
    );

    container.avatar.list.deinit(gpa);
    container.avatar.list = avatar_list;

    try container.avatar.reindex(gpa);

    const lineup_list = try readMultiArray(
        modules.Lineup.Data,
        io,
        makePath(lineup_list_path, &path_buf, uid),
        gpa,
    );

    container.lineup.list.deinit(gpa);
    container.lineup.list = lineup_list;

    container.lineup.active_index = if (try readInt(
        u32,
        io,
        makePath(active_lineup_path, &path_buf, uid),
    )) |int| .fromInt(int) else if (container.lineup.list.len == 0) .none else .fromInt(0);

    const equipment_list = try readMultiArray(
        modules.Inventory.Equipment,
        io,
        makePath(equipment_list_path, &path_buf, uid),
        gpa,
    );

    container.inventory.equipment.deinit(gpa);
    container.inventory.equipment = equipment_list;
    try container.inventory.reindex(gpa);

    const material_map = try readArrayHashMap(
        ItemRow.ID,
        modules.Inventory.Material,
        io,
        makePath(material_list_path, &path_buf, uid),
        gpa,
    );

    container.inventory.material_map.deinit(gpa);
    container.inventory.material_map = material_map;

    container.inventory.unique_id_counter = try readInt(
        u32,
        io,
        makePath(equipment_uid_path, &path_buf, uid),
    ) orelse 0;

    const challenge_map = try readArrayHashMap(
        ChallengeMazeConfigRow.ID,
        Challenge.Stars,
        io,
        makePath(challenge_list_path, &path_buf, uid),
        gpa,
    );

    container.challenge.map.deinit(gpa);
    container.challenge.map = challenge_map;
}

fn maxPathSize(comptime path_pattern: []const u8) usize {
    return (path_pattern.len - 3) + 10;
}

pub inline fn makePath(comptime path_pattern: []const u8, buf: anytype, uid: Uid) []const u8 {
    comptime debug.assert(
        maxPathSize(path_pattern) <= @typeInfo(@typeInfo(@TypeOf(buf)).pointer.child).array.len,
    );
    return std.fmt.bufPrint(buf, path_pattern, .{uid.toInt()}) catch unreachable;
}

const ReadIntError = error{
    InputOutput,
    Corrupted,
};

fn readInt(comptime Int: type, io: Io, path: []const u8) ReadIntError!?Int {
    const cwd: Io.Dir = .cwd();
    var file = cwd.openFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return error.InputOutput,
    };

    defer file.close(io);

    if (@sizeOf(Int) != file.length(io) catch return error.InputOutput)
        return error.Corrupted;

    var reader = file.reader(io, "");
    var int: Int = undefined;

    reader.interface.readSliceAll(@ptrCast(&int)) catch return error.InputOutput;

    return int;
}

pub const SaveError = error{InputOutput};

pub fn saveInt(comptime Int: type, io: Io, path: []const u8, int: Int) SaveError!void {
    const cwd: Io.Dir = .cwd();

    if (std.fs.path.dirname(path)) |dir_path| {
        cwd.createDirPath(io, dir_path) catch return error.InputOutput;
    }

    var file = cwd.createFile(io, path, .{}) catch return error.InputOutput;
    defer file.close(io);

    var writer = file.writer(io, "");
    writer.interface.writeInt(Int, int, .native) catch return error.InputOutput;
}

pub fn saveStruct(comptime S: type, io: Io, path: []const u8, s: *const S) SaveError!void {
    const cwd: Io.Dir = .cwd();

    if (std.fs.path.dirname(path)) |dir_path| {
        cwd.createDirPath(io, dir_path) catch return error.InputOutput;
    }

    var file = cwd.createFile(io, path, .{}) catch return error.InputOutput;
    defer file.close(io);

    var writer = file.writer(io, "");
    writer.interface.writeAll(@ptrCast(s)) catch return error.InputOutput;
}

pub const SaveStructError = error{InputOutput};

pub fn saveMultiArray(
    comptime T: type,
    io: Io,
    path: []const u8,
    list: *const MultiArrayList(T),
) SaveError!void {
    const cwd: Io.Dir = .cwd();

    if (std.fs.path.dirname(path)) |dir_path| {
        cwd.createDirPath(io, dir_path) catch return error.InputOutput;
    }

    var file = cwd.createFile(io, path, .{}) catch return error.InputOutput;
    defer file.close(io);

    var buffer: [1024]u8 = undefined;
    var writer = file.writer(io, &buffer);

    writer.interface.writeInt(u32, @truncate(list.len), .native) catch return error.InputOutput;

    const fields = comptime std.enums.values(MultiArrayList(T).Field);
    var vecs: [fields.len][]const u8 = undefined;
    var slice = list.slice();

    inline for (fields) |field| {
        vecs[@intFromEnum(field)] = std.mem.sliceAsBytes(slice.items(field));
    }

    writer.interface.writeVecAll(&vecs) catch return error.InputOutput;
    writer.interface.flush() catch return error.InputOutput;
}

pub fn saveArrayHashMap(
    comptime K: type,
    comptime V: type,
    io: Io,
    path: []const u8,
    map: *const ArrayHashMap(K, V),
) SaveError!void {
    const cwd: Io.Dir = .cwd();

    if (std.fs.path.dirname(path)) |dir_path| {
        cwd.createDirPath(io, dir_path) catch return error.InputOutput;
    }

    var file = cwd.createFile(io, path, .{}) catch return error.InputOutput;
    defer file.close(io);

    var buffer: [1024]u8 = undefined;
    var writer = file.writer(io, &buffer);

    writer.interface.writeInt(u32, @truncate(map.entries.len), .native) catch return error.InputOutput;

    var vecs: [2][]const u8 = .{
        std.mem.sliceAsBytes(map.entries.items(.key)),
        std.mem.sliceAsBytes(map.entries.items(.value)),
    };

    writer.interface.writeVecAll(&vecs) catch return error.InputOutput;
    writer.interface.flush() catch return error.InputOutput;
}

const ReadStructError = error{
    InputOutput,
    Corrupted,
};

fn readStruct(comptime T: type, io: Io, path: []const u8) ReadStructError!?T {
    var result: T = undefined;

    const cwd: Io.Dir = .cwd();
    var file = cwd.openFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return error.InputOutput,
    };

    defer file.close(io);

    if (@sizeOf(T) != file.length(io) catch return error.InputOutput)
        return error.Corrupted;

    var reader = file.reader(io, "");
    reader.interface.readSliceAll(@ptrCast(&result)) catch return error.InputOutput;

    return result;
}

const ReadMultiArrayError = error{
    InputOutput,
    Corrupted,
} || Allocator.Error;

fn readMultiArray(
    comptime T: type,
    io: Io,
    path: []const u8,
    gpa: Allocator,
) ReadMultiArrayError!MultiArrayList(T) {
    const cwd: Io.Dir = .cwd();
    var file = cwd.openFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return .empty,
        else => return error.InputOutput,
    };

    defer file.close(io);

    var buffer: [1024]u8 = undefined;
    var reader = file.reader(io, &buffer);

    const item_count = reader.interface.takeInt(u32, .native) catch
        return error.InputOutput;

    const size_in_bytes = MultiArrayList(T).capacityInBytes(item_count);

    if (@sizeOf(u32) + size_in_bytes != file.length(io) catch return error.InputOutput)
        return error.Corrupted;

    var list = try MultiArrayList(T).initCapacity(gpa, item_count);
    errdefer list.deinit(gpa);

    list.len = item_count;

    const fields = comptime std.enums.values(MultiArrayList(T).Field);
    var vecs: [fields.len][]u8 = undefined;
    var slice = list.slice();

    inline for (fields) |field| {
        vecs[@intFromEnum(field)] = std.mem.sliceAsBytes(slice.items(field));
    }

    reader.interface.readVecAll(&vecs) catch |err| switch (err) {
        error.ReadFailed => return error.InputOutput,
        error.EndOfStream => unreachable,
    };

    return list;
}

fn readArrayHashMap(
    comptime K: type,
    comptime V: type,
    io: Io,
    path: []const u8,
    gpa: Allocator,
) ReadMultiArrayError!ArrayHashMap(K, V) {
    const cwd: Io.Dir = .cwd();
    var file = cwd.openFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return .empty,
        else => return error.InputOutput,
    };

    defer file.close(io);

    var buffer: [1024]u8 = undefined;
    var reader = file.reader(io, &buffer);

    const item_count = reader.interface.takeInt(u32, .native) catch
        return error.InputOutput;

    const size_in_bytes = ArrayHashMap(K, V).DataList.capacityInBytes(item_count);

    if (@sizeOf(u32) + size_in_bytes != file.length(io) catch return error.InputOutput)
        return error.Corrupted;

    var list = try ArrayHashMap(K, V).DataList.initCapacity(gpa, item_count);
    errdefer list.deinit(gpa);

    list.len = item_count;
    var slice = list.slice();
    var vecs: [2][]u8 = .{
        std.mem.sliceAsBytes(slice.items(.key)),
        std.mem.sliceAsBytes(slice.items(.value)),
    };

    reader.interface.readVecAll(&vecs) catch |err| switch (err) {
        error.ReadFailed => return error.InputOutput,
        error.EndOfStream => unreachable,
    };

    var map: ArrayHashMap(K, V) = .{ .entries = list };
    try map.reIndex(gpa);

    return map;
}

const Challenge = modules.Challenge;
const Uid = modules.Login.Uid;

const Io = std.Io;
const Allocator = std.mem.Allocator;
const ArrayHashMap = std.AutoArrayHashMapUnmanaged;
const MultiArrayList = std.MultiArrayList;
const debug = std.debug;

const ChallengeMazeConfigRow = Assets.ExcelTables.ChallengeMazeConfigRow;
const ItemRow = Assets.ExcelTables.ItemRow;
const Assets = @import("Assets.zig");

const modules = @import("modules.zig");
const std = @import("std");
