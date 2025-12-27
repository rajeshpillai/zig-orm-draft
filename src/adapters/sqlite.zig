const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const SQLite = struct {
    db: ?*c.sqlite3,

    pub fn init(path: [:0]const u8) !SQLite {
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path, &db);
        if (rc != c.SQLITE_OK) {
            return error.SQLiteOpenError;
        }
        return SQLite{ .db = db };
    }

    pub fn deinit(self: *SQLite) void {
        _ = c.sqlite3_close(self.db);
    }
};

test "sqlite init" {
    var db = try SQLite.init(":memory:");
    defer db.deinit();
}
