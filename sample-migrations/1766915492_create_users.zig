const std = @import("std");
const orm = @import("zig-orm");

pub fn up(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);

    try helper.createTable("users", &.{
        .{ .name = "id", .type = .integer, .primary_key = true },
        .{ .name = "name", .type = .text, .nullable = false },
        .{ .name = "email", .type = .text, .nullable = false },
        .{ .name = "created_at", .type = .integer },
        .{ .name = "updated_at", .type = .integer },
    });

    try helper.addIndex("users", "idx_users_email", &.{"email"}, true);
}

pub fn down(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);
    try helper.dropTable("users");
}
