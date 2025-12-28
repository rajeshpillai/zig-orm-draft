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
    pub const table_name = "tasks";
    pub const model_type = Task;
    pub const columns = [_]builder.Column{
        .{ .name = "id", .type = .integer },
        .{ .name = "title", .type = .text },
        .{ .name = "status", .type = .text }, // TEXT for string enum
        .{ .name = "priority", .type = .integer }, // INTEGER for int enum
        .{ .name = "optional_status", .type = .text },
    };
};

test "sqlite enum - TEXT enum mapping" {
    const db_path = "test_enum_text.db";
    defer std.fs.cwd().deleteFile(db_path) catch {};

    var db = try orm.sqlite.SQLite.init(db_path);
    defer db.deinit();

    try db.exec("CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT, status TEXT, priority INTEGER, optional_status TEXT)");

    var repo = orm.Repo(orm.sqlite.SQLite).initFromAdapter(testing.allocator, db);

    // Insert task with TEXT enum
    {
        var changeset = try builder.Table(Task, "tasks").insert(testing.allocator);
        defer changeset.deinit();

        try changeset.add(.{
            .title = "Test Task",
            .status = .active,
            .priority = .high,
        });

        try repo.insert(&changeset);
    }

    // Verify TEXT enum was stored correctly
    {
        var stmt = try db.prepare("SELECT status FROM tasks WHERE id = ?");
        defer stmt.deinit();
        try stmt.bind_int(0, 1);

        try testing.expect(try stmt.step());
        const status_text = orm.sqlite.SQLite.column_text(&stmt, 0);
        try testing.expectEqualStrings("active", status_text.?);
    }

    // Query and verify enum deserialization
    {
        const tasks = try repo.findAllBy(TaskTable, .{});
        defer testing.allocator.free(tasks);

        try testing.expectEqual(@as(usize, 1), tasks.len);
        try testing.expectEqual(Status.active, tasks[0].status);
        try testing.expectEqualStrings("Test Task", tasks[0].title);
    }
}

test "sqlite enum - INTEGER enum mapping" {
    const db_path = "test_enum_int.db";
    defer std.fs.cwd().deleteFile(db_path) catch {};

    var db = try orm.sqlite.SQLite.init(db_path);
    defer db.deinit();

    try db.exec("CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT, status TEXT, priority INTEGER, optional_status TEXT)");

    var repo = orm.Repo(orm.sqlite.SQLite).initFromAdapter(testing.allocator, db);

    // Insert task with INTEGER enum
    {
        var changeset = try builder.Table(Task, "tasks").insert(testing.allocator);
        defer changeset.deinit();

        try changeset.add(.{
            .title = "Priority Task",
            .status = .pending,
            .priority = .medium,
        });

        try repo.insert(&changeset);
    }

    // Verify INTEGER enum was stored correctly
    {
        var stmt = try db.prepare("SELECT priority FROM tasks WHERE id = ?");
        defer stmt.deinit();
        try stmt.bind_int(0, 1);

        try testing.expect(try stmt.step());
        const priority_int = orm.sqlite.SQLite.column_int(&stmt, 0);
        try testing.expectEqual(@as(i64, 1), priority_int); // medium = 1
    }

    // Query and verify enum deserialization
    {
        const tasks = try repo.findAllBy(TaskTable, .{});
        defer testing.allocator.free(tasks);

        try testing.expectEqual(@as(usize, 1), tasks.len);
        try testing.expectEqual(Priority.medium, tasks[0].priority);
    }
}

test "sqlite enum - optional enum handling" {
    const db_path = "test_enum_optional.db";
    defer std.fs.cwd().deleteFile(db_path) catch {};

    var db = try orm.sqlite.SQLite.init(db_path);
    defer db.deinit();

    try db.exec("CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT, status TEXT, priority INTEGER, optional_status TEXT)");

    var repo = orm.Repo(orm.sqlite.SQLite).initFromAdapter(testing.allocator, db);

    // Insert with NULL optional enum
    {
        var changeset = try builder.Table(Task, "tasks").insert(testing.allocator);
        defer changeset.deinit();

        try changeset.add(.{
            .title = "Task without optional",
            .status = .pending,
            .priority = .low,
            .optional_status = null,
        });

        try repo.insert(&changeset);
    }

    // Insert with non-NULL optional enum
    {
        var changeset = try builder.Table(Task, "tasks").insert(testing.allocator);
        defer changeset.deinit();

        try changeset.add(.{
            .title = "Task with optional",
            .status = .active,
            .priority = .high,
            .optional_status = .completed,
        });

        try repo.insert(&changeset);
    }

    // Query and verify
    {
        const tasks = try repo.findAllBy(TaskTable, .{});
        defer testing.allocator.free(tasks);

        try testing.expectEqual(@as(usize, 2), tasks.len);

        // First task - null optional
        try testing.expect(tasks[0].optional_status == null);

        // Second task - non-null optional
        try testing.expect(tasks[1].optional_status != null);
        try testing.expectEqual(Status.completed, tasks[1].optional_status.?);
    }
}

test "sqlite enum - all enum values" {
    const db_path = "test_enum_all_values.db";
    defer std.fs.cwd().deleteFile(db_path) catch {};

    var db = try orm.sqlite.SQLite.init(db_path);
    defer db.deinit();

    try db.exec("CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT, status TEXT, priority INTEGER, optional_status TEXT)");

    var repo = orm.Repo(orm.sqlite.SQLite).initFromAdapter(testing.allocator, db);

    // Insert tasks with all enum values
    const test_cases = [_]struct {
        status: Status,
        priority: Priority,
    }{
        .{ .status = .pending, .priority = .low },
        .{ .status = .active, .priority = .medium },
        .{ .status = .completed, .priority = .high },
    };

    for (test_cases) |tc| {
        var changeset = try builder.Table(Task, "tasks").insert(testing.allocator);
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
}
