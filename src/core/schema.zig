const std = @import("std");
const Type = @import("types.zig").Type;
const query = @import("../builder/query.zig");

pub const Column = struct {
    name: []const u8,
    type: Type,
};

pub fn Table(comptime T: type, comptime name: []const u8) type {
    return struct {
        pub const table_name = name;
        pub const model_type = T;
        pub const columns = deriveColumns(T);

        const Self = @This();
        // Insert helper kept for convenience, but Select removed in favor of `from`
        pub fn insert(allocator: std.mem.Allocator) !query.Insert(Self) {
            return try query.Insert(Self).init(allocator);
        }
    };
}

fn deriveColumns(comptime T: type) []const Column {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") @compileError("Table model must be a struct");

    var cols: []const Column = &.{};
    for (type_info.@"struct".fields) |field| {
        const col_type = matchType(field.type);
        cols = cols ++ &[_]Column{
            .{ .name = field.name, .type = col_type },
        };
    }
    return cols;
}

fn matchType(comptime T: type) Type {
    return switch (T) {
        i64, i32, isize, usize, u64, u32 => .Integer,
        f64, f32 => .Float,
        []const u8 => .Text,
        bool => .Boolean,
        else => @compileError("Unsupported type: " ++ @typeName(T)),
    };
}

test "derive columns" {
    const User = struct {
        id: i64,
        name: []const u8,
        active: bool,
    };
    const Users = Table(User, "users");

    try std.testing.expectEqualStrings("users", Users.table_name);
    try std.testing.expectEqual(3, Users.columns.len);
    try std.testing.expectEqualStrings("id", Users.columns[0].name);
    try std.testing.expect(Users.columns[0].type == .Integer);
    try std.testing.expectEqualStrings("name", Users.columns[1].name);
    try std.testing.expect(Users.columns[1].type == .Text);
}

test "explicit sql" {
    const User = struct {
        id: i64,
        name: []const u8,
        active: bool,
    };
    const Users = Table(User, "users");

    // Select with `from`
    var val = try query.from(Users, std.testing.allocator);
    defer val.deinit();
    const sql = try val.toSql(std.testing.allocator);

    defer std.testing.allocator.free(sql);
    try std.testing.expectEqualStrings("SELECT id, name, active FROM users", sql);

    // Insert
    var insert_query = try Users.insert(std.testing.allocator);
    defer insert_query.deinit();

    try insert_query.add(.{ .id = 1, .name = "Alice", .active = true });
    try insert_query.add(.{ .id = 2, .name = "Bob", .active = false });

    const insert_sql = try insert_query.toSql();
    defer std.testing.allocator.free(insert_sql);
    // Note: Parameter placeholders '?' used for now
    try std.testing.expectEqualStrings("INSERT INTO users (id, name, active) VALUES (?, ?, ?), (?, ?, ?)", insert_sql);
}
