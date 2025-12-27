const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Mutex = std.Thread.Mutex;

pub fn ConnectionPool(comptime Adapter: type) type {
    return struct {
        const Self = @This();

        pub const Config = struct {
            max_connections: usize = 10,
            min_connections: usize = 2,
            connection_string: [:0]const u8,
        };

        allocator: Allocator,
        config: Config,
        connections: ArrayList(*Adapter),
        available: ArrayList(*Adapter),
        mutex: Mutex,

        pub fn init(allocator: Allocator, config: Config) !Self {
            var self = Self{
                .allocator = allocator,
                .config = config,
                .connections = .{},
                .available = .{},
                .mutex = .{},
            };

            // Create minimum connections
            var i: usize = 0;
            while (i < config.min_connections) : (i += 1) {
                const conn = try allocator.create(Adapter);
                errdefer allocator.destroy(conn);

                conn.* = try Adapter.init(config.connection_string);
                errdefer conn.deinit();

                try self.connections.append(allocator, conn);
                try self.available.append(allocator, conn);
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            for (self.connections.items) |conn| {
                conn.deinit();
                self.allocator.destroy(conn);
            }

            self.connections.deinit(self.allocator);
            self.available.deinit(self.allocator);
        }

        pub fn acquire(self: *Self) !*Adapter {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Try to get an available connection
            if (self.available.items.len > 0) {
                return self.available.pop() orelse return error.ConnectionPoolExhausted;
            }

            // Try to create a new connection if under max
            if (self.connections.items.len < self.config.max_connections) {
                const conn = try self.allocator.create(Adapter);
                errdefer self.allocator.destroy(conn);

                conn.* = try Adapter.init(self.config.connection_string);
                errdefer conn.deinit();

                try self.connections.append(self.allocator, conn);
                return conn;
            }

            // Pool exhausted
            return error.ConnectionPoolExhausted;
        }

        pub fn release(self: *Self, conn: *Adapter) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.available.append(self.allocator, conn) catch {
                // If we can't add back to available, just ignore
                // Connection will be cleaned up on pool deinit
            };
        }

        pub fn stats(self: *Self) Stats {
            self.mutex.lock();
            defer self.mutex.unlock();

            return .{
                .total = self.connections.items.len,
                .available = self.available.items.len,
                .in_use = self.connections.items.len - self.available.items.len,
            };
        }

        pub const Stats = struct {
            total: usize,
            available: usize,
            in_use: usize,
        };
    };
}

test "connection pool basic" {
    const MockAdapter = struct {
        value: i32 = 42,

        pub fn init(_: [:0]const u8) !@This() {
            return .{};
        }

        pub fn deinit(_: *@This()) void {}
    };

    var pool = try ConnectionPool(MockAdapter).init(std.testing.allocator, .{
        .max_connections = 5,
        .min_connections = 2,
        .connection_string = ":memory:",
    });
    defer pool.deinit();

    // Should have 2 connections initially
    const s1 = pool.stats();
    try std.testing.expectEqual(@as(usize, 2), s1.total);
    try std.testing.expectEqual(@as(usize, 2), s1.available);

    // Acquire a connection
    const conn1 = try pool.acquire();
    const s2 = pool.stats();
    try std.testing.expectEqual(@as(usize, 2), s2.total);
    try std.testing.expectEqual(@as(usize, 1), s2.available);
    try std.testing.expectEqual(@as(usize, 1), s2.in_use);

    // Release it back
    pool.release(conn1);
    const s3 = pool.stats();
    try std.testing.expectEqual(@as(usize, 2), s3.available);
}
