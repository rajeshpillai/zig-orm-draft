const std = @import("std");

pub const Type = enum {
    Integer,
    Float,
    Text,
    Boolean,
    Blob,
};

pub const Value = union(Type) {
    Integer: i64,
    Float: f64,
    Text: []const u8,
    Boolean: bool,
    Blob: []const u8,
};

test "Type enum" {
    const t = Type.Integer;
    try std.testing.expectEqual(Type.Integer, t);
}
