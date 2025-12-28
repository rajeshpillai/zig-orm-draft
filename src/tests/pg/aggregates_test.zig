const std = @import("std");
const orm = @import("zig-orm");

const User = struct {
    id: i64,
    name: []const u8,
    age: i32,
    active: bool,
};

const CONN_STR = "postgresql://postgres:root123@localhost:5432/mydb";

test "pg aggregates - count" {
    var db = try orm.postgres.PostgreSQL.init(CONN_STR);
    defer db.deinit();
    try db.exec("DROP TABLE IF EXISTS users_agg");
    try db.exec("CREATE TABLE users_agg (id SERIAL PRIMARY KEY, name TEXT, age INTEGER, active BOOLEAN)");

    const Repo = orm.Repo(orm.postgres.PostgreSQL);
    var repo = try Repo.init(std.testing.allocator, CONN_STR);
    defer repo.deinit();

    const Users = orm.Table(User, "users_agg");

    // Insert test data
    var changeset = try Users.insert(std.testing.allocator);
    defer changeset.deinit();
    try changeset.add(.{ .id = 1, .name = "Alice", .age = 30, .active = true });
    try changeset.add(.{ .id = 2, .name = "Bob", .age = 25, .active = true });
    try changeset.add(.{ .id = 3, .name = "Charlie", .age = 35, .active = false });
    try repo.insert(changeset);

    // 1. Basic count
    var q1 = try orm.from(Users, std.testing.allocator);
    defer q1.deinit();
    const total = try repo.count(&q1);
    try std.testing.expectEqual(@as(u64, 3), total);

    // 2. Count with where
    var q2 = try orm.from(Users, std.testing.allocator);
    defer q2.deinit();
    _ = try q2.where(.{ .active = true });
    const active_count = try repo.count(&q2);
    try std.testing.expectEqual(@as(u64, 2), active_count);
}

test "pg aggregates - scalar (sum)" {
    var db = try orm.postgres.PostgreSQL.init(CONN_STR);
    defer db.deinit();
    try db.exec("DROP TABLE IF EXISTS users_agg");
    try db.exec("CREATE TABLE users_agg (id SERIAL PRIMARY KEY, name TEXT, age INTEGER, active BOOLEAN)");

    const Repo = orm.Repo(orm.postgres.PostgreSQL);
    var repo = try Repo.init(std.testing.allocator, CONN_STR);
    defer repo.deinit();

    const Users = orm.Table(User, "users_agg");

    var changeset = try Users.insert(std.testing.allocator);
    defer changeset.deinit();
    try changeset.add(.{ .id = 1, .name = "Alice", .age = 30, .active = true });
    try changeset.add(.{ .id = 2, .name = "Bob", .age = 25, .active = true });
    try repo.insert(changeset);

    var q = try orm.from(Users, std.testing.allocator);
    defer q.deinit();
    _ = try q.select("SUM(age)");
    const total_age = try repo.scalar(i64, &q);
    try std.testing.expectEqual(@as(i64, 55), total_age);
}

test "pg aggregates - group by" {
    var db = try orm.postgres.PostgreSQL.init(CONN_STR);
    defer db.deinit();
    try db.exec("DROP TABLE IF EXISTS users_agg");
    try db.exec("CREATE TABLE users_agg (id SERIAL PRIMARY KEY, name TEXT, age INTEGER, active BOOLEAN)");

    const Repo = orm.Repo(orm.postgres.PostgreSQL);
    var repo = try Repo.init(std.testing.allocator, CONN_STR);
    defer repo.deinit();

    const Users = orm.Table(User, "users_agg");

    var changeset = try Users.insert(std.testing.allocator);
    defer changeset.deinit();
    try changeset.add(.{ .id = 1, .name = "Alice", .age = 30, .active = true });
    try changeset.add(.{ .id = 2, .name = "Bob", .age = 25, .active = true });
    try changeset.add(.{ .id = 3, .name = "Charlie", .age = 35, .active = false });
    try repo.insert(changeset);

    var q = try orm.from(Users, std.testing.allocator);
    defer q.deinit();
    _ = try q.select("active");
    _ = try q.count("*");
    _ = try q.groupBy("active");

    const Result = struct { active: bool, count: i64 };
    const sql = try q.toSql(std.testing.allocator);
    defer std.testing.allocator.free(sql);

    const results = try repo.query(Result, sql, &.{});
    defer std.testing.allocator.free(results);

    try std.testing.expectEqual(@as(usize, 2), results.len);
}
