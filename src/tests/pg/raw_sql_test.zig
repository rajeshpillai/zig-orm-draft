const std = @import("std");
const orm = @import("zig-orm");
const core_types = orm.types;

const CONN_STR = "postgresql://postgres:root123@localhost:5432/mydb";

const User = struct {
    id: i64,
    name: []const u8,
};

test "pg raw SQL query and execute" {
    const allocator = std.testing.allocator;
    const Repo = orm.Repo(orm.postgres.PostgreSQL);
    var repo = try Repo.init(allocator, CONN_STR);
    defer repo.deinit();

    // 1. Create table using raw execute
    try repo.adapter.exec("DROP TABLE IF EXISTS users_raw");
    try repo.execute("CREATE TABLE users_raw (id SERIAL PRIMARY KEY, name TEXT)", &.{});

    // 2. Insert data using raw execute with params (Postgres uses $1, $2)
    try repo.execute("INSERT INTO users_raw (id, name) VALUES ($1, $2)", &.{
        .{ .Integer = 1 },
        .{ .Text = "Alice" },
    });
    try repo.execute("INSERT INTO users_raw (id, name) VALUES ($1, $2)", &.{
        .{ .Integer = 2 },
        .{ .Text = "Bob" },
    });

    // 3. Query data using raw query with params
    const results = try repo.query(User, "SELECT id, name FROM users_raw WHERE id = $1", &.{.{ .Integer = 1 }});
    defer {
        for (results) |user| {
            allocator.free(user.name);
        }
        allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqual(@as(i64, 1), results[0].id);
    try std.testing.expectEqualSlices(u8, "Alice", results[0].name);

    // 4. Query all data
    const all_users = try repo.query(User, "SELECT id, name FROM users_raw ORDER BY id ASC", &.{});
    defer {
        for (all_users) |user| {
            allocator.free(user.name);
        }
        allocator.free(all_users);
    }

    try std.testing.expectEqual(@as(usize, 2), all_users.len);
    try std.testing.expectEqualSlices(u8, "Alice", all_users[0].name);
    try std.testing.expectEqualSlices(u8, "Bob", all_users[1].name);
}
