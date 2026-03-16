pub const ID = enum(u32) {
    _,

    pub fn toInt(id: ID) u32 {
        return @intFromEnum(id);
    }
};

AvatarID: ID,
AdventurePlayerID: u32,
AvatarVOTag: []const u8,
Rarity: u32,
JsonPath: []const u8,
NatureID: u32,
DamageType: []const u8,
ExpGroup: u32,
MaxPromotion: u32,
MaxRank: u32,
RankUpCostList: []const []const u8,
MaxRankRepay: u32,
SkillList: []const u32,
AvatarBaseType: []const u8,
Release: bool,
