# Enum Mapping Guide

Automatic bidirectional mapping between Zig enums and database types.

## Overview

The ORM automatically handles enum serialization and deserialization based on the enum's backing type:
- **String enums** (no backing type) → TEXT storage
- **Integer enums** (with backing type) → INTEGER storage

## Quick Start

### Define Enums

```zig
// String enum - stored as TEXT
const Status = enum {
    pending,
    active,
    completed,
};

// Integer enum - stored as INTEGER
const Priority = enum(u8) {
    low = 0,
    medium = 1,
    high = 2,
};
```

### Use in Models

```zig
const Task = struct {
    id: ?i64 = null,
    title: []const u8,
    status: Status,        // TEXT column
    priority: Priority,    // INTEGER column
    optional_status: ?Status = null, // Nullable TEXT column
};
```

### Database Schema

**SQLite:**
```sql
CREATE TABLE tasks (
    id INTEGER PRIMARY KEY,
    title TEXT,
    status TEXT,           -- "pending", "active", "completed"
    priority INTEGER,      -- 0, 1, 2
    optional_status TEXT   -- NULL or "pending", etc.
);
```

**PostgreSQL:**
```sql
CREATE TABLE tasks (
    id SERIAL PRIMARY KEY,
    title TEXT,
    status TEXT,
    priority INTEGER,
    optional_status TEXT
);
```

## Storage Strategies

### TEXT Storage (String Enums)

Enums without explicit backing type are stored as their string representation:

```zig
const Status = enum {
    pending,
    active,
    completed,
};

// Database: "pending", "active", "completed"
```

**Advantages:**
- Human-readable in database
- Easy to query manually
- Self-documenting

**Use when:**
- Debugging/inspecting database
- Values may change order
- Human readability is important

### INTEGER Storage (Ordinal Enums)

Enums with explicit integer backing type are stored as integers:

```zig
const Priority = enum(u8) {
    low = 0,
    medium = 1,
    high = 2,
};

// Database: 0, 1, 2
```

**Advantages:**
- Compact storage
- Faster comparisons
- Explicit ordering

**Use when:**
- Performance is critical
- Storage space matters
- Order is meaningful

## Usage Examples

### Insert

```zig
var task = Task{
    .title = "Implement feature",
    .status = .active,
    .priority = .high,
    .optional_status = .pending,
};

try repo.insert(&task);
```

**Generated SQL (SQLite):**
```sql
INSERT INTO tasks (title, status, priority, optional_status)
VALUES ('Implement feature', 'active', 2, 'pending');
```

### Query

```zig
// Find by enum value
const active_tasks = try repo.findAllBy(TaskTable, .{ .status = .active });

// Automatic deserialization
for (active_tasks) |task| {
    std.debug.print("Task: {s}, Priority: {}\n", .{
        task.title,
        @intFromEnum(task.priority), // 0, 1, or 2
    });
}
```

### Update

```zig
var query = try builder.from(TaskTable, allocator);
_ = try query.where(.{ .id = 123 });
_ = try query.set(.{ .status = .completed });

try repo.update(&query);
```

## Optional Enums

Optional enums support NULL values:

```zig
const Task = struct {
    optional_status: ?Status = null,
};

// Insert with NULL
var task1 = Task{ .optional_status = null };
try repo.insert(&task1);

// Insert with value
var task2 = Task{ .optional_status = .active };
try repo.insert(&task2);

// Query
const tasks = try repo.findAllBy(TaskTable, .{});
if (tasks[0].optional_status) |status| {
    // Has value
} else {
    // NULL
}
```

## Error Handling

### Invalid Enum Values

The ORM validates enum values during deserialization:

```zig
// If database contains invalid value "invalid_status"
const tasks = try repo.findAllBy(TaskTable, .{});
// Returns error.InvalidEnumValue
```

### NULL Non-Optional Enums

```zig
// If database contains NULL for non-optional enum
const tasks = try repo.findAllBy(TaskTable, .{});
// Returns error.NullEnumValue
```

## Complete Example

