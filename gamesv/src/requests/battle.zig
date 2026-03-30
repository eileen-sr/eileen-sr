pub fn onGetCurBattleInfoCsReq(txn: Transaction, request: pb.GetCurBattleInfoCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    try txn.sendMessage(pb.GetCurBattleInfoScRsp{});
}

pub fn onPVEBattleResultCsReq(txn: Transaction, request: pb.PVEBattleResultCsReq) !void {
    try txn.modules.login.step.ensureExact(.finished);

    const challenge = &txn.modules.challenge;
    const scene = &txn.modules.scene;

    if (request.end_status) |status| if (status == .BATTLE_END_WIN) {
        try scene.destroyEntities(&txn, txn.modules.battle.monster_entity_id_list.items);

        switch (challenge.stage) {
            .low => {
                challenge.round_cnt = request.stt.?.round_cnt;
                challenge.stage = .high;

                const id = try scene.entity_manager.find(.{ .kind = .prop, .config_id = 105 }); // AirWall
                try scene.updatePropState(&txn, id, .Open);
            },
            .high => {
                challenge.round_cnt += request.stt.?.round_cnt;

                const id = try scene.entity_manager.find(.{ .kind = .prop, .config_id = 104 }); // TreasureBox
                try scene.updatePropState(&txn, id, .ChestClosed);
            },
            .none => {},
        }
    };

    try txn.sendMessage(pb.PVEBattleResultScRsp{
        .stage_id = request.stage_id,
        .end_status = request.end_status,
    });
}

const Transaction = @import("../requests.zig").Transaction;
const pb = @import("proto").pb;
const std = @import("std");
