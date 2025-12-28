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

const CONN_STR = "postgresql://postgres:root123@localhost:5432/mydb";

test "pg joins - inner join" {
    var db = try orm.postgres.PostgreSQL.init(CONN_STR);
    defer db.deinit();
    try db.exec("DROP TABLE IF EXISTS posts_join");
    try db.exec("DROP TABLE IF EXISTS users_join");
    try db.exec("CREATE TABLE users_join (id SERIAL PRIMARY KEY, name TEXT)");
    try db.exec("CREATE TABLE posts_join (id SERIAL PRIMARY KEY, user_id INTEGER, title TEXT)");

    const Repo = orm.Repo(orm.postgres.PostgreSQL);
    var repo = try Repo.init(std.testing.allocator, CONN_STR);
    defer repo.deinit();

    const Users = orm.Table(User, "users_join");
    const Posts = orm.Table(Post, "posts_join");

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
    _ = try q.select("posts_join.title as post_title");
    _ = try q.select("users_join.name as user_name");
    _ = try q.innerJoin(Users, "posts_join.user_id = users_join.id");

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

test "pg joins - left join" {
    var db = try orm.postgres.PostgreSQL.init(CONN_STR);
    defer db.deinit();
    try db.exec("DROP TABLE IF EXISTS posts_join");
    try db.exec("DROP TABLE IF EXISTS users_join");
    try db.exec("CREATE TABLE users_join (id SERIAL PRIMARY KEY, name TEXT)");
    try db.exec("CREATE TABLE posts_join (id SERIAL PRIMARY KEY, user_id INTEGER, title TEXT)");

    const Repo = orm.Repo(orm.postgres.PostgreSQL);
    var repo = try Repo.init(std.testing.allocator, CONN_STR);
    defer repo.deinit();

    const Users = orm.Table(User, "users_join");
    const Posts = orm.Table(Post, "posts_join");

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
    _ = try q.select("users_join.name as user_name");
    _ = try q.select("COALESCE(posts_join.title, 'No Post') as post_title");
    _ = try q.leftJoin(Posts, "users_join.id = posts_join.user_id");

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
