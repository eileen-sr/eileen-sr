pub const ID = enum(u32) {
    _,

    pub fn toInt(id: ID) u32 {
        return @intFromEnum(id);
    }
};

EventID: ID,
WorldLevel: u32,
StageID: u32,
