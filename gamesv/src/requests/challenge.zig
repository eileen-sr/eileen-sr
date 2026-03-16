pub fn onGetChallengeCsReq(txn: Transaction, request: pb.GetChallengeCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    try txn.sendMessage(pb.GetChallengeScRsp{});
}

const Transaction = @import("../requests.zig").Transaction;
const pb = @import("proto").pb;
const std = @import("std");
