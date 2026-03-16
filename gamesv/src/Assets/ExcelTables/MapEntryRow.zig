pub const ID = enum(u32) {
    _,

    pub fn toInt(id: ID) u32 {
        return @intFromEnum(id);
    }
};

EntryID: ID,
PlaneID: u32,
FloorID: u32,
