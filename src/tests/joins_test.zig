const std = @import("std");
const orm = @import("zig-orm");

const User = struct {
    id: i64,
    name: []const u8,
};

const Post = struct {
    id: i64,
    user_id: i64,
    title: []const u8,
};

const PostWithUser = struct {
    post_title: []const u8,
    user_name: []const u8,
};

test "joins - inner join" {
    const Repo = orm.Repo(orm.sqlite.SQLite);
    var repo = try Repo.init(std.testing.allocator, ":memory:");
    defer repo.deinit();

    try repo.adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)");
    try repo.adapter.exec("CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER, title TEXT)");

    const Users = orm.Table(User, "users");
    const Posts = orm.Table(Post, "posts");

    // Seed data
    var user_cs = try Users.insert(std.testing.allocator);
    defer user_cs.deinit();
    try user_cs.add(.{ .id = 1, .name = "Alice" });
    try repo.insert(user_cs);

    var post_cs = try Posts.insert(std.testing.allocator);
    defer post_cs.deinit();
    try post_cs.add(.{ .id = 1, .user_id = 1, .title = "Hello World" });
    try repo.insert(post_cs);

    var q = try orm.from(Posts, std.testing.allocator);
    defer q.deinit();
    _ = try q.select("posts.title as post_title");
    _ = try q.select("users.name as user_name");
    _ = try q.innerJoin(Users, "posts.user_id = users.id");

    const results = try repo.allAs(PostWithUser, &q);
    defer {
        for (results) |r| {
            repo.allocator.free(r.post_title);
            repo.allocator.free(r.user_name);
        }
        std.testing.allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("Hello World", results[0].post_title);
    try std.testing.expectEqualStrings("Alice", results[0].user_name);
}

test "joins - left join" {
    const Repo = orm.Repo(orm.sqlite.SQLite);
    var repo = try Repo.init(std.testing.allocator, ":memory:");
    defer repo.deinit();

    try repo.adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)");
    try repo.adapter.exec("CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER, title TEXT)");

    const Users = orm.Table(User, "users");
    const Posts = orm.Table(Post, "posts");

    // Seed data
    var user_cs = try Users.insert(std.testing.allocator);
    defer user_cs.deinit();
    try user_cs.add(.{ .id = 1, .name = "Alice" });
    try user_cs.add(.{ .id = 2, .name = "Bob" }); // Bob has no posts
    try repo.insert(user_cs);

    var post_cs = try Posts.insert(std.testing.allocator);
    defer post_cs.deinit();
    try post_cs.add(.{ .id = 1, .user_id = 1, .title = "Hello World" });
    try repo.insert(post_cs);

    // Join Users -> Posts (Left Join)
    var q = try orm.from(Users, std.testing.allocator);
    defer q.deinit();
    _ = try q.select("users.name as user_name");
    _ = try q.select("COALESCE(posts.title, 'No Post') as post_title");
    _ = try q.leftJoin(Posts, "users.id = posts.user_id");

    const results = try repo.allAs(PostWithUser, &q);
    defer {
        for (results) |r| {
            repo.allocator.free(r.post_title);
            repo.allocator.free(r.user_name);
        }
        std.testing.allocator.free(results);
    }

    try std.testing.expectEqual(@as(usize, 2), results.len);
}
