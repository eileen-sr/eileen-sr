pub const ID = enum(u32) {
    _,

    pub fn toInt(id: ID) u32 {
        return @intFromEnum(id);
    }
};

StageID: ID,
MonsterList: []const struct {
    Monster0: u32,
    Monster1: u32,
    Monster2: u32,
    Monster3: u32,
    Monster4: u32,
},
