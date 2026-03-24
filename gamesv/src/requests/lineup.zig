pub fn onGetAllLineupDataCsReq(txn: Transaction, request: pb.GetAllLineupDataCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    const lineup = &txn.modules.lineup;

    var lineup_list = try std.ArrayList(pb.LineupInfo).initCapacity(txn.arena, lineup.list.len);
    var avatar_buf = try txn.arena.alloc(pb.LineupAvatar, lineup.list.len * Lineup.Avatar.Slot.count);
    const slice = lineup.list.slice();

    for (0..lineup.list.len) |index| packLineup(
        lineup_list.addOneAssumeCapacity(),
        avatar_buf[index * Lineup.Avatar.Slot.count ..][0..Lineup.Avatar.Slot.count],
        slice,
        @truncate(index),
    );

    try txn.sendMessage(pb.GetAllLineupDataScRsp{
        .cur_index = lineup.active_index.toInt(),
        .lineup_list = lineup_list,
    });
}

pub fn onGetCurLineupDataCsReq(txn: Transaction, request: pb.GetCurLineupDataCsReq) !void {
    _ = request;
    try txn.modules.login.step.ensureAtLeast(.waiting_key_packets);

    const lineup = &txn.modules.lineup;
    const slice = lineup.list.slice();
    const index = lineup.active_index.toInt();

    var avatar_buf: [Lineup.Avatar.Slot.count]pb.LineupAvatar = undefined;

    var rsp: pb.GetCurLineupDataScRsp = .{ .lineup = .init };
    packLineup(&rsp.lineup.?, &avatar_buf, slice, index);

    try txn.sendMessage(rsp);
}

pub fn onSetLineupNameCsReq(txn: Transaction, request: pb.SetLineupNameCsReq) !void {
    try txn.modules.login.step.ensureExact(.finished);

    txn.modules.lineup.list.items(.name)[request.index].set(request.name) catch {
        return txn.sendError(pb.SetLineupNameScRsp, .RET_LINEUP_NAME_FORMAT_ERROR);
    };

    try txn.notify(.lineup_name_changed, .{});

    try txn.sendMessage(pb.SetLineupNameScRsp{
        .name = request.name,
        .index = request.index,
    });
}

pub fn onSwitchLineupIndexCsReq(txn: Transaction, request: pb.SwitchLineupIndexCsReq) !void {
    try txn.modules.login.step.ensureExact(.finished);

    if (request.index >= txn.modules.lineup.list.len) {
        return txn.sendError(pb.SwitchLineupIndexScRsp, .RET_LINEUP_INVALID_INDEX);
    }

    txn.modules.lineup.active_index = @enumFromInt(request.index);

    try txn.notify(.lineup_index_changed, .{});

    try txn.sendMessage(pb.SwitchLineupIndexScRsp{
        .index = request.index,
    });
}

pub fn onChangeLineupLeaderCsReq(txn: Transaction, request: pb.ChangeLineupLeaderCsReq) !void {
    try txn.modules.login.step.ensureExact(.finished);

    const slot = Lineup.Avatar.Slot.fromInt(request.slot) catch {
        return txn.sendError(pb.ChangeLineupLeaderScRsp, .RET_LINEUP_INVALID_MEMBER_POS);
    };

    const lineup = &txn.modules.lineup;
    const index = lineup.active_index.toInt();
    const slice = lineup.list.slice();

    if (slice.items(.slots)[index].get(slot) == null) {
        return txn.sendError(pb.ChangeLineupLeaderScRsp, .RET_LINEUP_AVATAR_NOT_EXIST);
    }

    if (slice.items(.leader)[index] == slot) {
        return txn.sendError(pb.ChangeLineupLeaderScRsp, .RET_LINEUP_SAME_LEADER_SLOT);
    }

    slice.items(.leader)[index] = slot;
    try txn.notify(.lineup_leader_changed, .{ .new_slot = slot });

    try txn.sendMessage(pb.ChangeLineupLeaderScRsp{
        .slot = request.slot,
    });
}

