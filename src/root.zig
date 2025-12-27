const std = @import("std");

pub const sqlite = @import("adapters/sqlite.zig");


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

test {
    _ = sqlite;
}

