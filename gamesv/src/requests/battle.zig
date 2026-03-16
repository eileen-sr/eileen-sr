pub fn onGetCurBattleInfoCsReq(txn: Transaction, request: pb.GetCurBattleInfoCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    try txn.sendMessage(pb.GetCurBattleInfoScRsp{});
}

pub fn onPVEBattleResultCsReq(txn: Transaction, request: pb.PVEBattleResultCsReq) !void {
    try txn.modules.login.step.ensureExact(.finished);

    try txn.sendMessage(pb.PVEBattleResultScRsp{
        .stage_id = request.stage_id,
        .end_status = request.end_status,
    });
}

const Transaction = @import("../requests.zig").Transaction;
const pb = @import("proto").pb;
const std = @import("std");
