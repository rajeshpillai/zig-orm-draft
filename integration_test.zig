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
        // Data seeded in block 1 via repo.insert should persist if we didn't clear it.
        // Wait, default SQLite :memory: is shared?
        // No, ":memory:" is private per connection.
        // But `repo` is the same instance? Yes, declared at line 14.
        // So inserts from block 1 are still there.
        // Just query them.

        var q = try orm.from(Users, std.testing.allocator);
        defer q.deinit();

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

    // 3. Select Where
    {
        var q = try orm.from(Users, std.testing.allocator);
        defer q.deinit();

        _ = try q.where(.{ .name = "Alice" });

        const users = try repo.all(q);
        defer std.testing.allocator.free(users);
        defer {
            for (users) |u| {
                std.testing.allocator.free(u.name);
            }
        }
        try std.testing.expectEqual(1, users.len);
        try std.testing.expectEqualStrings("Alice", users[0].name);
    }

    // 4. Limit & Offset
    {
        // Test Limit
        var q = try orm.from(Users, std.testing.allocator);
        defer q.deinit();

        _ = q.limit(1);

        const results = try repo.all(q);
        defer std.testing.allocator.free(results);
        defer {
            for (results) |u| {
                std.testing.allocator.free(u.name);
            }
        }

        try std.testing.expectEqual(@as(usize, 1), results.len);
        try std.testing.expectEqualStrings("Alice", results[0].name);
    }

    {
        // Test Offset
        var q = try orm.from(Users, std.testing.allocator);
        defer q.deinit();

        // Offset 1, Limit 1 -> Should be Bob
        _ = q.limit(1).offset(1);

        const results = try repo.all(q);
        defer std.testing.allocator.free(results);
        defer {
            for (results) |u| {
                std.testing.allocator.free(u.name);
            }
        }

        try std.testing.expectEqual(@as(usize, 1), results.len);
        try std.testing.expectEqualStrings("Bob", results[0].name);
    }

    // 5. Transactions - Rollback
    {
        try repo.begin();
        errdefer repo.rollback() catch {};

        var q = try Users.insert(std.testing.allocator);
        defer q.deinit();
        try q.add(.{ .id = 3, .name = "Charlie", .active = true });
        try repo.insert(q);

        try repo.rollback();

        // Verify Charlie is NOT there
        var q_check = try orm.from(Users, std.testing.allocator);
        defer q_check.deinit();
        _ = try q_check.where(.{ .name = "Charlie" });

        const results = try repo.all(q_check);
        defer std.testing.allocator.free(results);
        defer {
            for (results) |u| std.testing.allocator.free(u.name);
        }

        try std.testing.expectEqual(@as(usize, 0), results.len);
    }

    // 6. Transactions - Commit
    {
        try repo.begin();
        errdefer repo.rollback() catch {};

        var q = try Users.insert(std.testing.allocator);
        defer q.deinit();
        try q.add(.{ .id = 4, .name = "Dave", .active = true });
        try repo.insert(q);

        try repo.commit();

        // Verify Dave IS there
        var q_check = try orm.from(Users, std.testing.allocator);
        defer q_check.deinit();
        _ = try q_check.where(.{ .name = "Dave" });

        const results = try repo.all(q_check);
        defer std.testing.allocator.free(results);
        defer {
            for (results) |u| std.testing.allocator.free(u.name);
        }

        try std.testing.expectEqual(@as(usize, 1), results.len);
        try std.testing.expectEqualStrings("Dave", results[0].name);
    }
}