```zig
const std = @import("std");
const orm = @import("zig-orm");
const builder = orm.builder;

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

const Task = struct {
    id: ?i64 = null,
    title: []const u8,
    status: Status,
    priority: Priority,
    created_at: ?i64 = null,
};

const TaskTable = struct {
    pub const table_name = "tasks";
    pub const model_type = Task;
    pub const columns = [_]builder.Column{
        .{ .name = "id", .type = .integer },
        .{ .name = "title", .type = .text },
        .{ .name = "status", .type = .text },
        .{ .name = "priority", .type = .integer },
        .{ .name = "created_at", .type = .integer },
    };
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var repo = try orm.Repo(orm.sqlite.SQLite).init(allocator, "app.db");
    defer repo.deinit();

    // Create table
    try repo.adapter.exec(
        \\CREATE TABLE IF NOT EXISTS tasks (
        \\    id INTEGER PRIMARY KEY,
        \\    title TEXT,
        \\    status TEXT,
        \\    priority INTEGER,
        \\    created_at INTEGER
        \\)
    );

    // Insert tasks
    var changeset = try builder.Table(Task, "tasks").insert(allocator);
    defer changeset.deinit();

    try changeset.add(.{
        .title = "High priority task",
        .status = .active,
        .priority = .high,
    });

    try changeset.add(.{
        .title = "Low priority task",
        .status = .pending,
        .priority = .low,
    });

    try repo.insert(&changeset);

    // Query by enum value
    const active_tasks = try repo.findAllBy(TaskTable, .{ .status = .active });
    defer allocator.free(active_tasks);

    for (active_tasks) |task| {
        std.debug.print("Task: {s}\n", .{task.title});
        std.debug.print("  Status: {s}\n", .{@tagName(task.status)});
        std.debug.print("  Priority: {}\n", .{@intFromEnum(task.priority)});
    }

    // Update enum value
    var query = try builder.from(TaskTable, allocator);
    defer query.deinit();
    _ = try query.where(.{ .status = .pending });

    var update_q = try builder.from(TaskTable, allocator);
    defer update_q.deinit();
    _ = try update_q.set(.{ .status = .active });
    _ = try update_q.where(.{ .status = .pending });

    try repo.update(&update_q);
}
```

## Migration Example

Adding enum columns to existing table:

```zig
pub fn up(helper: *MigrationHelper) !void {
    // TEXT enum column
    try helper.addColumn("tasks", "status", .text, .{
        .nullable = false,
        .default = "'pending'",
    });

    // INTEGER enum column
    try helper.addColumn("tasks", "priority", .integer, .{
        .nullable = false,
        .default = "0",
    });
}

pub fn down(helper: *MigrationHelper) !void {
    try helper.dropColumn("tasks", "status");
    try helper.dropColumn("tasks", "priority");
}
```

## Best Practices

### 1. Choose Storage Strategy Wisely

```zig
// Good: Use TEXT for status that may evolve
const Status = enum {
    pending,
    active,
    completed,
    // Easy to add: archived, cancelled, etc.
};

// Good: Use INTEGER for fixed priority levels
const Priority = enum(u8) {
    low = 0,
    medium = 1,
    high = 2,
};
```

### 2. Document Enum Values

```zig
/// Task status lifecycle
const Status = enum {
    pending,   // Initial state
    active,    // Work in progress
    completed, // Finished
};
```

### 3. Use Optional for Nullable Fields

```zig
const Task = struct {
    status: Status,           // Required
    optional_tag: ?Tag = null, // Optional
};
```

### 4. Validate Enum Values

```zig
pub fn validateStatus(status: Status) !void {
    switch (status) {
        .pending, .active, .completed => {},
        // Add validation logic if needed
    }
}
```

## Performance Considerations

- **TEXT enums**: Slightly larger storage, human-readable
- **INTEGER enums**: Compact storage, faster comparisons
- **Indexing**: Both types can be indexed efficiently
- **Queries**: INTEGER comparisons are marginally faster

## Troubleshooting

### Issue: Invalid enum value error

**Cause**: Database contains value not in enum definition

**Solution**: 
1. Check database data
2. Update enum definition to include all values
3. Clean invalid data

### Issue: NULL value for non-optional enum

**Cause**: Database has NULL but model expects non-optional

**Solution**:
1. Make field optional: `?Status`
2. Or ensure database has no NULLs

### Issue: Wrong storage type

**Cause**: Mismatch between enum backing type and column type

**Solution**:
```zig
// Ensure TEXT column for string enums
const Status = enum { ... };  // No backing type

// Ensure INTEGER column for int enums
const Priority = enum(u8) { ... };  // With backing type
```

## Future Enhancements

- PostgreSQL native ENUM type support
- Custom enum serialization
- Enum sets/flags
- Compile-time enum validation in queries
