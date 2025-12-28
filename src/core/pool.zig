const std = @import("std");

/// A thread-safe connection pool for generic Adapters.
/// The Adapter generic type must support:
/// - `init(conn_str: [:0]const u8) !Adapter`
/// - `deinit()`
/// - `exec`, `prepare`, `changes`, and static `column_*` methods.
pub fn Pool(comptime Adapter: type) type {
    return struct {
        const Self = @This();

        pub const Config = struct {
            max_connections: usize = 10,
        };

        allocator: std.mem.Allocator,
        connections: std.ArrayList(*Adapter),
        free_indices: std.ArrayList(usize),
        mutex: std.Thread.Mutex,
        cond: std.Thread.Condition,

        // We keep track of the config and conn_str in case we need to reconnect,
        // though currently we init all upfront.
        config: Config,

        pub fn init(allocator: std.mem.Allocator, config: Config, conn_str: [:0]const u8) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            self.allocator = allocator;
            self.config = config;
            self.connections = try std.ArrayList(*Adapter).initCapacity(allocator, config.max_connections);
            self.free_indices = try std.ArrayList(usize).initCapacity(allocator, config.max_connections);
            self.mutex = .{};
            self.cond = .{};

            errdefer {
                // Cleanup on partial failure
                for (self.connections.items) |conn| {
                    conn.deinit();
                    allocator.destroy(conn);
                }
                self.connections.deinit(allocator);
                self.free_indices.deinit(allocator);
            }

            for (0..config.max_connections) |i| {
                const conn = try allocator.create(Adapter);
                // Attempt to initialize connection
                conn.* = try Adapter.init(conn_str);

                // Add to lists
                // Note: If append fails (unlikely due to initCapacity), we are in trouble,
                // but we should handle it.
                self.connections.append(allocator, conn) catch return error.OutOfMemory;
                self.free_indices.append(allocator, i) catch return error.OutOfMemory;
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.mutex.lock();
            // In a robust implementation, we might wait for all connections to be free.
            // Here we force close.
            for (self.connections.items) |conn| {
                conn.deinit();
                self.allocator.destroy(conn);
            }
            self.connections.deinit(self.allocator);
            self.free_indices.deinit(self.allocator);
            self.mutex.unlock();

            self.allocator.destroy(self);
        }

        pub fn acquire(self: *Self) !PooledAdapter(Adapter) {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.free_indices.items.len == 0) {
                self.cond.wait(&self.mutex);
            }

            const index = self.free_indices.pop().?;
            return PooledAdapter(Adapter){
                .pool = self,
                .adapter = self.connections.items[index],
                .index = index,
            };
        }

        pub fn release(self: *Self, index: usize) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // We push back the index.
            // Since we pre-allocated, this shouldn't fail unless logic error.
            self.free_indices.append(self.allocator, index) catch @panic("Pool.release: free_indices overflow");

            self.cond.signal();
        }
    };
}

/// A wrapper around an Adapter that automatically releases itself back to the Pool on deinit.
pub fn PooledAdapter(comptime Adapter: type) type {
    return struct {
        const Self = @This();

        pool: *Pool(Adapter),
        adapter: *Adapter,
        index: usize,

        // Re-export Stmt from underlying Adapter so Repo can use it
        pub const Stmt = Adapter.Stmt;

        // Implement Adapter interface by forwarding

        pub fn deinit(self: *Self) void {
            self.pool.release(self.index);
            // After this, `self` should not be used.
            // In typical usage (Repo), Repo owns this struct value.
        }

        pub fn exec(self: *Self, sql: [:0]const u8) !void {
            return self.adapter.exec(sql);
        }

        pub fn prepare(self: *Self, sql: [:0]const u8) !Stmt {
            return self.adapter.prepare(sql);
        }

        pub fn changes(self: *Self) usize {
            return self.adapter.changes();
        }

        // Static helpers required by Repo
        pub fn column_int(stmt: *Stmt, idx: usize) i64 {
            return Adapter.column_int(stmt, idx);
        }

        pub fn column_text(stmt: *Stmt, idx: usize) ?[:0]const u8 {
            return Adapter.column_text(stmt, idx);
        }
    };
}
