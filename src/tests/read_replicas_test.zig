const std = @import("std");
const testing = std.testing;
const orm = @import("zig-orm");
const Pool = orm.Pool;

// Mock adapter for testing
const MockAdapter = struct {
    id: usize, // To track which connection this is
    is_replica: bool,

    pub const Stmt = struct {
        mock_data: i64 = 42,

        pub fn deinit(self: *Stmt) void {
            _ = self;
        }

        pub fn step(self: *Stmt) !bool {
            _ = self;
            return false;
        }

        pub fn reset(self: *Stmt) !void {
            _ = self;
        }

        pub fn bind_int(self: *Stmt, idx: usize, val: i64) !void {
            _ = self;
            _ = idx;
            _ = val;
        }

        pub fn bind_text(self: *Stmt, idx: usize, val: []const u8) !void {
            _ = self;
            _ = idx;
            _ = val;
        }
    };

    pub fn init(conn_str: [:0]const u8) !MockAdapter {
        // Parse connection string to determine if replica
        const is_replica = std.mem.indexOf(u8, conn_str, "replica") != null;

        // Extract ID from connection string (format: "primary:0" or "replica:1")
        const colon_idx = std.mem.indexOf(u8, conn_str, ":") orelse return error.InvalidConnStr;
        const id_str = conn_str[colon_idx + 1 ..];
        const id = std.fmt.parseInt(usize, id_str, 10) catch return error.InvalidConnStr;

        return MockAdapter{
            .id = id,
            .is_replica = is_replica,
        };
    }

    pub fn deinit(self: *MockAdapter) void {
        _ = self;
    }

    pub fn exec(self: *MockAdapter, sql: [:0]const u8) !void {
        _ = self;
        _ = sql;
    }

    pub fn prepare(self: *MockAdapter, sql: [:0]const u8) !Stmt {
        _ = self;
        _ = sql;
        return Stmt{};
    }

    pub fn changes(self: *MockAdapter) usize {
        _ = self;
        return 0;
    }

    pub fn column_int(stmt: *Stmt, idx: usize) i64 {
        _ = idx;
        return stmt.mock_data;
    }

    pub fn column_text(stmt: *Stmt, idx: usize) ?[:0]const u8 {
        _ = stmt;
        _ = idx;
        return null;
    }
};

test "pool - read replicas basic routing" {
    const replica_strs = [_][:0]const u8{ "replica:0", "replica:1" };

    var pool = try Pool(MockAdapter).init(testing.allocator, .{
        .max_connections = 2,
        .replica_conn_strs = &replica_strs,
    }, "primary:0");
    defer pool.deinit();

    // Acquire for write - should get primary
    {
        var conn = try pool.acquireForWrite();
        defer conn.deinit();
        try testing.expect(!conn.is_replica);
        try testing.expectEqual(@as(usize, 0), conn.adapter.id);
    }

    // Acquire for read - should get replica
    {
        var conn = try pool.acquireForRead();
        defer conn.deinit();
        try testing.expect(conn.is_replica);
        // Should be one of the replicas (0 or 1)
        try testing.expect(conn.adapter.id == 0 or conn.adapter.id == 1);
    }
}

test "pool - read falls back to primary when no replicas" {
    // Pool with no replicas
    var pool = try Pool(MockAdapter).init(testing.allocator, .{
        .max_connections = 1,
    }, "primary:0");
    defer pool.deinit();

    // Acquire for read - should fall back to primary
    {
        var conn = try pool.acquireForRead();
        defer conn.deinit();
        try testing.expect(!conn.is_replica);
        try testing.expectEqual(@as(usize, 0), conn.adapter.id);
    }
}

test "pool - backward compatible acquire uses primary" {
    const replica_strs = [_][:0]const u8{"replica:0"};

    var pool = try Pool(MockAdapter).init(testing.allocator, .{
        .max_connections = 1,
        .replica_conn_strs = &replica_strs,
    }, "primary:0");
    defer pool.deinit();

    // Old-style acquire should still use primary
    {
        var conn = try pool.acquire();
        defer conn.deinit();
        try testing.expect(!conn.is_replica);
    }
}

test "pool - multiple read replicas distribution" {
    const replica_strs = [_][:0]const u8{ "replica:0", "replica:1", "replica:2" };

    var pool = try Pool(MockAdapter).init(testing.allocator, .{
        .max_connections = 1,
        .replica_conn_strs = &replica_strs,
    }, "primary:0");
    defer pool.deinit();

    // Acquire all replicas
    var conn1 = try pool.acquireForRead();
    var conn2 = try pool.acquireForRead();
    var conn3 = try pool.acquireForRead();

    try testing.expect(conn1.is_replica);
    try testing.expect(conn2.is_replica);
    try testing.expect(conn3.is_replica);

    // All should be different replicas
    try testing.expect(conn1.adapter.id != conn2.adapter.id);
    try testing.expect(conn2.adapter.id != conn3.adapter.id);
    try testing.expect(conn1.adapter.id != conn3.adapter.id);

    conn1.deinit();
    conn2.deinit();
    conn3.deinit();
}