pub fn onJoinLineupCsReq(txn: Transaction, request: pb.JoinLineupCsReq) !void {
    try txn.modules.login.step.ensureExact(.finished);

    const slot = Lineup.Avatar.Slot.fromInt(request.slot) catch {
        return txn.sendError(pb.JoinLineupScRsp, .RET_LINEUP_INVALID_MEMBER_POS);
    };

    const lineup = &txn.modules.lineup;
    const index = lineup.getRequestIndex(request.index, request.extra_lineup_type) catch {
        return txn.sendError(pb.JoinLineupScRsp, .RET_LINEUP_INVALID_INDEX);
    };

    const slice = lineup.list.slice();

    if (!txn.modules.avatar.index.contains(@enumFromInt(request.avatar_id))) {
        return txn.sendError(pb.JoinLineupScRsp, .RET_LINEUP_AVATAR_NOT_EXIST);
    }

    for (slice.items(.slots)[index].values) |maybe_avatar| if (maybe_avatar) |avatar| {
        if (avatar.id.toInt() == request.avatar_id) {
            return txn.sendError(pb.JoinLineupScRsp, .RET_LINEUP_AVATAR_ALREADY_IN);
        }
    };

    slice.items(.slots)[index].set(slot, .{ .id = @enumFromInt(request.avatar_id) });

    const leader = &slice.items(.leader)[index];
    if (slice.items(.slots)[index].values[leader.toInt()] == null) leader.* = slot;

    try txn.notify(.lineup_slots_changed, .{});

    try sendLineupSync(&txn, lineup, index);
    try txn.sendMessage(pb.JoinLineupScRsp{});
}

pub fn onQuitLineupCsReq(txn: Transaction, request: pb.QuitLineupCsReq) !void {
    try txn.modules.login.step.ensureExact(.finished);

    const lineup = &txn.modules.lineup;
    const index = lineup.getRequestIndex(request.index, request.extra_lineup_type) catch {
        return txn.sendError(pb.QuitLineupScRsp, .RET_LINEUP_INVALID_INDEX);
    };

    const slice = lineup.list.slice();

    var requested_slot: ?Lineup.Avatar.Slot = null;
    var total_count: usize = 0;

    for (slice.items(.slots)[index].values, 0..) |maybe_avatar, i| if (maybe_avatar) |avatar| {
        total_count += 1;
        if (avatar.id.toInt() == request.avatar_id) {
            requested_slot = @enumFromInt(i);
        }
    };

    const slot = requested_slot orelse
        return txn.sendError(pb.QuitLineupScRsp, .RET_LINEUP_AVATAR_NOT_EXIST);

    if (total_count == 1) {
        return txn.sendError(pb.QuitLineupScRsp, .RET_LINEUP_ONLY_ONE_MEMBER);
    }

    slice.items(.slots)[index].set(slot, null);

    if (slot == slice.items(.leader)[index]) {
        for (slice.items(.slots)[index].values, 0..) |avatar, i| if (avatar != null) {
            slice.items(.leader)[index] = @enumFromInt(i);
            break;
        };
    }

    try txn.notify(.lineup_slots_changed, .{});

    try sendLineupSync(&txn, lineup, index);
    try txn.sendMessage(pb.QuitLineupScRsp{});
}

