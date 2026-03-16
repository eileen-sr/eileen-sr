pub fn onGetMazeMapInfoCsReq(txn: Transaction, request: pb.GetMazeMapInfoCsReq) !void {
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    try txn.sendMessage(pb.GetMazeMapInfoScRsp{
        .entry_id = request.entry_id,
    });
}

const Transaction = @import("../requests.zig").Transaction;
const pb = @import("proto").pb;
const std = @import("std");
