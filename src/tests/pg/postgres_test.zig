const std = @import("std");
const orm = @import("zig-orm");

test "PostgreSQL connection" {
    const Repo = orm.Repo(orm.postgres.PostgreSQL);

    // Connection string: postgresql://user:password@host:port/database
    var repo = Repo.init(
        std.testing.allocator,
        "postgresql://postgres:root123@localhost:5432/postgres",
    ) catch |err| {
        std.debug.print("Failed to connect to PostgreSQL: {}\n", .{err});
        std.debug.print("Make sure PostgreSQL is running on localhost:5432\n", .{});
        std.debug.print("Username: postgres, Password: root123\n", .{});
        return error.SkipZigTest;
    };
    defer repo.deinit();

    // Test basic exec
    try repo.adapter.exec("SELECT 1");
}

test "PostgreSQL CRUD operations" {
    const User = struct {
        id: i64,
        name: []const u8,
        active: bool,
    };

    const Users = orm.Table(User, "users");
    const Repo = orm.Repo(orm.postgres.PostgreSQL);

    var repo = Repo.init(
        std.testing.allocator,
        "postgresql://postgres:root123@localhost:5432/postgres",
    ) catch |err| {
        std.debug.print("Skipping PostgreSQL tests: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer repo.deinit();

    // Suppress NOTICE messages (like "table does not exist, skipping")
    repo.adapter.exec("SET client_min_messages = WARNING") catch {};

    // Drop table if exists
    repo.adapter.exec("DROP TABLE IF EXISTS users") catch {};

    // Create table
    try repo.adapter.exec(
        \\CREATE TABLE users (
        \\    id BIGINT PRIMARY KEY,
        \\    name TEXT NOT NULL,
        \\    active BOOLEAN NOT NULL
        \\)
    );

    // Insert
    {
        var q = try Users.insert(std.testing.allocator);
        defer q.deinit();
        try q.add(.{ .id = 1, .name = "Alice", .active = true });
        try q.add(.{ .id = 2, .name = "Bob", .active = false });
        try repo.insert(q);
    }

    // Select all
    {
        var q = try orm.from(Users, std.testing.allocator);
        defer q.deinit();

        const users = try repo.all(q);
        defer std.testing.allocator.free(users);
        defer {
            for (users) |u| std.testing.allocator.free(u.name);
        }

        try std.testing.expectEqual(@as(usize, 2), users.len);
    }

    // Select with where
    {
        var q = try orm.from(Users, std.testing.allocator);
        defer q.deinit();
        _ = try q.where(.{ .active = true });

        const users = try repo.all(q);
        defer std.testing.allocator.free(users);
        defer {
            for (users) |u| std.testing.allocator.free(u.name);
        }

        try std.testing.expectEqual(@as(usize, 1), users.len);
        try std.testing.expectEqualStrings("Alice", users[0].name);
    }

    // Update
    {
        var u = try Users.update(std.testing.allocator);
        defer u.deinit();
        _ = try u.set(.{ .active = true });
        _ = try u.where(.{ .name = "Bob" });
        try repo.update(u);
    }

    // Verify update
    {
        var q = try orm.from(Users, std.testing.allocator);
        defer q.deinit();
        _ = try q.where(.{ .active = true });

        const users = try repo.all(q);
        defer std.testing.allocator.free(users);
        defer {
            for (users) |u| std.testing.allocator.free(u.name);
        }

        try std.testing.expectEqual(@as(usize, 2), users.len);
    }

    // Delete
    {
        var d = try Users.delete(std.testing.allocator);
        defer d.deinit();
        _ = try d.where(.{ .name = "Bob" });
        try repo.delete(d);
    }

    // Verify delete
    {
        var q = try orm.from(Users, std.testing.allocator);
        defer q.deinit();

        const users = try repo.all(q);
        defer std.testing.allocator.free(users);
        defer {
            for (users) |u| std.testing.allocator.free(u.name);
        }

        try std.testing.expectEqual(@as(usize, 1), users.len);
        try std.testing.expectEqualStrings("Alice", users[0].name);
    }

    // Cleanup
    try repo.adapter.exec("DROP TABLE users");
}
