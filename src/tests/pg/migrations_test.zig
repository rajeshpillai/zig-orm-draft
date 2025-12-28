const std = @import("std");
const orm = @import("zig-orm");

// Example migration 001: Create users table
pub fn up_001(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const db: *orm.postgres.PostgreSQL = @ptrCast(@alignCast(db_ptr));
    // Use unique table names for isolation
    try db.exec(
        \\CREATE TABLE users_mig (
        \\    id BIGINT PRIMARY KEY,
        \\    name TEXT NOT NULL,
        \\    email TEXT NOT NULL UNIQUE,
        \\    created_at BIGINT NOT NULL
        \\)
    );
}

pub fn down_001(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const db: *orm.postgres.PostgreSQL = @ptrCast(@alignCast(db_ptr));
    try db.exec("DROP TABLE users_mig");
}

// Example migration 002: Create posts table
pub fn up_002(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const db: *orm.postgres.PostgreSQL = @ptrCast(@alignCast(db_ptr));
    try db.exec(
        \\CREATE TABLE posts_mig (
        \\    id BIGINT PRIMARY KEY,
        \\    title TEXT NOT NULL,
        \\    user_id BIGINT NOT NULL
        \\)
    );
}

pub fn down_002(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const db: *orm.postgres.PostgreSQL = @ptrCast(@alignCast(db_ptr));
    try db.exec("DROP TABLE posts_mig");
}

const CONN_STR = "postgresql://postgres:root123@localhost:5432/mydb";

test "pg migrations - apply and rollback" {
    var db = try orm.postgres.PostgreSQL.init(CONN_STR);
    defer db.deinit();

    // Clean up from previous runs
    try db.exec("DROP TABLE IF EXISTS users_mig");
    try db.exec("DROP TABLE IF EXISTS posts_mig");
    try db.exec("DROP TABLE IF EXISTS migrations");

    const migrations_list = [_]orm.migrations.Migration{
        .{ .version = 1, .name = "create_users", .up = &up_001, .down = &down_001 },
        .{ .version = 2, .name = "create_posts", .up = &up_002, .down = &down_002 },
    };

    var runner = orm.migrations.MigrationRunner(orm.postgres.PostgreSQL).init(&db, std.testing.allocator);

    // Apply all migrations
    try runner.migrate(&migrations_list);

    // Check current version
    const version = try runner.getCurrentVersion();
    try std.testing.expectEqual(@as(?i64, 2), version);

    // Verify migrations table exists and entries are there
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

test "pg migrations - idempotency" {
    var db = try orm.postgres.PostgreSQL.init(CONN_STR);
    defer db.deinit();

    // Clean up
    try db.exec("DROP TABLE IF EXISTS users_mig");
    try db.exec("DROP TABLE IF EXISTS migrations");

    const migrations_list = [_]orm.migrations.Migration{
        .{ .version = 1, .name = "create_users", .up = &up_001, .down = &down_001 },
    };

    var runner = orm.migrations.MigrationRunner(orm.postgres.PostgreSQL).init(&db, std.testing.allocator);

    // Apply migration twice
    try runner.migrate(&migrations_list);
    try runner.migrate(&migrations_list); // Should skip

    // Should still be at version 1
    const version = try runner.getCurrentVersion();
    try std.testing.expectEqual(@as(?i64, 1), version);
}
