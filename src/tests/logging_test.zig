const std = @import("std");
const orm = @import("zig-orm");
const testing = std.testing;

const User = struct {
    id: i64,
    name: []const u8,
    active: bool,
    created_at: i64,
    updated_at: i64,
};

const Users = orm.Table(User, "users");

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
    // std.debug.print("LOGGED: {s} ({d}ns)\n", .{ctx.sql, ctx.duration_ns});
}

test "logging - captures sql and duration" {
    // Reset state
    if (last_sql) |s| std.heap.page_allocator.free(s);
    last_sql = null;
    last_duration_ns = 0;
    log_count = 0;

    var db = try orm.sqlite.SQLite.init(":memory:");
    defer db.deinit();

    try db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, active INTEGER, created_at INTEGER, updated_at INTEGER)");

    const Repo = orm.Repo(orm.sqlite.SQLite);
    var repo = try Repo.init(testing.allocator, ":memory:");
    // Note: We use the same adapter instance if possible, but Repo.init creates a new one.
    // For SQLite :memory: with distinct init calls, they are distinct DBs unless we share the handle.
    // But Repo takes connection string.
    // To share the DB for setup, we can't easily.
    // So let's use the repo to create table via raw execute if we can, or just rely on separate DBs?
    // Wait, separate :memory: DBs are separate.

    // Workaround: Use Repo's adapter to create table.
    try repo.adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, active INTEGER, created_at INTEGER, updated_at INTEGER)");

    defer repo.deinit();

    // Set logger
    repo.setLogger(testLogger);

    // Test Insert
    var changeset = try Users.insert(testing.allocator);
    defer changeset.deinit();
    try changeset.add(.{ .id = 1, .name = "Bob", .active = true });

    try repo.insert(changeset);

    try testing.expect(log_count == 1);
    try testing.expect(last_sql != null);
    try testing.expect(std.mem.startsWith(u8, last_sql.?, "INSERT INTO users"));
    try testing.expect(last_duration_ns > 0);

    // Test Select
    var q = try orm.from(Users, testing.allocator);
    defer q.deinit();
    _ = try q.where(.{ .name = "Bob" });

    const results = try repo.all(q);
    defer testing.allocator.free(results);

    try testing.expect(log_count == 2);
    try testing.expect(std.mem.startsWith(u8, last_sql.?, "SELECT"));
}
