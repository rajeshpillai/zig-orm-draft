const std = @import("std");
const testing = std.testing;
const orm = @import("zig-orm");
const builder = orm.builder;

// Test enums
const Status = enum {
    pending,
    active,
    completed,
};

const Priority = enum(u8) {
    low = 0,
    medium = 1,
    high = 2,
};

// Test model with enums
const Task = struct {
    id: ?i64 = null,
    title: []const u8,
    status: Status,
    priority: Priority,
    optional_status: ?Status = null,
};

const TaskTable = struct {
    pub const table_name = "tasks_enum";
    pub const model_type = Task;
    pub const columns = [_]builder.Column{
        .{ .name = "id", .type = .integer },
        .{ .name = "title", .type = .text },
        .{ .name = "status", .type = .text }, // TEXT for string enum
        .{ .name = "priority", .type = .integer }, // INTEGER for int enum
        .{ .name = "optional_status", .type = .text },
    };
};

test "postgresql enum - TEXT and INTEGER mapping" {
    var db = orm.postgres.PostgreSQL.init("host=localhost port=5432 dbname=test_primary user=postgres password=root123") catch {
        std.debug.print("Skipping PostgreSQL enum test - database not available\n", .{});
        return error.SkipZigTest;
    };
    defer db.deinit();

    // Setup
    db.exec("DROP TABLE IF EXISTS tasks_enum") catch {};
    try db.exec("CREATE TABLE tasks_enum (id SERIAL PRIMARY KEY, title TEXT, status TEXT, priority INTEGER, optional_status TEXT)");

    var repo = orm.Repo(orm.postgres.PostgreSQL).initFromAdapter(testing.allocator, db);

    // Insert task with both enum types
    {
        var changeset = try builder.Table(Task, "tasks_enum").insert(testing.allocator);
        defer changeset.deinit();

        try changeset.add(.{
            .title = "Test Task",
            .status = .active,
            .priority = .high,
            .optional_status = .completed,
        });

        try repo.insert(&changeset);
    }

    // Verify TEXT enum storage
    {
        var stmt = try db.prepare("SELECT status FROM tasks_enum WHERE id = $1");
        defer stmt.deinit();
        try stmt.bind_int(0, 1);

        try testing.expect(try stmt.step());
        const status_text = orm.postgres.PostgreSQL.column_text(&stmt, 0);
        try testing.expectEqualStrings("active", status_text.?);
    }

    // Verify INTEGER enum storage
    {
        var stmt = try db.prepare("SELECT priority FROM tasks_enum WHERE id = $1");
        defer stmt.deinit();
        try stmt.bind_int(0, 1);

        try testing.expect(try stmt.step());
        const priority_int = orm.postgres.PostgreSQL.column_int(&stmt, 0);
        try testing.expectEqual(@as(i64, 2), priority_int); // high = 2
    }

    // Query and verify deserialization
    {
        const tasks = try repo.findAllBy(TaskTable, .{});
        defer testing.allocator.free(tasks);

        try testing.expectEqual(@as(usize, 1), tasks.len);
        try testing.expectEqual(Status.active, tasks[0].status);
        try testing.expectEqual(Priority.high, tasks[0].priority);
        try testing.expectEqual(Status.completed, tasks[0].optional_status.?);
    }

    // Cleanup
    try db.exec("DROP TABLE tasks_enum");
}

test "postgresql enum - all enum values" {
    var db = orm.postgres.PostgreSQL.init("host=localhost port=5432 dbname=test_primary user=postgres password=root123") catch {
        std.debug.print("Skipping PostgreSQL enum test - database not available\n", .{});
        return error.SkipZigTest;
    };
    defer db.deinit();

    db.exec("DROP TABLE IF EXISTS tasks_enum") catch {};
    try db.exec("CREATE TABLE tasks_enum (id SERIAL PRIMARY KEY, title TEXT, status TEXT, priority INTEGER, optional_status TEXT)");

    var repo = orm.Repo(orm.postgres.PostgreSQL).initFromAdapter(testing.allocator, db);

    // Insert tasks with all enum combinations
    const test_cases = [_]struct {
        status: Status,
        priority: Priority,
    }{
        .{ .status = .pending, .priority = .low },
        .{ .status = .active, .priority = .medium },
        .{ .status = .completed, .priority = .high },
    };

    for (test_cases) |tc| {
        var changeset = try builder.Table(Task, "tasks_enum").insert(testing.allocator);
        defer changeset.deinit();

        try changeset.add(.{
            .title = "Test",
            .status = tc.status,
            .priority = tc.priority,
        });

        try repo.insert(&changeset);
    }

    // Verify all values
    {
        const tasks = try repo.findAllBy(TaskTable, .{});
        defer testing.allocator.free(tasks);

        try testing.expectEqual(@as(usize, 3), tasks.len);

        try testing.expectEqual(Status.pending, tasks[0].status);
        try testing.expectEqual(Priority.low, tasks[0].priority);

        try testing.expectEqual(Status.active, tasks[1].status);
        try testing.expectEqual(Priority.medium, tasks[1].priority);

        try testing.expectEqual(Status.completed, tasks[2].status);
        try testing.expectEqual(Priority.high, tasks[2].priority);
    }

    // Cleanup
    try db.exec("DROP TABLE tasks_enum");
}

test "postgresql enum - optional enum NULL handling" {
    var db = orm.postgres.PostgreSQL.init("host=localhost port=5432 dbname=test_primary user=postgres password=root123") catch {
        std.debug.print("Skipping PostgreSQL enum test - database not available\n", .{});
        return error.SkipZigTest;
    };
    defer db.deinit();

    db.exec("DROP TABLE IF EXISTS tasks_enum") catch {};
    try db.exec("CREATE TABLE tasks_enum (id SERIAL PRIMARY KEY, title TEXT, status TEXT, priority INTEGER, optional_status TEXT)");

    var repo = orm.Repo(orm.postgres.PostgreSQL).initFromAdapter(testing.allocator, db);

    // Insert with NULL optional enum
    {
        var changeset = try builder.Table(Task, "tasks_enum").insert(testing.allocator);
        defer changeset.deinit();

        try changeset.add(.{
            .title = "Task without optional",
            .status = .pending,
            .priority = .low,
            .optional_status = null,
        });

        try repo.insert(&changeset);
    }

    // Verify NULL handling
    {
        const tasks = try repo.findAllBy(TaskTable, .{});
        defer testing.allocator.free(tasks);

        try testing.expectEqual(@as(usize, 1), tasks.len);
        try testing.expect(tasks[0].optional_status == null);
    }

    // Cleanup
    try db.exec("DROP TABLE tasks_enum");
}
