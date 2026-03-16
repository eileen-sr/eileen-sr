const head_magic: u32 = 0x01234567;
const tail_magic: u32 = 0x89ABCDEF;

const packet_head_len: usize = 12;
const packet_tail_len: usize = 4;

pub const DeserializeError = error{
    NotComplete,
    NotCorrect,
};

cmd_id: u16,
head: []const u8,
body: []const u8,

pub fn isComplete(buf: []const u8) bool {
    if (buf.len < packet_head_len) return false;

    const head_len = std.mem.readInt(u16, buf[6..8], .big);
    const body_len = std.mem.readInt(u32, buf[8..12], .big);

    return buf.len >= packet_head_len + head_len + body_len + packet_tail_len;
}

pub fn deserialize(buf: []const u8) DeserializeError!NetPacket {
    if (buf.len < packet_head_len) return error.NotComplete;

    if (head_magic != std.mem.readInt(u32, buf[0..4], .big))
        return error.NotCorrect;

    const head_len = std.mem.readInt(u16, buf[6..8], .big);
    const body_len = std.mem.readInt(u32, buf[8..12], .big);

    if (buf.len < head_len + body_len + packet_tail_len)
        return error.NotComplete;

    if (tail_magic != std.mem.readInt(u32, buf[12 + head_len + body_len ..][0..4], .big))
        return error.NotCorrect;

    return .{
        .cmd_id = std.mem.readInt(u16, buf[4..6], .big),
        .head = buf[packet_head_len..][0..head_len],
        .body = buf[packet_head_len + head_len ..][0..body_len],
    };
}

pub fn size(np: *const NetPacket) usize {
    return packet_head_len + np.head.len + np.body.len + packet_tail_len;
}

// Does not flush the writer.
pub fn serialize(writer: *Io.Writer, message: anytype) Io.Writer.Error!void {
    try writer.writeInt(u32, head_magic, .big);
    try writer.writeInt(u16, @intFromEnum(proto.typeOf(message)), .big);
    try writer.writeInt(u16, 0, .big); // head_len
    try writer.writeInt(u32, @intCast(proto.encodingLength(message)), .big);
    try proto.encodeMessage(writer, message);
    try writer.writeInt(u32, tail_magic, .big);
}

const Io = std.Io;
const proto = @import("proto");
const std = @import("std");
const NetPacket = @This();
