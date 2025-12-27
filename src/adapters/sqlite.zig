const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const SQLite = struct {
    const Self = @This();

    db: ?*c.sqlite3,

    pub const Config = struct {
        path: [:0]const u8,
    };

    pub fn init(path: [:0]const u8) !Self {
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path, &db);
        if (rc != c.SQLITE_OK) {
            return error.SQLiteOpenError;
        }
        return Self{ .db = db };
    }

    pub fn deinit(self: *Self) void {
        _ = c.sqlite3_close(self.db);
    }

    pub const Stmt = struct {
        stmt: ?*c.sqlite3_stmt,

        pub fn deinit(self: *Stmt) void {
            _ = c.sqlite3_finalize(self.stmt);
        }

        pub fn step(self: *Stmt) !bool {
            const rc = c.sqlite3_step(self.stmt);
            if (rc == c.SQLITE_ROW) return true;
            if (rc == c.SQLITE_DONE) return false;
            return error.SQLiteStepError;
        }
    };

    pub fn prepare(self: *Self, sql: [:0]const u8) !Stmt {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) {
            const err_msg = c.sqlite3_errmsg(self.db);
            std.debug.print("SQLite error: {s}\n", .{err_msg});
            return error.SQLitePrepareError;
        }
        return Stmt{ .stmt = stmt };
    }

    pub fn exec(self: *Self, sql: [:0]const u8) !void {
        var stmt = try self.prepare(sql);
        defer stmt.deinit();
        _ = try stmt.step();
    }

    pub fn column_int(stmt: *Stmt, col: usize) i64 {
        return c.sqlite3_column_int64(stmt.stmt, @intCast(col));
    }

    pub fn column_text(stmt: *Stmt, col: usize) ?[:0]const u8 {
        const ptr = c.sqlite3_column_text(stmt.stmt, @intCast(col));
        if (ptr == null) return null;
        return std.mem.span(ptr);
    }
};

test "sqlite exec" {
    var db = try SQLite.init(":memory:");
    defer db.deinit();

    try db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)");
    try db.exec("INSERT INTO users (name) VALUES ('Alice')");

    var stmt = try db.prepare("SELECT name FROM users");
    defer stmt.deinit();

    if (try stmt.step()) {
        // TODO: Read column
    }
}
