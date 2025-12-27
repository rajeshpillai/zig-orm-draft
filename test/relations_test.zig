const std = @import("std");
const orm = @import("zig-orm");

test "one-to-one relationships" {
    // Define models with foreign key
    const User = struct {
        id: i64,
        name: []const u8,
    };

    const Profile = struct {
        id: i64,
        user_id: i64, // Foreign key to users.id
        bio: []const u8,
    };

    const Users = orm.Table(User, "users");
    const Profiles = orm.Table(Profile, "profiles");
    const Repo = orm.Repo(orm.sqlite.SQLite);

    var repo = try Repo.init(std.testing.allocator, ":memory:");
    defer repo.deinit();

    // Setup tables
    try repo.adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)");
    try repo.adapter.exec("CREATE TABLE profiles (id INTEGER PRIMARY KEY, user_id INTEGER, bio TEXT)");

    // Insert user
    {
        var q = try Users.insert(std.testing.allocator);
        defer q.deinit();
        try q.add(.{ .id = 1, .name = "Alice" });
        try repo.insert(q);
    }

    // Insert profile with foreign key
    {
        var q = try Profiles.insert(std.testing.allocator);
        defer q.deinit();
        try q.add(.{ .id = 1, .user_id = 1, .bio = "Software Engineer" });
        try repo.insert(q);
    }

    // Test findBy helper - load profile for user
    {
        const profile = try repo.findBy(Profiles, .{ .user_id = 1 });
        try std.testing.expect(profile != null);

        if (profile) |p| {
            defer std.testing.allocator.free(p.bio);
            try std.testing.expectEqual(@as(i64, 1), p.id);
            try std.testing.expectEqual(@as(i64, 1), p.user_id);
            try std.testing.expectEqualStrings("Software Engineer", p.bio);
        }
    }

    // Test findBy returns null when not found
    {
        const profile = try repo.findBy(Profiles, .{ .user_id = 999 });
        try std.testing.expect(profile == null);
    }

    // Test manual loading with where clause
    {
        var q = try orm.from(Profiles, std.testing.allocator);
        defer q.deinit();
        _ = try q.where(.{ .user_id = 1 });

        const profiles = try repo.all(q);
        defer std.testing.allocator.free(profiles);
        defer {
            for (profiles) |p| std.testing.allocator.free(p.bio);
        }

        try std.testing.expectEqual(@as(usize, 1), profiles.len);
        try std.testing.expectEqualStrings("Software Engineer", profiles[0].bio);
    }
}

test "one-to-many relationships" {
    // Define models
    const User = struct {
        id: i64,
        name: []const u8,
    };

    const Post = struct {
        id: i64,
        user_id: i64, // Foreign key
        title: []const u8,
        content: []const u8,
    };

    const Users = orm.Table(User, "users");
    const Posts = orm.Table(Post, "posts");
    const Repo = orm.Repo(orm.sqlite.SQLite);

    var repo = try Repo.init(std.testing.allocator, ":memory:");
    defer repo.deinit();

    // Setup tables
    try repo.adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)");
    try repo.adapter.exec("CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER, title TEXT, content TEXT)");

    // Insert user
    {
        var q = try Users.insert(std.testing.allocator);
        defer q.deinit();
        try q.add(.{ .id = 1, .name = "Alice" });
        try repo.insert(q);
    }

    // Insert multiple posts for user
    {
        var q = try Posts.insert(std.testing.allocator);
        defer q.deinit();
        try q.add(.{ .id = 1, .user_id = 1, .title = "First Post", .content = "Hello World" });
        try q.add(.{ .id = 2, .user_id = 1, .title = "Second Post", .content = "Zig is great" });
        try q.add(.{ .id = 3, .user_id = 1, .title = "Third Post", .content = "ORM patterns" });
        try repo.insert(q);
    }

    // Test findAllBy - load all posts for user
    {
        const posts = try repo.findAllBy(Posts, .{ .user_id = 1 });
        defer std.testing.allocator.free(posts);
        defer {
            for (posts) |p| {
                std.testing.allocator.free(p.title);
                std.testing.allocator.free(p.content);
            }
        }

        try std.testing.expectEqual(@as(usize, 3), posts.len);
        try std.testing.expectEqualStrings("First Post", posts[0].title);
        try std.testing.expectEqualStrings("Second Post", posts[1].title);
        try std.testing.expectEqualStrings("Third Post", posts[2].title);
    }

    // Test empty collection
    {
        const posts = try repo.findAllBy(Posts, .{ .user_id = 999 });
        defer std.testing.allocator.free(posts);

        try std.testing.expectEqual(@as(usize, 0), posts.len);
    }
}
