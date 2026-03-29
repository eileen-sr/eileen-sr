pub const ID = enum(u32) {
    _,

    pub fn toInt(id: ID) u32 {
        return @intFromEnum(id);
    }
};

pub const TutorialTriggerType = enum(u32) {
    None,
    TutorialFinish,
    GetItem,
    AnyAvatarToLevel,
    GetAvatar,
    FinishMainMission,
    TaskUnlock,
    TakeSubMission,
    EnterBattle,
    GetAnyLightCone,

    pub fn toInt(trigger_type: TutorialTriggerType) u32 {
        return @intFromEnum(trigger_type);
    }

    pub fn fromInt(n: u32) TutorialTriggerType {
        return if (n <= TutorialTriggerType.GetAnyLightCone) @enumFromInt(n) else TutorialTriggerType.None;
    }

    pub fn fromString(trigger_type: []const u8) ?TutorialTriggerType {
        return @import("std").meta.stringToEnum(TutorialTriggerType, trigger_type);
    }
};

TutorialID: ID,
TriggerParams: []const struct {
    TriggerType: TutorialTriggerType,
    TriggerParam: []const u8,
},
