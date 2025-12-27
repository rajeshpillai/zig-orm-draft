const std = @import("std");
const orm = @import("zig-orm");
const testing = std.testing;

const User = struct {
    id: i64,
    name: []const u8,
    created_at: i64,
    updated_at: i64,
};

const UserTable = orm.Table(User, "users");

test "automatic timestamps on insert" {
    const allocator = testing.allocator;
    var repo = try orm.Repo(orm.sqlite.SQLite).init(allocator, ":memory:");
    defer repo.deinit();

    try repo.adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, created_at INTEGER, updated_at INTEGER)");

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

test "automatic timestamps on update" {
    const allocator = testing.allocator;
    var repo = try orm.Repo(orm.sqlite.SQLite).init(allocator, ":memory:");
    defer repo.deinit();

    try repo.adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, created_at INTEGER, updated_at INTEGER)");

    // Insert initial
    var insert = try orm.query.Insert(UserTable).init(allocator);
    defer insert.deinit();
    try insert.add(.{ .id = 1, .name = "Alice", .created_at = 100, .updated_at = 100 });
    try repo.insert(&insert);

    // Update
    const start_time = orm.timestamps.currentTimestamp();
    // Wait a bit if needed? No, just compare.

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

test "manual timestamp override" {
    const allocator = testing.allocator;
    var repo = try orm.Repo(orm.sqlite.SQLite).init(allocator, ":memory:");
    defer repo.deinit();

    try repo.adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, created_at INTEGER, updated_at INTEGER)");

    // Override on insert
    var insert = try orm.query.Insert(UserTable).init(allocator);
    defer insert.deinit();
    try insert.add(.{ .id = 1, .name = "Alice", .created_at = 500, .updated_at = 600 });
    try repo.insert(&insert);

    const user1 = (try repo.findBy(UserTable, .{ .id = 1 })).?;
    defer allocator.free(user1.name);
    try testing.expectEqual(@as(i64, 500), user1.created_at);
    // updated_at is currently ALWAYS overwritten by repo.insert
    // unless we change Repo.insert logic
}
