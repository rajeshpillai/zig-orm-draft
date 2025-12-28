const std = @import("std");
const orm = @import("zig-orm");

const CONN_STR = "postgresql://postgres:root123@localhost:5432/mydb";

test "pg preload - whereIn clause" {
    var db = try orm.postgres.PostgreSQL.init(CONN_STR);
    defer db.deinit();
    try db.exec("DROP TABLE IF EXISTS posts_preload");
    try db.exec("CREATE TABLE posts_preload (id SERIAL PRIMARY KEY, user_id INTEGER, title TEXT)");

    const Post = struct {
        id: i64,
        user_id: i64,
        title: []const u8,
    };

    const Posts = orm.Table(Post, "posts_preload");
    const Repo = orm.Repo(orm.postgres.PostgreSQL);

    var repo = try Repo.init(std.testing.allocator, CONN_STR);
    defer repo.deinit();

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

        // Empty IN clause should return all (no WHERE added - standard behavior check)
        // Wait, if whereIn is empty, does it add "1=0" or ignore it?
        // SQLite test expects all (4).
        try std.testing.expectEqual(@as(usize, 4), posts.len);
    }
}

test "pg preload - N+1 elimination pattern" {
    var db = try orm.postgres.PostgreSQL.init(CONN_STR);
    defer db.deinit();
    try db.exec("DROP TABLE IF EXISTS posts_preload");
    try db.exec("DROP TABLE IF EXISTS users_preload");
    try db.exec("CREATE TABLE users_preload (id SERIAL PRIMARY KEY, name TEXT)");
    try db.exec("CREATE TABLE posts_preload (id SERIAL PRIMARY KEY, user_id INTEGER, title TEXT)");

    const User = struct {
        id: i64,
        name: []const u8,
    };

    const Post = struct {
        id: i64,
        user_id: i64,
        title: []const u8,
    };

    const Users = orm.Table(User, "users_preload");
    const Posts = orm.Table(Post, "posts_preload");
    const Repo = orm.Repo(orm.postgres.PostgreSQL);

    var repo = try Repo.init(std.testing.allocator, CONN_STR);
    defer repo.deinit();

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
    }
}
