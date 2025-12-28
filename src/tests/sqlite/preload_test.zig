const std = @import("std");
const orm = @import("zig-orm");

test "whereIn clause" {
    const Post = struct {
        id: i64,
        user_id: i64,
        title: []const u8,
    };

    const Posts = orm.Table(Post, "posts");
    const Repo = orm.Repo(orm.sqlite.SQLite);

    var repo = try Repo.init(std.testing.allocator, ":memory:");
    defer repo.deinit();

    try repo.adapter.exec("CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER, title TEXT)");

    // Insert posts for multiple users
    {
        var q = try Posts.insert(std.testing.allocator);
        defer q.deinit();
        try q.add(.{ .id = 1, .user_id = 1, .title = "User 1 Post 1" });
        try q.add(.{ .id = 2, .user_id = 1, .title = "User 1 Post 2" });
        try q.add(.{ .id = 3, .user_id = 2, .title = "User 2 Post 1" });
        try q.add(.{ .id = 4, .user_id = 3, .title = "User 3 Post 1" });
        try repo.insert(q);
    }

    // Test whereIn - get posts for users 1 and 2
    {
        var q = try orm.from(Posts, std.testing.allocator);
        defer q.deinit();

        const user_ids = [_]i64{ 1, 2 };
        _ = try q.whereIn("user_id", &user_ids);

        const posts = try repo.all(q);
        defer std.testing.allocator.free(posts);
        defer {
            for (posts) |p| std.testing.allocator.free(p.title);
        }

        try std.testing.expectEqual(@as(usize, 3), posts.len);
    }

    // Test empty whereIn
    {
        var q = try orm.from(Posts, std.testing.allocator);
        defer q.deinit();

        const user_ids = [_]i64{};
        _ = try q.whereIn("user_id", &user_ids);

        const posts = try repo.all(q);
        defer std.testing.allocator.free(posts);
        defer {
            for (posts) |p| std.testing.allocator.free(p.title);
        }

        // Empty IN clause should return all (no WHERE added)
        try std.testing.expectEqual(@as(usize, 4), posts.len);
    }
}

test "N+1 elimination pattern" {
    // This test demonstrates the pattern for eliminating N+1 queries
    // Users can follow this pattern in their own code

    const User = struct {
        id: i64,
        name: []const u8,
    };

    const Post = struct {
        id: i64,
        user_id: i64,
        title: []const u8,
    };

    const Users = orm.Table(User, "users");
    const Posts = orm.Table(Post, "posts");
    const Repo = orm.Repo(orm.sqlite.SQLite);

    var repo = try Repo.init(std.testing.allocator, ":memory:");
    defer repo.deinit();

    try repo.adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)");
    try repo.adapter.exec("CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER, title TEXT)");

    // Insert test data
    {
        var q = try Users.insert(std.testing.allocator);
        defer q.deinit();
        try q.add(.{ .id = 1, .name = "Alice" });
        try q.add(.{ .id = 2, .name = "Bob" });
        try repo.insert(q);
    }

    {
        var q = try Posts.insert(std.testing.allocator);
        defer q.deinit();
        try q.add(.{ .id = 1, .user_id = 1, .title = "Alice Post 1" });
        try q.add(.{ .id = 2, .user_id = 1, .title = "Alice Post 2" });
        try q.add(.{ .id = 3, .user_id = 2, .title = "Bob Post 1" });
        try repo.insert(q);
    }

    // GOOD PATTERN: 2 queries instead of N+1
    {
        // Query 1: Get all users
        var user_q = try orm.from(Users, std.testing.allocator);
        defer user_q.deinit();
        const users = try repo.all(user_q);
        defer std.testing.allocator.free(users);
        defer {
            for (users) |u| std.testing.allocator.free(u.name);
        }

        // Query 2: Get all posts for these users in ONE query using whereIn
        const user_ids = [_]i64{ 1, 2 };
        var post_q = try orm.from(Posts, std.testing.allocator);
        defer post_q.deinit();
        _ = try post_q.whereIn("user_id", &user_ids);

        const posts = try repo.all(post_q);
        defer std.testing.allocator.free(posts);
        defer {
            for (posts) |p| std.testing.allocator.free(p.title);
        }

        // Verify we got all posts in a single query
        try std.testing.expectEqual(@as(usize, 3), posts.len);

        // Users can manually associate posts with users as needed
        // This is explicit and type-safe
    }
}
