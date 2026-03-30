pub fn onGetChallengeCsReq(txn: Transaction, request: pb.GetChallengeCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    var challenge_list: std.ArrayList(pb.Challenge) = .empty;

    var it = txn.modules.challenge.map.iterator();
    while (it.next()) |entry| try challenge_list.append(txn.arena, .{
        .challenge_id = entry.key_ptr.toInt(),
        .stars = @intCast(@as(u3, @bitCast(entry.value_ptr.*))),
    });

    try txn.sendMessage(pb.GetChallengeScRsp{
        .challenge_list = challenge_list,
    });
}

// The client will send this request if the player was previously in a challenge.
pub fn onLeaveChallengeCsReq(txn: Transaction, request: pb.LeaveChallengeCsReq) !void {
    _ = request;

    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);
    txn.modules.challenge.stage = .none;

    const scene = &txn.modules.scene;
    const lineup = &txn.modules.lineup;

    const entry = txn.assets.tables.map_entry.map.get(@enumFromInt(1010201)).?;

    try scene.enterScene(
        txn.gpa,
        txn.assets,
        entry,
        null,
        &lineup.list.items(.slots)[lineup.active_index.toInt()],
    );

    var scene_info: pb.SceneInfo = .init;
    try encoding.packSceneInfo(
        &scene_info,
        txn.arena,
        txn.assets,
        entry,
        &txn.modules.scene.entity_manager,
        txn.modules.login.uid,
    );

    try txn.sendMessage(pb.LeaveChallengeScRsp{
        .maze = .{
            .id = entry.PlaneID,
            .map_entry_id = entry.EntryID.toInt(),
            .floor = .{
                .floor_id = entry.FloorID,
                .scene = scene_info,
            },
        },
    });

    std.log.scoped(.scene).info(
        "entering maze {d} (plane={d}, floor={d})",
        .{ entry.EntryID, entry.PlaneID, entry.FloorID },
    );
}

pub fn onStartChallengeCsReq(txn: Transaction, request: pb.StartChallengeCsReq) !void {
    try txn.modules.login.step.ensureExact(.finished);

    const config = txn.assets.tables.challenge_maze_config.map.get(@enumFromInt(request.challenge_id)) orelse {
        return txn.sendError(pb.StartChallengeScRsp, .RET_CHALLENGE_NOT_EXIST);
    };

    const entry = txn.assets.tables.map_entry.map.get(@enumFromInt(config.MapEntranceID)) orelse {
        return txn.sendError(pb.StartChallengeScRsp, .RET_MAZE_MAP_NOT_EXIST);
    };

    txn.modules.challenge.stage = if (config.StageID.len == 2) .low else .high;
    txn.modules.challenge.challenge_id = @enumFromInt(request.challenge_id);

    const scene = &txn.modules.scene;
    const lineup = &txn.modules.lineup;

    const index = try lineup.getRequestIndex(lineup.active_index.toInt(), .LINEUP_CHALLENGE);

    try scene.enterScene(
        txn.gpa,
        txn.assets,
        entry,
        null,
        &lineup.list.items(.slots)[index],
    );

    var scene_info: pb.SceneInfo = .init;
    try encoding.packSceneInfo(
        &scene_info,
        txn.arena,
        txn.assets,
        entry,
        &txn.modules.scene.entity_manager,
        txn.modules.login.uid,
    );

    try txn.sendMessage(pb.StartChallengeScRsp{
        .maze = .{
            .id = entry.PlaneID,
            .map_entry_id = entry.EntryID.toInt(),
            .floor = .{
                .floor_id = entry.FloorID,
                .scene = scene_info,
            },
        },
    });

    std.log.scoped(.scene).info(
        "entering challenge maze {d} (plane={d}, floor={d})",
        .{ entry.EntryID, entry.PlaneID, entry.FloorID },
    );
}

pub fn onFinishChallengeCsReq(txn: Transaction, request: pb.FinishChallengeCsReq) !void {
    try txn.modules.login.step.ensureExact(.finished);

    const challenge = &txn.modules.challenge;
    std.debug.assert(request.challenge_id == challenge.challenge_id.toInt());

    const config = txn.assets.tables.challenge_maze_config.map.get(challenge.challenge_id) orelse {
        return txn.sendError(pb.FinishChallengeScRsp, .RET_CHALLENGE_NOT_EXIST);
    };

    var stars: Challenge.Stars = challenge.map.get(challenge.challenge_id) orelse .initEmpty();
    for (config.ChallengeTargetID, 0..) |id, i| {
        const target = txn.assets.tables.challenge_target_config.map.get(@enumFromInt(id)) orelse continue;
        if (target.ChallengeTargetType == .ROUNDS and challenge.round_cnt > target.ChallengeTargetParam) continue;

        stars.set(i);
    }

    try challenge.map.put(txn.gpa, challenge.challenge_id, stars);
    try txn.notify(.challenge_finished, .{});

    try txn.sendMessage(pb.ChallengeSettleNotify{
        .challenge_id = challenge.challenge_id.toInt(),
        .is_win = true,
        .stars = @intCast(@as(u3, @bitCast(stars))),
    });

    try txn.sendMessage(pb.FinishChallengeScRsp{});
}

const Challenge = modules.Challenge;
const modules = @import("../modules.zig");

const encoding = @import("../encoding.zig");

const Transaction = @import("../requests.zig").Transaction;
const pb = @import("proto").pb;
const std = @import("std");
