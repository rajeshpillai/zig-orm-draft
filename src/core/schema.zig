const std = @import("std");

/// Schema constraint definitions
pub const Constraint = union(enum) {
    unique: UniqueConstraint,
    foreign_key: ForeignKeyConstraint,
    check: CheckConstraint,

    /// Unique constraint on one or more fields
    pub const UniqueConstraint = struct {
        fields: []const []const u8, // Can be composite (multiple fields)
        name: ?[]const u8 = null, // Optional constraint name for error messages
    };

    /// Foreign key constraint
    pub const ForeignKeyConstraint = struct {
        field: []const u8,
        references_table: []const u8,
        references_field: []const u8,
        on_delete: ?ForeignKeyAction = null,
        on_update: ?ForeignKeyAction = null,

        pub const ForeignKeyAction = enum {
            cascade,
            set_null,
            restrict,
            no_action,
        };
    };

    /// Check constraint (SQL expression)
    pub const CheckConstraint = struct {
        field: []const u8,
        condition: []const u8, // SQL expression, e.g., "age >= 18"
        name: ?[]const u8 = null,
    };
};

test "constraint types" {
    const unique = Constraint{
        .unique = .{
            .fields = &[_][]const u8{"email"},
            .name = "unique_email",
        },
    };

    try std.testing.expect(unique == .unique);
    try std.testing.expectEqual(@as(usize, 1), unique.unique.fields.len);
    try std.testing.expectEqualStrings("email", unique.unique.fields[0]);
}

test "composite unique constraint" {
    const unique = Constraint{
        .unique = .{
            .fields = &[_][]const u8{ "user_id", "slug" },
        },
    };

    try std.testing.expectEqual(@as(usize, 2), unique.unique.fields.len);
}

test "foreign key constraint" {
    const fk = Constraint{
        .foreign_key = .{
            .field = "user_id",
            .references_table = "users",
            .references_field = "id",
            .on_delete = .cascade,
        },
    };

    try std.testing.expect(fk == .foreign_key);
    try std.testing.expectEqualStrings("user_id", fk.foreign_key.field);
}

test "check constraint" {
    const check = Constraint{
        .check = .{
            .field = "age",
            .condition = "age >= 18",
            .name = "age_check",
        },
    };

    try std.testing.expect(check == .check);
    try std.testing.expectEqualStrings("age >= 18", check.check.condition);
}
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

        pub fn update(allocator: std.mem.Allocator) !query.Update(Self) {
            return try query.Update(Self).init(allocator);
        }

        pub fn delete(allocator: std.mem.Allocator) !query.Delete(Self) {
            return try query.Delete(Self).init(allocator);
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
