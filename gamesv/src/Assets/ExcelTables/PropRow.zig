pub const ID = enum(u32) {
    _,

    pub fn toInt(id: ID) u32 {
        return @intFromEnum(id);
    }
};

pub const Type = enum {
    PROP_NONE,
    PROP_ORDINARY,
    PROP_SUMMON,
    PROP_DESTRUCT,
    PROP_SPRING,
    PROP_PLATFORM,
    PROP_TREASURE_CHEST,
    PROP_MATERIAL_ZONE,
    PROP_COCOON,
    PROP_MAPPINGINFO,
    PROP_PUZZLES,
    PROP_ELEVATOR,
};

pub const State = enum(u32) {
    Closed,
    Open,
    Locked,
    BridgeState1,
    BridgeState2,
    BridgeState3,
    BridgeState4,
    CheckPointDisable,
    CheckPointEnable,
    TriggerDisable,
    TriggerEnable,
    ChestLocked,
    ChestClosed,
    ChestUsed,
    Elevator1,
    Elevator2,
    Elevator3,

    pub fn toInt(state: State) u32 {
        return @intFromEnum(state);
    }

    pub fn fromString(state: []const u8) ?State {
        return @import("std").meta.stringToEnum(State, state);
    }
};

PropID: ID,
PropType: Type,
PrefabPath: []const u8,
InitLevelGraph: []const u8,
PropStateList: []const State,
