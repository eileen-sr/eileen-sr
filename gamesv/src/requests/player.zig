const dev_account_channel_id: u32 = 10_000;

pub fn onPlayerGetTokenCsReq(txn: Transaction, request: pb.PlayerGetTokenCsReq) !void {
    const log = std.log.scoped(.player_get_token);
    try txn.modules.login.step.ensureExact(.pre_get_token);

    log.debug(
        "channel_id: {d}, uid: {d}, account_uid: '{s}'",
        .{ request.channel_id, request.uid, request.account_uid },
    );

    if (request.channel_id != dev_account_channel_id) {
        return txn.sendError(pb.PlayerGetTokenScRsp, .RET_ACCOUNT_PARA_ERROR);
    }

    const uid: Login.Uid = .fromInt(request.uid);

    if (uid == .none) {
        return txn.sendError(pb.PlayerGetTokenScRsp, .RET_ACCOUNT_PARA_ERROR);
    }

    store.loadModules(txn.gpa, txn.io, uid, txn.modules) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => |e| {
            log.err(
                "failed to load data for player with UID {d}: {t}",
                .{ uid.toInt(), e },
            );
            return txn.sendError(pb.PlayerGetTokenScRsp, .RET_PLAYER_DATA_ERROR);
        },
    };

    try txn.sendMessage(pb.PlayerGetTokenScRsp{
        .uid = uid.toInt(),
    });

    txn.modules.login.onPlayerTokenGot(uid);
}

pub fn onPlayerLoginCsReq(txn: Transaction, request: pb.PlayerLoginCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureExact(.has_player_token);

    const player = &txn.modules.player;

    try txn.sendMessage(pb.PlayerLoginScRsp{
        .basic_info = .{
            .nickname = player.nickname.view(),
            .level = player.level.toInt(),
            .stamina = player.stamina.toInt(),
            .mcoin = player.coins.get(.m).toInt(),
            .hcoin = player.coins.get(.h).toInt(),
            .scoin = player.coins.get(.s).toInt(),
            .world_level = player.world_level.toInt(),
        },
        .stamina = player.stamina.toInt(),
        .server_timestamp_ms = @bitCast(txn.time.toMilliseconds()),
    });

    txn.modules.login.onPlayerLoginSuccess();

    if (txn.modules.isFirstLogin()) {
        try txn.notify(.first_login, .{});
    }
}

pub fn onGetStaminaExchangeCsReq(txn: Transaction, request: pb.GetStaminaExchangeCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    try txn.sendMessage(pb.GetStaminaExchangeScRsp{});
}

pub fn onSyncTimeCsReq(txn: Transaction, request: pb.SyncTimeCsReq) !void {
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    try txn.sendMessage(pb.SyncTimeScRsp{
        .client_time_ms = request.client_time_ms,
        .server_time_ms = @bitCast(txn.time.toMilliseconds()),
    });
}

const Login = modules.Login;
const Transaction = @import("../requests.zig").Transaction;

const store = @import("../store.zig");
const modules = @import("../modules.zig");
const pb = @import("proto").pb;
const std = @import("std");
