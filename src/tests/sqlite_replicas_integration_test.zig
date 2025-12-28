const std = @import("std");
const testing = std.testing;
const orm = @import("zig-orm");
const Pool = orm.Pool;
const SQLite = orm.sqlite.SQLite;

test "sqlite read replicas - integration test" {
    // Create temporary database files for primary and replicas
    const primary_path = "test_primary.db";
    const replica1_path = "test_replica1.db";
    const replica2_path = "test_replica2.db";

    // Cleanup function
    defer {
        std.fs.cwd().deleteFile(primary_path) catch {};
        std.fs.cwd().deleteFile(replica1_path) catch {};
        std.fs.cwd().deleteFile(replica2_path) catch {};
    }

    // Setup: Create primary database with test table and data
    {
        var db = try SQLite.init(primary_path);
        defer db.deinit();

        try db.exec("CREATE TABLE test_users (id INTEGER PRIMARY KEY, name TEXT, type TEXT)");
        try db.exec("INSERT INTO test_users (name, type) VALUES ('Alice', 'primary')");
    }

    // Setup: Copy primary to replicas (simulating replication)
    {
        const primary_data = try std.fs.cwd().readFileAlloc(testing.allocator, primary_path, 1024 * 1024);
        defer testing.allocator.free(primary_data);

        try std.fs.cwd().writeFile(.{ .sub_path = replica1_path, .data = primary_data });
        try std.fs.cwd().writeFile(.{ .sub_path = replica2_path, .data = primary_data });
    }

    // Test: Create pool with replicas
    const replica_strs = [_][:0]const u8{ replica1_path, replica2_path };
    var pool = try Pool(SQLite).init(testing.allocator, .{
        .max_connections = 1,
        .replica_conn_strs = &replica_strs,
    }, primary_path);
    defer pool.deinit();

    // Test: Read from replica
    {
        var conn = try pool.acquireForRead();
        defer conn.deinit();

        // Verify we can read data
        var stmt = try conn.prepare("SELECT name, type FROM test_users WHERE id = ?");
        defer stmt.deinit();

        try stmt.bind_int(0, 1);
        const has_row = try stmt.step();
        try testing.expect(has_row);

        const name = SQLite.column_text(&stmt, 0);
        try testing.expectEqualStrings("Alice", name.?);
    }

    // Test: Write to primary
    {
        var conn = try pool.acquireForWrite();
        defer conn.deinit();

        try conn.exec("INSERT INTO test_users (name, type) VALUES ('Bob', 'primary')");

        // Verify write succeeded
        var stmt = try conn.prepare("SELECT COUNT(*) FROM test_users");
        defer stmt.deinit();

        _ = try stmt.step();
        const count = SQLite.column_int(&stmt, 0);
        try testing.expectEqual(@as(i64, 2), count);
    }

    // Test: Verify replicas still have old data (not auto-synced)
    {
        var conn = try pool.acquireForRead();
        defer conn.deinit();

        var stmt = try conn.prepare("SELECT COUNT(*) FROM test_users");
        defer stmt.deinit();

        _ = try stmt.step();
        const count = SQLite.column_int(&stmt, 0);
        // Replica should still have only 1 row (not synced)
        try testing.expectEqual(@as(i64, 1), count);
    }
}

test "sqlite read replicas - fallback to primary when no replicas" {
    const primary_path = "test_primary_fallback.db";

    defer {
        std.fs.cwd().deleteFile(primary_path) catch {};
    }

    // Setup database
    {
        var db = try SQLite.init(primary_path);
        defer db.deinit();
        try db.exec("CREATE TABLE test (id INTEGER PRIMARY KEY)");
    }

    // Create pool without replicas
    var pool = try Pool(SQLite).init(testing.allocator, .{
        .max_connections = 1,
    }, primary_path);
    defer pool.deinit();

    // acquireForRead should fall back to primary
    {
        var conn = try pool.acquireForRead();
        defer conn.deinit();

        try testing.expect(!conn.is_replica);

        // Verify we can query
        var stmt = try conn.prepare("SELECT COUNT(*) FROM test");
        defer stmt.deinit();
        _ = try stmt.step();
    }
}
