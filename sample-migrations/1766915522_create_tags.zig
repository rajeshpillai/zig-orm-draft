const std = @import("std");
const orm = @import("zig-orm");

pub fn up(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);

    // Tags Table
    try helper.createTable("tags", &.{
        .{ .name = "id", .type = .integer, .primary_key = true },
        .{ .name = "name", .type = .text, .nullable = false },
    });
    try helper.addIndex("tags", "idx_tags_name", &.{"name"}, true);

    // Join Table: posts_tags
    try helper.createTable("posts_tags", &.{
        .{ .name = "post_id", .type = .integer, .nullable = false },
        .{ .name = "tag_id", .type = .integer, .nullable = false },
    });

    try helper.addIndex("posts_tags", "idx_posts_tags_unique", &.{ "post_id", "tag_id" }, true);
}

pub fn down(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);
    try helper.dropTable("posts_tags");
    try helper.dropTable("tags");
}
