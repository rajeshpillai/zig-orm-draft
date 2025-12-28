const std = @import("std");
const testing = std.testing;
const orm = @import("zig-orm");
const Pool = orm.Pool;
const PostgreSQL = orm.postgres.PostgreSQL;

// NOTE: This test requires a PostgreSQL instance with replication setup
// Primary: postgresql://postgres:root123@localhost:5432/test_primary
// Replica: postgresql://postgres:root123@localhost:5433/test_replica (or streaming replica)

test "postgresql read replicas - integration test" {
    // Skip if PostgreSQL not available
    var primary_db = PostgreSQL.init("host=localhost port=5432 dbname=test_primary user=postgres password=root123") catch {
        std.debug.print("Skipping PostgreSQL replica test - primary not available\n", .{});
        return error.SkipZigTest;
    };
    defer primary_db.deinit();

    // Setup: Create test table and data on primary
    primary_db.exec("DROP TABLE IF EXISTS test_users") catch {};
    try primary_db.exec("CREATE TABLE test_users (id SERIAL PRIMARY KEY, name TEXT, type TEXT)");
    try primary_db.exec("INSERT INTO test_users (name, type) VALUES ('Alice', 'primary')");

    // Test: Create pool with replica
    const replica_strs = [_][:0]const u8{
        "host=localhost port=5433 dbname=test_replica user=postgres password=root123",
    };

    var pool = Pool(PostgreSQL).init(testing.allocator, .{
        .max_connections = 1,
        .replica_conn_strs = &replica_strs,
    }, "host=localhost port=5432 dbname=test_primary user=postgres password=root123") catch {
        std.debug.print("Skipping PostgreSQL replica test - replica not available\n", .{});
        return error.SkipZigTest;
    };
    defer pool.deinit();

    // Test: Read from replica
    {
        var conn = try pool.acquireForRead();
        defer conn.deinit();

        // Verify we got a replica connection
        try testing.expect(conn.is_replica);

        // Verify we can read data (assuming replication has synced)
        var stmt = try conn.prepare("SELECT name, type FROM test_users WHERE id = $1");
        defer stmt.deinit();

        try stmt.bind_int(0, 1);
        const has_row = try stmt.step();

        if (has_row) {
            const name = PostgreSQL.column_text(&stmt, 0);
            try testing.expectEqualStrings("Alice", name.?);
        }
    }

    // Test: Write to primary
    {
        var conn = try pool.acquireForWrite();
        defer conn.deinit();

        // Verify we got a primary connection
        try testing.expect(!conn.is_replica);

        try conn.exec("INSERT INTO test_users (name, type) VALUES ('Bob', 'primary')");

        // Verify write succeeded
        var stmt = try conn.prepare("SELECT COUNT(*) FROM test_users");
        defer stmt.deinit();

        _ = try stmt.step();
        const count = PostgreSQL.column_int(&stmt, 0);
        try testing.expectEqual(@as(i64, 2), count);
    }

    // Cleanup
    try primary_db.exec("DROP TABLE test_users");
}

test "postgresql read replicas - fallback to primary when no replicas" {
    var pool = Pool(PostgreSQL).init(testing.allocator, .{
        .max_connections = 1,
    }, "host=localhost port=5432 dbname=test_primary user=postgres password=root123") catch {
        std.debug.print("Skipping PostgreSQL test - database not available\n", .{});
        return error.SkipZigTest;
    };
    defer pool.deinit();

    // acquireForRead should fall back to primary
    {
        var conn = try pool.acquireForRead();
        defer conn.deinit();

        try testing.expect(!conn.is_replica);
    }
}
