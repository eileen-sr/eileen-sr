pub fn onGetQuestDataCsReq(txn: Transaction, request: pb.GetQuestDataCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    try txn.sendMessage(pb.GetQuestDataScRsp{});
}

const Transaction = @import("../requests.zig").Transaction;
const pb = @import("proto").pb;
const std = @import("std");
