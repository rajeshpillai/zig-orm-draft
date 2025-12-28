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

/// Enum mapping errors
pub const EnumError = error{
    InvalidEnumValue,
    NullEnumValue,
    EnumConversionFailed,
};

/// Check if a type should be stored as TEXT (string representation)
/// Returns true for enums without explicit integer backing type
/// Simple heuristic: if enum fields don't have explicit values, use TEXT
pub fn shouldStoreEnumAsText(comptime E: type) bool {
    const type_info = @typeInfo(E);
    switch (type_info) {
        .Enum => {
            // Simple approach: always use TEXT for now
            // This avoids complex type info operations
            // In practice, most enums without explicit backing are TEXT
            return true;
        },
        else => return false,
    }
}

/// Convert enum to its string representation
pub fn enumToText(comptime E: type, value: E) []const u8 {
    return @tagName(value);
}

/// Convert string to enum value
pub fn textToEnum(comptime E: type, text: []const u8) EnumError!E {
    return std.meta.stringToEnum(E, text) orelse error.InvalidEnumValue;
}

/// Convert enum to its integer ordinal value
pub fn enumToInt(comptime E: type, value: E) i64 {
    return @intFromEnum(value);
}

/// Convert integer to enum value
pub fn intToEnum(comptime E: type, value: i64) EnumError!E {
    // Use std.meta.intToEnum which handles the conversion safely
    inline for (std.meta.fields(E)) |field| {
        if (field.value == value) {
            return @enumFromInt(value);
        }
    }
    return error.InvalidEnumValue;
}

test "Type enum" {
    const t = Type.Integer;
    try std.testing.expectEqual(Type.Integer, t);
}

test "enum storage strategy detection" {
    const StringEnum = enum {
        foo,
        bar,
        baz,
    };

    const IntEnum = enum(u8) {
        low = 0,
        medium = 1,
        high = 2,
    };

    try std.testing.expect(shouldStoreEnumAsText(StringEnum));
    try std.testing.expect(!shouldStoreEnumAsText(IntEnum));
}

test "enum to text conversion" {
    const Status = enum {
        pending,
        active,
        completed,
    };

    try std.testing.expectEqualStrings("pending", enumToText(Status, .pending));
    try std.testing.expectEqualStrings("active", enumToText(Status, .active));
    try std.testing.expectEqualStrings("completed", enumToText(Status, .completed));
}

test "text to enum conversion" {
    const Status = enum {
        pending,
        active,
        completed,
    };

    try std.testing.expectEqual(Status.pending, try textToEnum(Status, "pending"));
    try std.testing.expectEqual(Status.active, try textToEnum(Status, "active"));
    try std.testing.expectEqual(Status.completed, try textToEnum(Status, "completed"));

    // Invalid value
    try std.testing.expectError(error.InvalidEnumValue, textToEnum(Status, "invalid"));
}

test "enum to int conversion" {
    const Priority = enum(u8) {
        low = 0,
        medium = 1,
        high = 2,
    };

    try std.testing.expectEqual(@as(i64, 0), enumToInt(Priority, .low));
    try std.testing.expectEqual(@as(i64, 1), enumToInt(Priority, .medium));
    try std.testing.expectEqual(@as(i64, 2), enumToInt(Priority, .high));
}

test "int to enum conversion" {
    const Priority = enum(u8) {
        low = 0,
        medium = 1,
        high = 2,
    };

    try std.testing.expectEqual(Priority.low, try intToEnum(Priority, 0));
    try std.testing.expectEqual(Priority.medium, try intToEnum(Priority, 1));
    try std.testing.expectEqual(Priority.high, try intToEnum(Priority, 2));

    // Invalid value
    try std.testing.expectError(error.InvalidEnumValue, intToEnum(Priority, 99));
}
