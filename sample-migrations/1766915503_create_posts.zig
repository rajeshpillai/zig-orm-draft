const std = @import("std");
const orm = @import("zig-orm");

pub fn up(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);

    try helper.createTable("posts", &.{
        .{ .name = "id", .type = .integer, .primary_key = true },
        .{ .name = "user_id", .type = .integer, .nullable = false },
        .{ .name = "title", .type = .text, .nullable = false },
        .{ .name = "body", .type = .text },
        .{ .name = "created_at", .type = .integer },
        .{ .name = "updated_at", .type = .integer },
    });

    try helper.addIndex("posts", "idx_posts_user_id", &.{"user_id"}, false);
}

pub fn down(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);
    try helper.dropTable("posts");
}
