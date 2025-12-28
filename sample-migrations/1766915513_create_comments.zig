const std = @import("std");
const orm = @import("zig-orm");

pub fn up(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);

    try helper.createTable("comments", &.{
        .{ .name = "id", .type = .integer, .primary_key = true },
        .{ .name = "post_id", .type = .integer, .nullable = false },
        .{ .name = "user_id", .type = .integer, .nullable = false },
        .{ .name = "body", .type = .text, .nullable = false },
        .{ .name = "created_at", .type = .integer },
    });

    try helper.addIndex("comments", "idx_comments_post_id", &.{"post_id"}, false);
}

pub fn down(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);
    try helper.dropTable("comments");
}
