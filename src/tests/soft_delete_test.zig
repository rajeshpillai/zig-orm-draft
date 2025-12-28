const std = @import("std");
const testing = std.testing;
const orm = @import("zig-orm");

// Test model with soft delete
const User = struct {
    id: ?i64 = null,
    name: []const u8,
    email: []const u8,
    deleted_at: ?i64 = null, // Soft delete field
};

// Test model without soft delete
const Post = struct {
    id: ?i64 = null,
    title: []const u8,
    body: []const u8,
};

test "soft delete - hasSoftDelete detection" {
    const Repo = orm.Repo;

    // User has deleted_at field
    try testing.expect(Repo(orm.sqlite.SQLite).hasSoftDelete(User));

    // Post does not have deleted_at field
    try testing.expect(!Repo(orm.sqlite.SQLite).hasSoftDelete(Post));
}

test "soft delete - whereNull and whereNotNull" {
    var query = try orm.builder.QueryBuilder(struct {
        pub const table_name = "users";
        pub const model_type = User;
        pub const columns = [_]orm.builder.Column{
            .{ .name = "id", .type = .integer },
            .{ .name = "name", .type = .text },
            .{ .name = "email", .type = .text },
            .{ .name = "deleted_at", .type = .integer },
        };
    }).init(testing.allocator);
    defer query.deinit();

    // Test whereNull
    _ = try query.whereNull("deleted_at");
    const sql_null = try query.toSql(testing.allocator);
    defer testing.allocator.free(sql_null);

    try testing.expect(std.mem.indexOf(u8, sql_null, "deleted_at IS NULL") != null);

    // Test whereNotNull
    var query2 = try orm.builder.QueryBuilder(struct {
        pub const table_name = "users";
        pub const model_type = User;
        pub const columns = [_]orm.builder.Column{
            .{ .name = "id", .type = .integer },
            .{ .name = "name", .type = .text },
            .{ .name = "email", .type = .text },
            .{ .name = "deleted_at", .type = .integer },
        };
    }).init(testing.allocator);
    defer query2.deinit();

    _ = try query2.whereNotNull("deleted_at");
    const sql_not_null = try query2.toSql(testing.allocator);
    defer testing.allocator.free(sql_not_null);

    try testing.expect(std.mem.indexOf(u8, sql_not_null, "deleted_at IS NOT NULL") != null);
}

test "soft delete - withTrashed and onlyTrashed" {
    var query = try orm.builder.QueryBuilder(struct {
        pub const table_name = "users";
        pub const model_type = User;
        pub const columns = [_]orm.builder.Column{
            .{ .name = "id", .type = .integer },
            .{ .name = "name", .type = .text },
            .{ .name = "email", .type = .text },
            .{ .name = "deleted_at", .type = .integer },
        };
    }).init(testing.allocator);
    defer query.deinit();

    // Test withTrashed
    _ = try query.withTrashed();
    try testing.expect(query.include_trashed == true);

    // Test onlyTrashed
    var query2 = try orm.builder.QueryBuilder(struct {
        pub const table_name = "users";
        pub const model_type = User;
        pub const columns = [_]orm.builder.Column{
            .{ .name = "id", .type = .integer },
            .{ .name = "name", .type = .text },
            .{ .name = "email", .type = .text },
            .{ .name = "deleted_at", .type = .integer },
        };
    }).init(testing.allocator);
    defer query2.deinit();

    _ = try query2.onlyTrashed();
    const sql = try query2.toSql(testing.allocator);
    defer testing.allocator.free(sql);

    try testing.expect(std.mem.indexOf(u8, sql, "deleted_at IS NOT NULL") != null);
}
