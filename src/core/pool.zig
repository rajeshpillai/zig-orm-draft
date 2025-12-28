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
            replica_conn_strs: ?[]const [:0]const u8 = null, // Optional read replicas
        };

        allocator: std.mem.Allocator,
        connections: std.ArrayList(*Adapter),
        free_indices: std.ArrayList(usize),
        replica_connections: std.ArrayList(*Adapter),
        replica_free_indices: std.ArrayList(usize),
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
            self.replica_connections = try std.ArrayList(*Adapter).initCapacity(allocator, 0);
            self.replica_free_indices = try std.ArrayList(usize).initCapacity(allocator, 0);
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
                for (self.replica_connections.items) |conn| {
                    conn.deinit();
                    allocator.destroy(conn);
                }
                self.replica_connections.deinit(allocator);
                self.replica_free_indices.deinit(allocator);
            }

            // Initialize primary connections
            for (0..config.max_connections) |i| {
                const conn = try allocator.create(Adapter);
                conn.* = try Adapter.init(conn_str);
                self.connections.append(allocator, conn) catch return error.OutOfMemory;
                self.free_indices.append(allocator, i) catch return error.OutOfMemory;
            }

            // Initialize replica connections if provided
            if (config.replica_conn_strs) |replicas| {
                for (replicas, 0..) |replica_str, i| {
                    const conn = try allocator.create(Adapter);
                    conn.* = try Adapter.init(replica_str);
                    self.replica_connections.append(allocator, conn) catch return error.OutOfMemory;
                    self.replica_free_indices.append(allocator, i) catch return error.OutOfMemory;
                }
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
            for (self.replica_connections.items) |conn| {
                conn.deinit();
                self.allocator.destroy(conn);
            }
            self.connections.deinit(self.allocator);
            self.free_indices.deinit(self.allocator);
            self.replica_connections.deinit(self.allocator);
            self.replica_free_indices.deinit(self.allocator);
            self.mutex.unlock();

            self.allocator.destroy(self);
        }

        /// Acquire a connection for write operations (always uses primary)
        pub fn acquireForWrite(self: *Self) !PooledAdapter(Adapter) {
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
                .is_replica = false,
            };
        }

        /// Acquire a connection for read operations (uses replica if available, otherwise primary)
        pub fn acquireForRead(self: *Self) !PooledAdapter(Adapter) {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Try to get a replica connection first
            if (self.replica_free_indices.items.len > 0) {
                const index = self.replica_free_indices.pop().?;
                return PooledAdapter(Adapter){
                    .pool = self,
                    .adapter = self.replica_connections.items[index],
                    .index = index,
                    .is_replica = true,
                };
            }

            // Fall back to primary if no replicas available
            while (self.free_indices.items.len == 0) {
                self.cond.wait(&self.mutex);
            }

            const index = self.free_indices.pop().?;
            return PooledAdapter(Adapter){
                .pool = self,
                .adapter = self.connections.items[index],
                .index = index,
                .is_replica = false,
            };
        }

        /// Acquire a connection (backward compatible - uses primary)
        pub fn acquire(self: *Self) !PooledAdapter(Adapter) {
            return self.acquireForWrite();
        }

        pub fn release(self: *Self, index: usize, is_replica: bool) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (is_replica) {
                self.replica_free_indices.append(self.allocator, index) catch @panic("Pool.release: replica_free_indices overflow");
            } else {
                self.free_indices.append(self.allocator, index) catch @panic("Pool.release: free_indices overflow");
            }

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
        is_replica: bool,

        // Re-export Stmt from underlying Adapter so Repo can use it
        pub const Stmt = Adapter.Stmt;

        // Implement Adapter interface by forwarding

        pub fn deinit(self: *Self) void {
            self.pool.release(self.index, self.is_replica);
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
