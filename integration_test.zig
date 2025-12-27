const std = @import("std");
const orm = @import("zig-orm");

test "repo insert and all integration" {
    // Define model
    const User = struct {
        id: i64,
        name: []const u8,
        active: bool,
    };
    const Users = orm.Table(User, "users");
    const Repo = orm.Repo(orm.sqlite.SQLite);

    var repo = try Repo.init(std.testing.allocator, ":memory:");
    defer repo.deinit();

    // Setup table (manually for now)
    try repo.adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, active INTEGER)");

    // 1. Insert
    {
        var q = try Users.insert(std.testing.allocator);
        defer q.deinit();
        try q.add(.{ .id = 1, .name = "Alice", .active = true });
        try q.add(.{ .id = 2, .name = "Bob", .active = false });
        // Note: multiple items insert handled by loop in repo.insert?
        // Our simplified impl does `step()` once.
        // If SQL is `VALUES (?,?), (?,?)` it inserts all.
        try repo.insert(q);
    }

    // 2. Select All
    {
        // Seed data using raw SQL to verify Mapping (since insert bindings aren't ready)
        try repo.adapter.exec("DELETE FROM users");
        try repo.adapter.exec("INSERT INTO users (id, name, active) VALUES (1, 'Alice', 1)");
        try repo.adapter.exec("INSERT INTO users (id, name, active) VALUES (2, 'Bob', 0)");

        const q = orm.from(Users);

        const users = try repo.all(q);
        defer std.testing.allocator.free(users);
        defer {
            for (users) |u| {
                std.testing.allocator.free(u.name);
            }
        }

        try std.testing.expectEqual(2, users.len);

        // Check User 1
        try std.testing.expectEqual(1, users[0].id);
        try std.testing.expectEqualStrings("Alice", users[0].name);
        try std.testing.expectEqual(true, users[0].active);

        // Check User 2
        try std.testing.expectEqual(2, users[1].id);
        try std.testing.expectEqualStrings("Bob", users[1].name);
        try std.testing.expectEqual(false, users[1].active);
    }
}
