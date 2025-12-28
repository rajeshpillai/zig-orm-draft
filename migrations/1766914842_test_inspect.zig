const std = @import("std");
const orm = @import("zig-orm");

pub fn up(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    try db.exec("CREATE TABLE inspect_me (id INTEGER PRIMARY KEY, title TEXT NOT NULL, score REAL, is_active INTEGER)");
}

pub fn down(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    try db.exec("DROP TABLE IF EXISTS inspect_me");
}
