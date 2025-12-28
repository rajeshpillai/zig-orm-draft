const std = @import("std");
const orm = @import("zig-orm");

pub fn up(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    _ = db_ptr;
    _ = allocator;
    // const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    // var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);
    
    // try helper.createTable("table_name", &[_]orm.migrations.helpers.Column{
    //     .{ .name = "id", .type = .integer, .primary_key = true },
    // });
}

pub fn down(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    _ = db_ptr;
    _ = allocator;
    // const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    // var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);
    // try helper.dropTable("table_name");
}
