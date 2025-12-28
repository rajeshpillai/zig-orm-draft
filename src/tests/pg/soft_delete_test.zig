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
    pub const table_name = "users_soft_delete";
    pub const model_type = User;
    pub const columns = [_]builder.Column{
        .{ .name = "id", .type = .integer },
        .{ .name = "name", .type = .text },
        .{ .name = "email", .type = .text },
        .{ .name = "deleted_at", .type = .integer },
    };
};

test "postgresql soft delete - basic soft delete and restore" {
    var db = orm.postgres.PostgreSQL.init("host=localhost port=5432 dbname=test_primary user=postgres password=root123") catch {
        std.debug.print("Skipping PostgreSQL soft delete test - database not available\n", .{});
        return error.SkipZigTest;
    };
    defer db.deinit();

    // Setup
    db.exec("DROP TABLE IF EXISTS users_soft_delete") catch {};
    try db.exec("CREATE TABLE users_soft_delete (id SERIAL PRIMARY KEY, name TEXT, email TEXT, deleted_at BIGINT)");
    try db.exec("INSERT INTO users_soft_delete (name, email) VALUES ('Alice', 'alice@example.com')");
    try db.exec("INSERT INTO users_soft_delete (name, email) VALUES ('Bob', 'bob@example.com')");

    var repo = orm.Repo(orm.postgres.PostgreSQL).initFromAdapter(testing.allocator, db);

    // Test: Soft delete
    {
        var query = try builder.from(UserTable, testing.allocator);
        defer query.deinit();
        _ = try query.where(.{ .name = "Alice" });

        try repo.delete(&query);
    }

    // Verify: Alice is soft-deleted
    {
        var stmt = try db.prepare("SELECT deleted_at FROM users_soft_delete WHERE name = $1");
        defer stmt.deinit();
        try stmt.bind_text(0, "Alice");

        try testing.expect(try stmt.step());
        const deleted_at = orm.postgres.PostgreSQL.column_int(&stmt, 0);
        try testing.expect(deleted_at > 0);
    }

    // Test: findBy excludes soft-deleted records
    {
        const alice = try repo.findBy(UserTable, .{ .name = "Alice" });
        try testing.expect(alice == null);

        const bob = try repo.findBy(UserTable, .{ .name = "Bob" });
        try testing.expect(bob != null);
    }

    // Test: Restore
    {
        var query = try builder.from(UserTable, testing.allocator);
        defer query.deinit();
        _ = try query.where(.{ .name = "Alice" });

        try repo.restore(&query);
    }

    // Verify: Alice is restored
    {
        const alice = try repo.findBy(UserTable, .{ .name = "Alice" });
        try testing.expect(alice != null);
    }

    // Cleanup
    try db.exec("DROP TABLE users_soft_delete");
}

test "postgresql soft delete - forceDelete permanently removes record" {
    var db = orm.postgres.PostgreSQL.init("host=localhost port=5432 dbname=test_primary user=postgres password=root123") catch {
        std.debug.print("Skipping PostgreSQL soft delete test - database not available\n", .{});
        return error.SkipZigTest;
    };
    defer db.deinit();

    db.exec("DROP TABLE IF EXISTS users_soft_delete") catch {};
    try db.exec("CREATE TABLE users_soft_delete (id SERIAL PRIMARY KEY, name TEXT, email TEXT, deleted_at BIGINT)");
    try db.exec("INSERT INTO users_soft_delete (name, email) VALUES ('Charlie', 'charlie@example.com')");

    var repo = orm.Repo(orm.postgres.PostgreSQL).initFromAdapter(testing.allocator, db);

    // Test: Force delete
    {
        var query = try builder.from(UserTable, testing.allocator);
        defer query.deinit();
        _ = try query.where(.{ .name = "Charlie" });

        try repo.forceDelete(&query);
    }

    // Verify: Record is gone
    {
        var stmt = try db.prepare("SELECT COUNT(*) FROM users_soft_delete WHERE name = $1");
        defer stmt.deinit();
        try stmt.bind_text(0, "Charlie");

        _ = try stmt.step();
        const count = orm.postgres.PostgreSQL.column_int(&stmt, 0);
        try testing.expectEqual(@as(i64, 0), count);
    }

    // Cleanup
    try db.exec("DROP TABLE users_soft_delete");
}

test "postgresql soft delete - withTrashed and onlyTrashed" {
    var db = orm.postgres.PostgreSQL.init("host=localhost port=5432 dbname=test_primary user=postgres password=root123") catch {
        std.debug.print("Skipping PostgreSQL soft delete test - database not available\n", .{});
        return error.SkipZigTest;
    };
    defer db.deinit();

    db.exec("DROP TABLE IF EXISTS users_soft_delete") catch {};
    try db.exec("CREATE TABLE users_soft_delete (id SERIAL PRIMARY KEY, name TEXT, email TEXT, deleted_at BIGINT)");
    try db.exec("INSERT INTO users_soft_delete (name, email) VALUES ('Dave', 'dave@example.com')");
    try db.exec("INSERT INTO users_soft_delete (name, email) VALUES ('Eve', 'eve@example.com')");

    var repo = orm.Repo(orm.postgres.PostgreSQL).initFromAdapter(testing.allocator, db);

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
        try testing.expectEqual(@as(usize, 1), users.len);
    }

    // Test: withTrashed includes deleted
    {
        var query = try builder.from(UserTable, testing.allocator);
        defer query.deinit();
        _ = try query.withTrashed();

        const users = try repo.all(query);
        defer testing.allocator.free(users);
        try testing.expectEqual(@as(usize, 2), users.len);
    }

    // Test: onlyTrashed returns only deleted
    {
        var query = try builder.from(UserTable, testing.allocator);
        defer query.deinit();
        _ = try query.onlyTrashed();

        const users = try repo.all(query);
        defer testing.allocator.free(users);
        try testing.expectEqual(@as(usize, 1), users.len);
        try testing.expectEqualStrings("Dave", users[0].name);
    }

    // Cleanup
    try db.exec("DROP TABLE users_soft_delete");
}
