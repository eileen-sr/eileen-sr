pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const eileen_proto_gen = b.addExecutable(.{
        .name = "eileen_proto_gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("proto/gen/src/main.zig"),
            .optimize = optimize,
            .target = b.graph.host,
        }),
    });

    const compile_proto = b.addRunArtifact(eileen_proto_gen);
    compile_proto.expectExitCode(0);
    const pb_generated = compile_proto.captureStdOut(.{ .basename = "hkrpg_generated.zig" });

    for (proto_files) |file| {
        compile_proto.addFileArg(b.path(file));
    }

    const proto = b.createModule(.{
        .root_source_file = b.path("proto/src/root.zig"),
        .optimize = optimize,
        .target = target,
    });

    proto.addAnonymousImport("hkrpg_generated", .{ .root_source_file = pb_generated });

    const common = b.createModule(.{
        .root_source_file = b.path("common/src/root.zig"),
        .optimize = optimize,
        .target = target,
    });

    const dpsv = b.addExecutable(.{
        .name = "eileen-dpsv",
        .root_module = b.createModule(.{
            .root_source_file = b.path("dpsv/src/main.zig"),
            .imports = &.{.{ .name = "common", .module = common }},
            .target = target,
            .optimize = optimize,
        }),
    });

    const gamesv = b.addExecutable(.{
        .name = "eileen-gamesv",
        .root_module = b.createModule(.{
            .root_source_file = b.path("gamesv/src/main.zig"),
            .imports = &.{
                .{ .name = "proto", .module = proto },
                .{ .name = "common", .module = common },
            },
            .target = target,
            .optimize = optimize,
        }),
    });

    gamesv.step.dependOn(&compile_proto.step);

    b.step(
        "run-dpsv",
        "Run the dispatch server",
    ).dependOn(&b.addRunArtifact(dpsv).step);

    b.step(
        "run-gamesv",
        "Run the game server",
    ).dependOn(&b.addRunArtifact(gamesv).step);

    b.installArtifact(dpsv);
    b.installArtifact(gamesv);
}

const proto_files: []const []const u8 = &.{
    "proto/pb/common.define.proto",
    "proto/pb/common.gamecore.proto",
    "proto/pb/common.retcode.proto",
    "proto/pb/cs.adventure.proto",
    "proto/pb/cs.avatar.proto",
    "proto/pb/cs.battle.proto",
    "proto/pb/cs.challenge.proto",
    "proto/pb/cs.common.proto",
    "proto/pb/cs.item.proto",
    "proto/pb/cs.lineup.proto",
    "proto/pb/cs.mail.proto",
    "proto/pb/cs.maze.proto",
    "proto/pb/cs.mission.proto",
    "proto/pb/cs.player.proto",
    "proto/pb/cs.plot.proto",
    "proto/pb/cs.quest.proto",
    "proto/pb/cs.scene.proto",
    "proto/pb/cs.shop.proto",
    "proto/pb/cs.stage.proto",
    "proto/pb/cs.sync.proto",
    "proto/pb/cs.tutorial.proto",
    "proto/pb/cs.waypoint.proto",
    "proto/pb/head.proto",
};

const Build = std.Build;
const std = @import("std");
