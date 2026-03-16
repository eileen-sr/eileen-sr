pub fn onGetTutorialCsReq(txn: Transaction, request: pb.GetTutorialCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    try txn.sendMessage(pb.GetTutorialScRsp{});
}

pub fn onGetTutorialGuideCsReq(txn: Transaction, request: pb.GetTutorialGuideCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    try txn.sendMessage(pb.GetTutorialGuideScRsp{});
}

const Transaction = @import("../requests.zig").Transaction;
const pb = @import("proto").pb;
const std = @import("std");
