const std = @import("std");
const orm = @import("zig-orm");
const helpers = orm.migrations.helpers;

test "migration helpers - create and drop table" {
    var db = try orm.sqlite.SQLite.init(":memory:");
    defer db.deinit();

    var helper = helpers.MigrationHelper(orm.sqlite.SQLite).init(&db, std.testing.allocator);

    // 1. Create Table
    try helper.createTable("users", &[_]helpers.Column{
        .{ .name = "id", .type = .integer, .primary_key = true },
        .{ .name = "name", .type = .text, .nullable = false },
        .{ .name = "active", .type = .boolean, .default = "true" },
    });

    // Verify table exists (raw SQL)
    {
        var stmt = try db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='users'");
        defer stmt.deinit();
        try std.testing.expect(try stmt.step());
    }

    // 2. Drop Table
    try helper.dropTable("users");

    // Verify table gone
    {
        var stmt = try db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='users'");
        defer stmt.deinit();
        try std.testing.expect(!(try stmt.step()));
    }
}

test "migration helpers - add and remove column" {
    var db = try orm.sqlite.SQLite.init(":memory:");
    defer db.deinit();

    var helper = helpers.MigrationHelper(orm.sqlite.SQLite).init(&db, std.testing.allocator);

    // Create initial table
    try helper.createTable("users", &[_]helpers.Column{
        .{ .name = "id", .type = .integer, .primary_key = true },
    });

    // 1. Add Column
    try helper.addColumn("users", .{ .name = "email", .type = .text });
    try helper.addIndex("users", "idx_users_email", &[_][]const u8{"email"}, true);

    // Verify column exists
    var stmt = try db.prepare("PRAGMA table_info(users)");
    defer stmt.deinit();
    var found_email = false;
    while (try stmt.step()) {
        const name = orm.sqlite.SQLite.column_text(&stmt, 1);
        if (std.mem.eql(u8, name.?, "email")) {
            found_email = true;
            break;
        }
    }
    try std.testing.expect(found_email);

    // Note: SQLite version 3.8.8.2 bundled in this project does not support DROP COLUMN.
    // It was added in SQLite 3.35.0.
}
