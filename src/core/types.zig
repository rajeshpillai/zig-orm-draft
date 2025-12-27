const std = @import("std");

/// Core types supported by the ORM
pub const Type = union(enum) {
    Integer,
    Float,
    Text,
    Boolean,
    Blob,
};

test "core types" {
    const t = Type.Integer;
    try std.testing.expect(t == .Integer);
}
