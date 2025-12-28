const std = @import("std");
const orm = @import("zig-orm");
const testing = std.testing;

test "core - pool initialization and lifecycle" {
    // Local MockAdapter to avoid shared state race conditions
    const MockAdapter = struct {
        const Self = @This();
        pub var instance_count: usize = 0;
        // Need to implement full interface expected by Pool/PooledAdapter
        pub const Stmt = struct {
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
        pub fn init(conn_str: [:0]const u8) !Self {
            _ = conn_str;
            _ = @atomicRmw(usize, &instance_count, .Add, 1, .seq_cst);
            return Self{};
        }
        pub fn deinit(self: *Self) void {
            _ = self;
            _ = @atomicRmw(usize, &instance_count, .Sub, 1, .seq_cst);
        }
        pub fn exec(self: *Self, sql: [:0]const u8) !void {
            _ = self;
            _ = sql;
        }
        pub fn prepare(self: *Self, sql: [:0]const u8) !Stmt {
            _ = self;
            _ = sql;
            return Stmt{};
        }
        pub fn changes(self: *Self) usize {
            _ = self;
            return 0;
        }
        pub fn column_int(stmt: *Stmt, col: usize) i64 {
            _ = stmt;
            _ = col;
            return 0;
        }
        pub fn column_text(stmt: *Stmt, col: usize) ?[:0]const u8 {
            _ = stmt;
            _ = col;
            return null;
        }
    };

    const Pool = orm.Pool(MockAdapter);
    var pool = try Pool.init(testing.allocator, .{ .max_connections = 2 }, "dummy");
    defer pool.deinit();

    // Should have created 2 instances
    try testing.expectEqual(@as(usize, 2), MockAdapter.instance_count);

    // Acquire one
    var adapter1 = try pool.acquire();
    try testing.expectEqual(@as(usize, 2), pool.connections.items.len);
    try testing.expectEqual(@as(usize, 1), pool.free_indices.items.len);

    // Acquire another
    var adapter2 = try pool.acquire();
    try testing.expectEqual(@as(usize, 0), pool.free_indices.items.len);

    // Release
    adapter1.deinit();
    try testing.expectEqual(@as(usize, 1), pool.free_indices.items.len);

    adapter2.deinit();
    try testing.expectEqual(@as(usize, 2), pool.free_indices.items.len);
}

test "core - pool integration with repo" {
    const MockAdapter = struct {
        const Self = @This();
        pub const Stmt = struct {
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
        pub fn init(conn_str: [:0]const u8) !Self {
            _ = conn_str;
            return Self{};
        }
        pub fn deinit(self: *Self) void {
            _ = self;
        }
        pub fn exec(self: *Self, sql: [:0]const u8) !void {
            _ = self;
            _ = sql;
        }
        pub fn prepare(self: *Self, sql: [:0]const u8) !Stmt {
            _ = self;
            _ = sql;
            return Stmt{};
        }
        pub fn changes(self: *Self) usize {
            _ = self;
            return 0;
        }
        pub fn column_int(stmt: *Stmt, col: usize) i64 {
            _ = stmt;
            _ = col;
            return 0;
        }
        pub fn column_text(stmt: *Stmt, col: usize) ?[:0]const u8 {
            _ = stmt;
            _ = col;
            return null;
        }
    };

    const Pool = orm.Pool(MockAdapter);
    var pool = try Pool.init(testing.allocator, .{ .max_connections = 1 }, "dummy");
    defer pool.deinit();

    const PooledAdapter = orm.pool.PooledAdapter(MockAdapter);
    const Repo = orm.Repo(PooledAdapter);

    {
        // 1. Acquire pooled adapter
        const pooled = try pool.acquire();
        // 2. Init repo
        var repo = Repo.initFromAdapter(testing.allocator, pooled);
        // 3. Use repo (invokes adapter methods)
        try repo.begin();
        // 4. Deinit repo -> calls pooled.deinit() -> releases to pool
        repo.deinit();
    }

    try testing.expectEqual(@as(usize, 1), pool.free_indices.items.len);
}

// Threaded test
const ThreadMockAdapter = struct {
    const Self = @This();
    pub const Stmt = struct {
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
    pub fn init(conn_str: [:0]const u8) !Self {
        _ = conn_str;
        return Self{};
    }
    pub fn deinit(self: *Self) void {
        _ = self;
    }
    pub fn exec(self: *Self, sql: [:0]const u8) !void {
        _ = self;
        _ = sql;
    }
    pub fn prepare(self: *Self, sql: [:0]const u8) !Stmt {
        _ = self;
        _ = sql;
        return Stmt{};
    }
    pub fn changes(self: *Self) usize {
        _ = self;
        return 0;
    }
    pub fn column_int(stmt: *Stmt, col: usize) i64 {
        _ = stmt;
        _ = col;
        return 0;
    }
    pub fn column_text(stmt: *Stmt, col: usize) ?[:0]const u8 {
        _ = stmt;
        _ = col;
        return null;
    }
};

fn worker(pool: *orm.Pool(ThreadMockAdapter)) !void {
    var adapter = try pool.acquire();
    defer adapter.deinit();
    // Simulate work
    std.time.sleep(10 * std.time.ns_per_ms);
}

test "core - pool thread contention" {
    const Pool = orm.Pool(ThreadMockAdapter);
    var pool = try Pool.init(testing.allocator, .{ .max_connections = 2 }, "dummy");
    defer pool.deinit();

    var thread1 = try std.Thread.spawn(.{}, worker, .{pool});
    var thread2 = try std.Thread.spawn(.{}, worker, .{pool});
    var thread3 = try std.Thread.spawn(.{}, worker, .{pool});

    thread1.join();
    thread2.join();
    thread3.join();

    // All should have finished, pool should be full
    try testing.expectEqual(@as(usize, 2), pool.free_indices.items.len);
}
