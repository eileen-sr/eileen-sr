pub const ID = enum(u32) {
    _,

    pub fn toInt(id: ID) u32 {
        return @intFromEnum(id);
    }
};

ChallengeMazeID: ID,
MapEntranceID: u32,
StageID: []const u32,
ChallengeTargetID: [3]u32,
