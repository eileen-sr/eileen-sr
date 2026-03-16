pub fn onGetMissionDataCsReq(txn: Transaction, request: pb.GetMissionDataCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    var rsp: pb.GetMissionDataScRsp = .init;
    try rsp.finished_main_mission_id_list.ensureTotalCapacity(
        txn.arena,
        txn.assets.tables.main_mission.rows.len,
    );

    for (txn.assets.tables.main_mission.rows) |row| {
        rsp.finished_main_mission_id_list.appendAssumeCapacity(row.MainMissionID);
    }

    try txn.sendMessage(rsp);
}

const Transaction = @import("../requests.zig").Transaction;
const pb = @import("proto").pb;
const std = @import("std");
