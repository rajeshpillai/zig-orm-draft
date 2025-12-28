const std = @import("std");
const orm = @import("zig-orm");
const query = orm.query;

const User = struct {
    id: i64,
    name: []const u8,
    age: i32,
    active: bool,
};
const Users = orm.Table(User, "users");

test "enhanced query builder - comparison operators" {
    const allocator = std.testing.allocator;
    var q = try orm.from(Users, allocator);
    defer q.deinit();

    // age > 18
    _ = try q.where(.{ .age, .gt, 18 });

    const sql = try q.toSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualSlices(u8, "SELECT id, name, age, active FROM users WHERE age > ?", sql);
    try std.testing.expectEqual(@as(usize, 1), q.params.items.len);
    try std.testing.expectEqual(@as(i64, 18), q.params.items[0].Integer);
}

test "enhanced query builder - logical OR" {
    const allocator = std.testing.allocator;
    var q = try orm.from(Users, allocator);
    defer q.deinit();

    // active = true OR age > 21
    _ = try q.where(.{ .{ .active = true }, .OR, .{ .age, .gt, 21 } });

    const sql = try q.toSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualSlices(u8, "SELECT id, name, age, active FROM users WHERE (active = ? OR age > ?)", sql);
    try std.testing.expectEqual(@as(usize, 2), q.params.items.len);
    try std.testing.expectEqual(true, q.params.items[0].Boolean);
    try std.testing.expectEqual(@as(i64, 21), q.params.items[1].Integer);
}

test "enhanced query builder - mixed logical and comparison" {
    const allocator = std.testing.allocator;
    var q = try orm.from(Users, allocator);
    defer q.deinit();

    // (active = true OR admin = true) AND age > 21
    // Note: currently nested AND is implicit if we call .where multiple times
    _ = try q.where(.{ .{ .active = true }, .OR, .{ .id, .lt, 100 } });
    _ = try q.where(.{ .age, .gt, 21 });

    const sql = try q.toSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualSlices(u8, "SELECT id, name, age, active FROM users WHERE (active = ? OR id < ?) AND age > ?", sql);
    try std.testing.expectEqual(@as(usize, 3), q.params.items.len);
}

test "enhanced query builder - LIKE and NULL" {
    const allocator = std.testing.allocator;
    var q = try orm.from(Users, allocator);
    defer q.deinit();

    _ = try q.where(.{ .name, .like, "Ali%" });
    _ = try q.where(.{ .active, .is_null, null }); // value is ignored for is_null

    const sql = try q.toSql(allocator);
    defer allocator.free(sql);

    try std.testing.expectEqualSlices(u8, "SELECT id, name, age, active FROM users WHERE name LIKE ? AND active IS NULL", sql);
    try std.testing.expectEqual(@as(usize, 1), q.params.items.len);
    try std.testing.expectEqualSlices(u8, "Ali%", q.params.items[0].Text);
}
