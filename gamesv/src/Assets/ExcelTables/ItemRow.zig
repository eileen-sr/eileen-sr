pub const ID = enum(u32) {
    _,

    pub fn toInt(id: ID) u32 {
        return @intFromEnum(id);
    }
};

pub const Type = enum {
    Virtual,
    Placeholder,
    Material,
    AvatarCard,
    Equipment,
    Gift,
    Mission,
    Book,
    Food,
};

ItemID: ID,
ItemType: Type,
PileLimit: u32,
