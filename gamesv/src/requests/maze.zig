pub fn onGetMazeMapInfoCsReq(txn: Transaction, request: pb.GetMazeMapInfoCsReq) !void {
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    const entry = txn.assets.tables.map_entry.map.get(@enumFromInt(request.entry_id)) orelse {
        return txn.sendError(pb.GetMazeMapInfoScRsp, .RET_MAZE_MAP_NOT_EXIST);
    };

    const floor = txn.assets.floor.map.get(entry.FloorID) orelse {
        return txn.sendError(pb.GetMazeMapInfoScRsp, .RET_MAZE_NO_FLOOR);
    };

    var lighten_section_list: std.ArrayList(u32) = .empty;

    if (floor.MinimapVolumeData.Sections) |sections| {
        for (sections) |section| {
            try lighten_section_list.append(txn.arena, section.ID);
        }
    }

    var maze_prop_list: std.ArrayList(pb.MazePropState) = .empty;
    var maze_group_list: std.ArrayList(pb.MazeGroup) = .empty;

    const group_id = floor.StartGroupID;

    if (txn.assets.group.map.get(.{
        .floor_id = floor.FloorID,
        .group_id = group_id,
    })) |group| {
        try maze_group_list.append(txn.arena, .{ .group_id = group_id });

        if (group.PropList) |props|
            for (props) |prop|
                if (txn.assets.tables.prop.map.get(@enumFromInt(prop.PropID))) |prop_row| {
                    if (prop_row.PropType == .PROP_SPRING) {
                        try maze_prop_list.append(txn.arena, .{
                            .group_id = group_id,
                            .config_id = prop.ID,
                            .state = @import("../Assets/ExcelTables/PropRow.zig").State.CheckPointEnable.toInt(),
                        });
                    }
                };
    }

    try txn.sendMessage(pb.GetMazeMapInfoScRsp{
        .entry_id = request.entry_id,
        .lighten_section_list = lighten_section_list,
        .maze_prop_list = maze_prop_list,
        .maze_group_list = maze_group_list,
    });
}

const Transaction = @import("../requests.zig").Transaction;
const pb = @import("proto").pb;

const std = @import("std");
