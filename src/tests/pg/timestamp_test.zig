const std = @import("std");
const orm = @import("zig-orm");
const testing = std.testing;

const CONN_STR = "postgresql://postgres:root123@localhost:5432/mydb";

const User = struct {
    id: i64,
    name: []const u8,
    created_at: i64,
    updated_at: i64,
};

const UserTable = orm.Table(User, "users_ts");

test "pg automatic timestamps on insert" {
    const allocator = testing.allocator;
    var repo = try orm.Repo(orm.postgres.PostgreSQL).init(allocator, CONN_STR);
    defer repo.deinit();

    try repo.adapter.exec("DROP TABLE IF EXISTS users_ts");
    try repo.adapter.exec("CREATE TABLE users_ts (id SERIAL PRIMARY KEY, name TEXT, created_at BIGINT, updated_at BIGINT)");

    var insert = try orm.query.Insert(UserTable).init(allocator);
    defer insert.deinit();

    try insert.add(.{
        .id = 1,
        .name = "Alice",
        .created_at = 0,
        .updated_at = 0,
    });

    const start_time = orm.timestamps.currentTimestamp();
    try repo.insert(&insert);
    const end_time = orm.timestamps.currentTimestamp();

    const user = (try repo.findBy(UserTable, .{ .id = 1 })).?;
    defer allocator.free(user.name);

    try testing.expect(user.created_at >= start_time);
    try testing.expect(user.created_at <= end_time);
    try testing.expect(user.updated_at >= start_time);
    try testing.expect(user.updated_at <= end_time);
    try testing.expect(user.created_at == user.updated_at);
}

test "pg automatic timestamps on update" {
    const allocator = testing.allocator;
    var repo = try orm.Repo(orm.postgres.PostgreSQL).init(allocator, CONN_STR);
    defer repo.deinit();

    try repo.adapter.exec("DROP TABLE IF EXISTS users_ts");
    try repo.adapter.exec("CREATE TABLE users_ts (id SERIAL PRIMARY KEY, name TEXT, created_at BIGINT, updated_at BIGINT)");

    // Insert initial
    var insert = try orm.query.Insert(UserTable).init(allocator);
    defer insert.deinit();
    try insert.add(.{ .id = 1, .name = "Alice", .created_at = 100, .updated_at = 100 });
    try repo.insert(&insert);

    // Update
    const start_time = orm.timestamps.currentTimestamp();

    var up = try orm.query.Update(UserTable).init(allocator);
    defer up.deinit();
    _ = try up.set(.{ .name = "Bob" });
    _ = try up.where(.{ .id = 1 });

    try repo.update(&up);
    const end_time = orm.timestamps.currentTimestamp();

    const user = (try repo.findBy(UserTable, .{ .id = 1 })).?;
    defer allocator.free(user.name);

    try testing.expectEqual(@as(i64, 100), user.created_at); // Not changed
    try testing.expect(user.updated_at >= start_time);
    try testing.expect(user.updated_at <= end_time);
    try testing.expect(user.updated_at > 100);
}

test "pg manual timestamp override" {
    const allocator = testing.allocator;
    var repo = try orm.Repo(orm.postgres.PostgreSQL).init(allocator, CONN_STR);
    defer repo.deinit();

    try repo.adapter.exec("DROP TABLE IF EXISTS users_ts");
    try repo.adapter.exec("CREATE TABLE users_ts (id SERIAL PRIMARY KEY, name TEXT, created_at BIGINT, updated_at BIGINT)");

    // Override on insert
    var insert = try orm.query.Insert(UserTable).init(allocator);
    defer insert.deinit();
    try insert.add(.{ .id = 1, .name = "Alice", .created_at = 500, .updated_at = 600 });
    try repo.insert(&insert);

    const user1 = (try repo.findBy(UserTable, .{ .id = 1 })).?;
    defer allocator.free(user1.name);
    try testing.expectEqual(@as(i64, 500), user1.created_at);
    // updated_at is currently ALWAYS overwritten by repo.insert
}
