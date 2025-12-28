const std = @import("std");
const testing = std.testing;
const orm = @import("zig-orm");
const builder = orm.builder;

// Test model with soft delete
const User = struct {
    id: ?i64 = null,
    name: []const u8,
    email: []const u8,
    deleted_at: ?i64 = null,
};

const UserTable = struct {
    pub const table_name = "users";
    pub const model_type = User;
    pub const columns = [_]builder.Column{
        .{ .name = "id", .type = .integer },
        .{ .name = "name", .type = .text },
        .{ .name = "email", .type = .text },
        .{ .name = "deleted_at", .type = .integer },
    };
};

test "sqlite soft delete - basic soft delete and restore" {
    const db_path = "test_soft_delete.db";
    defer std.fs.cwd().deleteFile(db_path) catch {};

    // Setup database
    var db = try orm.sqlite.SQLite.init(db_path);
    defer db.deinit();

    try db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT, deleted_at INTEGER)");
    try db.exec("INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com')");
    try db.exec("INSERT INTO users (name, email) VALUES ('Bob', 'bob@example.com')");

    var repo = orm.Repo(orm.sqlite.SQLite).initFromAdapter(testing.allocator, db);

    // Test: Soft delete
    {
        var query = try builder.from(UserTable, testing.allocator);
        defer query.deinit();
        _ = try query.where(.{ .name = "Alice" });

        try repo.delete(&query);
    }

    // Verify: Alice is soft-deleted (has deleted_at timestamp)
    {
        var stmt = try db.prepare("SELECT deleted_at FROM users WHERE name = ?");
        defer stmt.deinit();
        try stmt.bind_text(0, "Alice");

        try testing.expect(try stmt.step());
        const deleted_at = orm.sqlite.SQLite.column_int(&stmt, 0);
        try testing.expect(deleted_at > 0); // Should have timestamp
    }

    // Test: findBy excludes soft-deleted records
    {
        const alice = try repo.findBy(UserTable, .{ .name = "Alice" });
        try testing.expect(alice == null); // Should not find soft-deleted Alice

        const bob = try repo.findBy(UserTable, .{ .name = "Bob" });
        try testing.expect(bob != null); // Should find Bob
    }

    // Test: Restore soft-deleted record
    {
        var query = try builder.from(UserTable, testing.allocator);
        defer query.deinit();
        _ = try query.where(.{ .name = "Alice" });

        try repo.restore(&query);
    }

    // Verify: Alice is restored (deleted_at is NULL)
    {
        var stmt = try db.prepare("SELECT deleted_at FROM users WHERE name = ?");
        defer stmt.deinit();
        try stmt.bind_text(0, "Alice");

        try testing.expect(try stmt.step());
        const deleted_at_ptr = orm.sqlite.SQLite.column_text(&stmt, 0);
        try testing.expect(deleted_at_ptr == null); // Should be NULL
    }

    // Test: findBy now finds restored Alice
    {
        const alice = try repo.findBy(UserTable, .{ .name = "Alice" });
        try testing.expect(alice != null);
    }
}

test "sqlite soft delete - forceDelete permanently removes record" {
    const db_path = "test_force_delete.db";
    defer std.fs.cwd().deleteFile(db_path) catch {};

    var db = try orm.sqlite.SQLite.init(db_path);
    defer db.deinit();

    try db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT, deleted_at INTEGER)");
    try db.exec("INSERT INTO users (name, email) VALUES ('Charlie', 'charlie@example.com')");

    var repo = orm.Repo(orm.sqlite.SQLite).initFromAdapter(testing.allocator, db);

    // Test: Force delete
    {
        var query = try builder.from(UserTable, testing.allocator);
        defer query.deinit();
        _ = try query.where(.{ .name = "Charlie" });

        try repo.forceDelete(&query);
    }

    // Verify: Record is completely gone
    {
        var stmt = try db.prepare("SELECT COUNT(*) FROM users WHERE name = ?");
        defer stmt.deinit();
        try stmt.bind_text(0, "Charlie");

        _ = try stmt.step();
        const count = orm.sqlite.SQLite.column_int(&stmt, 0);
        try testing.expectEqual(@as(i64, 0), count);
    }
}

test "sqlite soft delete - withTrashed includes deleted records" {
    const db_path = "test_with_trashed.db";
    defer std.fs.cwd().deleteFile(db_path) catch {};

    var db = try orm.sqlite.SQLite.init(db_path);
    defer db.deinit();

    try db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT, deleted_at INTEGER)");
    try db.exec("INSERT INTO users (name, email) VALUES ('Dave', 'dave@example.com')");
    try db.exec("INSERT INTO users (name, email) VALUES ('Eve', 'eve@example.com')");

    var repo = orm.Repo(orm.sqlite.SQLite).initFromAdapter(testing.allocator, db);

    // Soft delete Dave
    {
        var query = try builder.from(UserTable, testing.allocator);
        defer query.deinit();
        _ = try query.where(.{ .name = "Dave" });
        try repo.delete(&query);
    }

    // Test: Normal query excludes deleted
    {
        const users = try repo.findAllBy(UserTable, .{});
        defer testing.allocator.free(users);
        try testing.expectEqual(@as(usize, 1), users.len); // Only Eve
    }

    // Test: withTrashed includes deleted
    {
        var query = try builder.from(UserTable, testing.allocator);
        defer query.deinit();
        _ = try query.withTrashed();

        const users = try repo.all(query);
        defer testing.allocator.free(users);
        try testing.expectEqual(@as(usize, 2), users.len); // Both Dave and Eve
    }
}

test "sqlite soft delete - onlyTrashed returns only deleted records" {
    const db_path = "test_only_trashed.db";
    defer std.fs.cwd().deleteFile(db_path) catch {};

    var db = try orm.sqlite.SQLite.init(db_path);
    defer db.deinit();

    try db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT, deleted_at INTEGER)");
    try db.exec("INSERT INTO users (name, email) VALUES ('Frank', 'frank@example.com')");
    try db.exec("INSERT INTO users (name, email) VALUES ('Grace', 'grace@example.com')");

    var repo = orm.Repo(orm.sqlite.SQLite).initFromAdapter(testing.allocator, db);

    // Soft delete Frank
    {
        var query = try builder.from(UserTable, testing.allocator);
        defer query.deinit();
        _ = try query.where(.{ .name = "Frank" });
        try repo.delete(&query);
    }

    // Test: onlyTrashed returns only deleted records
    {
        var query = try builder.from(UserTable, testing.allocator);
        defer query.deinit();
        _ = try query.onlyTrashed();

        const users = try repo.all(query);
        defer testing.allocator.free(users);
        try testing.expectEqual(@as(usize, 1), users.len); // Only Frank
        try testing.expectEqualStrings("Frank", users[0].name);
    }
}
