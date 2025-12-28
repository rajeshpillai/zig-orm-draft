const std = @import("std");
const orm = @import("zig-orm");
const testing = std.testing;
const Pool = orm.Pool;
const Repo = orm.Repo;
const sqlite = orm.sqlite;
const postgres = orm.postgres;

test "pool - sqlite integration" {
    // 1. Create Pool
    var pool = try Pool(sqlite.SQLite3).init(testing.allocator, .{ .max_connections = 2 }, ":memory:");
    defer pool.deinit();

    // 2. Acquire connection
    var conn = try pool.acquire();
    defer conn.deinit();

    // 3. Low-level check
    // Create a table
    try conn.exec("CREATE TABLE IF NOT EXISTS test_pool (id INTEGER PRIMARY KEY, name TEXT)");
    try conn.exec("INSERT INTO test_pool (name) VALUES ('test')");

    // Check changes
    try testing.expectEqual(@as(usize, 1), conn.changes());

    // Select
    var stmt = try conn.prepare("SELECT name FROM test_pool WHERE id = ?");
    defer stmt.deinit();
    try stmt.bind_int(1, 1);
    const has_row = try stmt.step();
    try testing.expect(has_row);

    const name = orm.pool.PooledAdapter(sqlite.SQLite3).column_text(&stmt, 0);
    try testing.expectEqualStrings("test", name.?);
}

test "pool - postgres integration" {
    // 1. Create Pool
    // Assumes PG is running locally as per existing tests
    var pool = try Pool(postgres.PostgreSQL).init(testing.allocator, .{ .max_connections = 2 }, "postgresql://postgres:root123@localhost:5432/mydb");
    defer pool.deinit();

    // 2. Acquire connection
    var conn = try pool.acquire();
    defer conn.deinit();

    // 3. Low-level check
    try conn.exec("DROP TABLE IF EXISTS test_pool_pg");
    try conn.exec("CREATE TABLE test_pool_pg (id SERIAL PRIMARY KEY, name TEXT)");
    try conn.exec("INSERT INTO test_pool_pg (name) VALUES ('test')");

    // 4. Repo Integration
    const PooledPG = orm.pool.PooledAdapter(postgres.PostgreSQL);
    // Be careful with ownership: we want to create a NEW repo using a NEW pooled connection,
    // or use the current one if we weren't deferring deinit above.
    // Let's grab a second connection for Repo.

    {
        var conn2 = try pool.acquire();
        // Repo takes ownership of conn2
        // But Repo.deinit() calls conn2.deinit(), which releases it to pool.
        const repo = Repo(PooledPG).initFromAdapter(testing.allocator, conn2);
        defer repo.deinit();

        const User = struct {
            id: i32,
            name: []const u8,
            pub const table_name = "test_pool_pg";
            pub const columns = &.{
                .{ .name = "id", .type = .Integer },
                .{ .name = "name", .type = .Text },
            };
            pub const model_type = @This();
        };

        const users = try repo.findAllBy(User, .{ .name = "test" });
        defer testing.allocator.free(users); // Array itself
        defer {
            for (users) |u| testing.allocator.free(u.name);
        }

        try testing.expectEqual(@as(usize, 1), users.len);
        try testing.expectEqualStrings("test", users[0].name);
    }
}
