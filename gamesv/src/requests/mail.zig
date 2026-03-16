pub fn onGetMailCsReq(txn: Transaction, request: pb.GetMailCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    try txn.sendMessage(pb.GetMailScRsp{});
}

const Transaction = @import("../requests.zig").Transaction;
const pb = @import("proto").pb;
const std = @import("std");