pub fn onSwapLineupCsReq(txn: Transaction, request: pb.SwapLineupCsReq) !void {
    try txn.modules.login.step.ensureExact(.finished);

    const lineup = &txn.modules.lineup;
    const index = lineup.getRequestIndex(request.index, request.extra_lineup_type) catch {
        return txn.sendError(pb.SwapLineupScRsp, .RET_LINEUP_INVALID_INDEX);
    };

    const src_slot = Lineup.Avatar.Slot.fromInt(request.src_slot) catch {
        return txn.sendError(pb.SwapLineupScRsp, .RET_LINEUP_INVALID_MEMBER_POS);
    };

    const dst_slot = Lineup.Avatar.Slot.fromInt(request.dst_slot) catch {
        return txn.sendError(pb.SwapLineupScRsp, .RET_LINEUP_INVALID_MEMBER_POS);
    };

    const slice = lineup.list.slice();

    const t = slice.items(.slots)[index].get(dst_slot);
    slice.items(.slots)[index].set(dst_slot, slice.items(.slots)[index].get(src_slot));
    slice.items(.slots)[index].set(src_slot, t);

    try txn.notify(.lineup_slots_changed, .{});

    try sendLineupSync(&txn, lineup, index);
    try txn.sendMessage(pb.SwapLineupScRsp{});
}

fn sendLineupSync(txn: *const Transaction, lineup: *const Lineup, index: u32) !void {
    var avatar_buf: [Lineup.Avatar.Slot.count]pb.LineupAvatar = undefined;
    const slice = lineup.list.slice();

    try syncAvatars(txn, &slice.items(.slots)[index]);

    var notify: pb.SyncLineupNotify = .{ .lineup = .init };
    packLineup(&notify.lineup.?, &avatar_buf, slice, index);

    try txn.sendMessage(notify);
}

fn packAvatar(out: *pb.LineupAvatar, avatar: *const Lineup.Avatar, slot: u32) void {
    out.* = .{
        .slot = slot,
        .id = avatar.id.toInt(),
        .hp = avatar.hp.toInt(),
        .sp = avatar.sp.toInt(),
        .satiety = avatar.satiety.toInt(),
        .avatar_type = .AVATAR_FORMAL_TYPE,
    };
}

fn packLineup(
    out: *pb.LineupInfo,
    avatar_buf: *[Lineup.Avatar.Slot.count]pb.LineupAvatar,
    slice: MultiArrayList(Lineup.Data).Slice,
    index: u32,
) void {
    var avatar_list: ArrayList(pb.LineupAvatar) = .initBuffer(avatar_buf);

    for (slice.items(.slots)[index].values, 0..) |maybe_avatar, slot| if (maybe_avatar) |*avatar| {
        packAvatar(avatar_list.addOneAssumeCapacity(), avatar, @truncate(slot));
    };

    out.* = .{
        .avatar_list = avatar_list,
        .mp = slice.items(.mp)[index].toInt(),
        .name = slice.items(.name)[index].view(),
        .is_virtual = slice.items(.flags)[index].virtual,
        .leader_slot = slice.items(.leader)[index].toInt(),
        .index = index,
        .extra_lineup_type = if (slice.items(.flags)[index].challenge) .LINEUP_CHALLENGE else .LINEUP_NONE,
    };
}

fn syncAvatars(txn: *const Transaction, avatars: *const std.EnumArray(Lineup.Avatar.Slot, ?Lineup.Avatar)) !void {
    txn.modules.scene.syncAvatars(avatars);
    try txn.notify(.scene_changed, .{});

    const slice = txn.modules.scene.entity_list.slice();

    var entity_info_list = try std.ArrayList(pb.SceneEntityInfo)
        .initCapacity(txn.arena, Lineup.Avatar.Slot.count);

    for (0..entity_info_list.capacity) |i| {
        const out = entity_info_list.addOneAssumeCapacity();
        @import("./scene.zig").packEntity(
            out,
            slice,
            i,
            txn.modules.login.uid,
        );
    }

    try txn.sendMessage(pb.SceneEntityUpdateScNotify{ .entity_list = entity_info_list });
}

const Lineup = modules.Lineup;
const modules = @import("../modules.zig");

const ArrayList = std.ArrayList;
const MultiArrayList = std.MultiArrayList;

const Transaction = @import("../requests.zig").Transaction;
const pb = @import("proto").pb;
const std = @import("std");
