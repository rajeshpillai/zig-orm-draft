const std = @import("std");
const Allocator = std.mem.Allocator;

// PostgreSQL C library bindings
const c = @cImport({
    @cInclude("libpq-fe.h");
});

pub const PostgreSQL = struct {
    conn: ?*c.PGconn,
    allocator: Allocator,

    pub fn init(connection_string: [:0]const u8) !PostgreSQL {
        const conn = c.PQconnectdb(connection_string.ptr);
        if (c.PQstatus(conn) != c.CONNECTION_OK) {
            const err_msg = c.PQerrorMessage(conn);
            std.debug.print("PostgreSQL connection failed: {s}\n", .{err_msg});
            c.PQfinish(conn);
            return error.ConnectionFailed;
        }

        return PostgreSQL{
            .conn = conn,
            .allocator = std.heap.page_allocator, // TODO: Use proper allocator
        };
    }

    pub fn deinit(self: *PostgreSQL) void {
        if (self.conn) |conn| {
            c.PQfinish(conn);
        }
    }

    pub fn exec(self: *PostgreSQL, sql: [:0]const u8) !void {
        const result = c.PQexec(self.conn, sql.ptr);
        defer c.PQclear(result);

        const status = c.PQresultStatus(result);
        if (status != c.PGRES_COMMAND_OK and status != c.PGRES_TUPLES_OK) {
            const err_msg = c.PQerrorMessage(self.conn);
            std.debug.print("PostgreSQL exec failed: {s}\n", .{err_msg});
            return error.ExecFailed;
        }
    }

    pub fn prepare(self: *PostgreSQL, sql: [:0]const u8) !Stmt {
        return Stmt{
            .conn = self.conn,
            .sql = sql,
            .params = .{},
            .param_values = .{},
            .result = null,
            .current_row = 0,
            .allocator = self.allocator,
        };
    }

    pub const Stmt = struct {
        conn: ?*c.PGconn,
        sql: [:0]const u8,
        params: std.ArrayList([:0]const u8),
        param_values: std.ArrayList([*c]const u8),
        result: ?*c.PGresult,
        current_row: i32,
        allocator: Allocator,

        pub fn deinit(self: *Stmt) void {
            if (self.result) |result| {
                c.PQclear(result);
            }
            // Free allocated parameter strings
            for (self.params.items) |param| {
                self.allocator.free(param);
            }
            self.params.deinit(self.allocator);
            self.param_values.deinit(self.allocator);
        }

        pub fn bind_int(self: *Stmt, _: usize, val: i64) !void {
            // Convert int to sentinel-terminated string for PostgreSQL
            const str_no_null = try std.fmt.allocPrint(self.allocator, "{d}", .{val});
            defer self.allocator.free(str_no_null);
            const str = try self.allocator.dupeZ(u8, str_no_null);
            try self.params.append(self.allocator, str);
            try self.param_values.append(self.allocator, str.ptr);
        }

        pub fn bind_text(self: *Stmt, _: usize, val: []const u8) !void {
            const duped = try self.allocator.dupeZ(u8, val);
            try self.params.append(self.allocator, duped);
            try self.param_values.append(self.allocator, duped.ptr);
        }

        pub fn step(self: *Stmt) !bool {
            if (self.result == null) {
                // Execute query with parameters
                self.result = c.PQexecParams(
                    self.conn,
                    self.sql.ptr,
                    @intCast(self.param_values.items.len),
                    null, // param types (NULL = infer)
                    @ptrCast(self.param_values.items.ptr),
                    null, // param lengths (NULL = text)
                    null, // param formats (NULL = text)
                    0, // result format (0 = text)
                );

                const status = c.PQresultStatus(self.result);
                if (status != c.PGRES_COMMAND_OK and status != c.PGRES_TUPLES_OK) {
                    const err_msg = c.PQerrorMessage(self.conn);
                    std.debug.print("PostgreSQL query failed: {s}\n", .{err_msg});
                    return error.QueryFailed;
                }

                self.current_row = 0;
            }

            if (self.result) |result| {
                const row_count = c.PQntuples(result);
                if (self.current_row < row_count) {
                    self.current_row += 1;
                    return true;
                }
            }

            return false;
        }

        pub fn reset(self: *Stmt) !void {
            if (self.result) |result| {
                c.PQclear(result);
                self.result = null;
            }
            self.current_row = 0;
            self.params.clearRetainingCapacity();
            self.param_values.clearRetainingCapacity();
        }
    };

    // Static column accessors (match SQLite adapter signature)
    pub fn column_int(stmt: *Stmt, idx: usize) i64 {
        if (stmt.result) |result| {
            const val = c.PQgetvalue(result, stmt.current_row - 1, @intCast(idx));
            return std.fmt.parseInt(i64, std.mem.span(val), 10) catch 0;
        }
        return 0;
    }

    pub fn column_text(stmt: *Stmt, idx: usize) ?[:0]const u8 {
        if (stmt.result) |result| {
            const val = c.PQgetvalue(result, stmt.current_row - 1, @intCast(idx));
            if (val == null) return null;
            return std.mem.span(val);
        }
        return null;
    }
};

// Note: This adapter requires libpq to be installed
// Windows: Install PostgreSQL and add to PATH
// Linux: sudo apt-get install libpq-dev
// macOS: brew install postgresql
