pub const ID = enum(u32) {
    _,

    pub fn toInt(id: ID) u32 {
        return @intFromEnum(id);
    }
};

EquipmentID: ID,
Rarity: u8,
AvatarBaseType: []const u8,
MaxPromotion: u8,
MaxRank: u8,
ExpType: u8,
SkillID: u32,
ExpProvide: u32,
CoinCost: u32,
RankUpCost: u32,
