const std = @import("std");
const orm = @import("zig-orm");

// Example migration 001: Create users table
pub fn up_001(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    try db.exec(
        \\CREATE TABLE users (
        \\    id BIGINT PRIMARY KEY,
        \\    name TEXT NOT NULL,
        \\    email TEXT NOT NULL UNIQUE,
        \\    created_at BIGINT NOT NULL
        \\)
    );
}

pub fn down_001(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    try db.exec("DROP TABLE users");
}

// Example migration 002: Create posts table
pub fn up_002(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    try db.exec(
        \\CREATE TABLE posts (
        \\    id BIGINT PRIMARY KEY,
        \\    title TEXT NOT NULL,
        \\    user_id BIGINT NOT NULL
        \\)
    );
}

pub fn down_002(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    try db.exec("DROP TABLE posts");
}

test "migrations - apply and rollback" {
    var db = try orm.sqlite.SQLite.init(":memory:");
    defer db.deinit();

    const migrations_list = [_]orm.migrations.Migration{
        .{ .version = 1, .name = "create_users", .up = &up_001, .down = &down_001 },
        .{ .version = 2, .name = "create_posts", .up = &up_002, .down = &down_002 },
    };

    var runner = orm.migrations.MigrationRunner(orm.sqlite.SQLite).init(&db, std.testing.allocator);

    // Apply all migrations
    try runner.migrate(&migrations_list);

    // Check current version
    const version = try runner.getCurrentVersion();
    try std.testing.expectEqual(@as(?i64, 2), version);

    // Verify migrations table exists
    const is_applied_1 = try runner.isApplied(1);
    const is_applied_2 = try runner.isApplied(2);
    try std.testing.expect(is_applied_1);
    try std.testing.expect(is_applied_2);

    // Rollback one migration
    try runner.rollback(&migrations_list, 1);

    // Check version after rollback
    const version_after = try runner.getCurrentVersion();
    try std.testing.expectEqual(@as(?i64, 1), version_after);

    // Verify migration 2 is no longer applied
    const is_applied_2_after = try runner.isApplied(2);
    try std.testing.expect(!is_applied_2_after);
}

test "migrations - idempotency" {
    var db = try orm.sqlite.SQLite.init(":memory:");
    defer db.deinit();

    const migrations_list = [_]orm.migrations.Migration{
        .{ .version = 1, .name = "create_users", .up = &up_001, .down = &down_001 },
    };

    var runner = orm.migrations.MigrationRunner(orm.sqlite.SQLite).init(&db, std.testing.allocator);

    // Apply migration twice
    try runner.migrate(&migrations_list);
    try runner.migrate(&migrations_list); // Should skip

    // Should still be at version 1
    const version = try runner.getCurrentVersion();
    try std.testing.expectEqual(@as(?i64, 1), version);
}
