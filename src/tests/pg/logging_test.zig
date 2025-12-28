const std = @import("std");
const orm = @import("zig-orm");
const testing = std.testing;

const CONN_STR = "postgresql://postgres:root123@localhost:5432/mydb";

const User = struct {
    id: i64,
    name: []const u8,
    active: bool,
    created_at: i64,
    updated_at: i64,
};

const Users = orm.Table(User, "users_log");

// Global log capture
var last_sql: ?[]const u8 = null;
var last_duration_ns: u64 = 0;
var log_count: usize = 0;

fn testLogger(ctx: orm.logging.LogContext) void {
    if (last_sql) |s| {
        std.heap.page_allocator.free(s);
    }
    last_sql = std.heap.page_allocator.dupe(u8, ctx.sql) catch unreachable;
    last_duration_ns = ctx.duration_ns;
    log_count += 1;
}

test "pg logging - captures sql and duration" {
    // Reset state
    if (last_sql) |s| std.heap.page_allocator.free(s);
    last_sql = null;
    last_duration_ns = 0;
    log_count = 0;

    const Repo = orm.Repo(orm.postgres.PostgreSQL);
    var repo = try Repo.init(testing.allocator, CONN_STR);
    defer repo.deinit();

    try repo.adapter.exec("DROP TABLE IF EXISTS users_log");
    try repo.adapter.exec("CREATE TABLE users_log (id SERIAL PRIMARY KEY, name TEXT, active BOOLEAN, created_at BIGINT, updated_at BIGINT)");

    // Set logger
    repo.setLogger(testLogger);

    // Test Insert
    var changeset = try Users.insert(testing.allocator);
    defer changeset.deinit();
    try changeset.add(.{ .id = 1, .name = "Bob", .active = true, .created_at = 0, .updated_at = 0 });

    try repo.insert(changeset);

    try testing.expect(log_count == 1);
    try testing.expect(last_sql != null);
    try testing.expect(std.mem.startsWith(u8, last_sql.?, "INSERT INTO users_log"));
    try testing.expect(last_duration_ns > 0);

    // Test Select
    var q = try orm.from(Users, testing.allocator);
    defer q.deinit();
    _ = try q.where(.{ .name = "Bob" });

    const results = try repo.all(q);
    defer {
        for (results) |user| {
            testing.allocator.free(user.name);
        }
        testing.allocator.free(results);
    }

    try testing.expect(log_count == 2);
    try testing.expect(std.mem.startsWith(u8, last_sql.?, "SELECT"));
}
