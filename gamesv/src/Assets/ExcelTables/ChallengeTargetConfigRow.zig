pub const ID = enum(u32) {
    _,

    pub fn toInt(id: ID) u32 {
        return @intFromEnum(id);
    }
};

pub const Type = enum {
    NONE,
    ROUNDS,
};

ChallengeTargetID: ID,
ChallengeTargetType: Type,
ChallengeTargetParam: u32,
