pub fn onGetTutorialCsReq(txn: Transaction, request: pb.GetTutorialCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    const tutorials = txn.assets.tables.tutorial.rows;

    var tutorial_list = try std.ArrayList(pb.Tutorial).initCapacity(
        txn.arena,
        tutorials.len,
    );

    for (tutorials) |tutorial| {
        tutorial_list.appendAssumeCapacity(.{
            .id = tutorial.TutorialID.toInt(),
            .status = pb.TutorialStatus.TUTORIAL_FINISH,
        });
    }

    try txn.sendMessage(pb.GetTutorialScRsp{
        .tutorial_list = tutorial_list,
    });
}

pub fn onGetTutorialGuideCsReq(txn: Transaction, request: pb.GetTutorialGuideCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    const tutorial_guides = txn.assets.tables.tutorial_guide.rows;

    var tutorial_guide_list = try std.ArrayList(pb.TutorialGuide).initCapacity(
        txn.arena,
        tutorial_guides.len,
    );

    for (tutorial_guides) |tutorial_guide| {
        tutorial_guide_list.appendAssumeCapacity(.{
            .id = tutorial_guide.ID,
            .status = pb.TutorialStatus.TUTORIAL_FINISH,
        });
    }

    try txn.sendMessage(pb.GetTutorialGuideScRsp{
        .tutorial_guide_list = tutorial_guide_list,
    });
}

const Transaction = @import("../requests.zig").Transaction;
const pb = @import("proto").pb;
const std = @import("std");
