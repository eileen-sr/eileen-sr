pub const ID = enum(u32) {
    _,

    pub fn toInt(id: ID) u32 {
        return @intFromEnum(id);
    }
};

CocoonID: ID,
WorldLevel: u32,
PropID: u32,
MappingInfoID: u32,
StageID: u32,
StageIDList: []const u32,
DropList: []const u32,
StaminaCost: u32,
