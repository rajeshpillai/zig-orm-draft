# Soft Delete Guide

Soft delete allows you to mark records as deleted without physically removing them from the database. This is useful for:
- Audit trails and compliance
- Data recovery
- Maintaining referential integrity
- Historical analysis

## Quick Start

### 1. Add `deleted_at` Field to Your Model

```zig
const User = struct {
    id: ?i64 = null,
    name: []const u8,
    email: []const u8,
    deleted_at: ?i64 = null, // This enables soft delete
};
```

The ORM automatically detects the `deleted_at` field and enables soft delete behavior.

### 2. Use Normal Delete Operations

```zig
// Soft delete (sets deleted_at timestamp)
var query = try builder.from(UserTable, allocator);
_ = try query.where(.{ .id = 123 });
try repo.delete(&query);
```

### 3. Queries Automatically Exclude Deleted Records

```zig
// Only returns non-deleted users
const users = try repo.findAllBy(UserTable, .{});

// Won't find soft-deleted user
const user = try repo.findBy(UserTable, .{ .id = 123 });
```

## Core Methods

### `delete(query)`
Smart delete that automatically chooses soft or hard delete:
- **Soft delete** if model has `deleted_at` field
- **Hard delete** if model doesn't have `deleted_at`

```zig
var query = try builder.from(UserTable, allocator);
_ = try query.where(.{ .id = 123 });
try repo.delete(&query); // Soft deletes if User has deleted_at
```

### `forceDelete(query)`
Permanently removes record from database, even if model supports soft delete:

```zig
var query = try builder.from(UserTable, allocator);
_ = try query.where(.{ .id = 123 });
try repo.forceDelete(&query); // Always hard deletes
```

### `restore(query)`
Un-deletes soft-deleted records by setting `deleted_at` to NULL:

```zig
var query = try builder.from(UserTable, allocator);
_ = try query.where(.{ .id = 123 });
try repo.restore(&query); // Brings back deleted record
```

## Query Modifiers

### `withTrashed()`
Include soft-deleted records in query results:

```zig
var query = try builder.from(UserTable, allocator);
_ = try query.withTrashed(); // Include deleted records

const all_users = try repo.all(query); // Returns both active and deleted
```

### `onlyTrashed()`
Return only soft-deleted records (useful for audit queries):

```zig
var query = try builder.from(UserTable, allocator);
_ = try query.onlyTrashed(); // Only deleted records

const deleted_users = try repo.all(query); // Audit trail
```

## Complete Example

```zig
const std = @import("std");
const orm = @import("zig-orm");
const builder = orm.builder;

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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var repo = try orm.Repo(orm.sqlite.SQLite).init(allocator, "app.db");
    defer repo.deinit();

    // Soft delete a user
    {
        var query = try builder.from(UserTable, allocator);
        defer query.deinit();
        _ = try query.where(.{ .email = "user@example.com" });
        try repo.delete(&query);
    }

    // Normal queries exclude deleted users
    {
        const active_users = try repo.findAllBy(UserTable, .{});
        defer allocator.free(active_users);
        // deleted user not in results
    }

    // Audit: View deleted users
    {
        var query = try builder.from(UserTable, allocator);
        defer query.deinit();
        _ = try query.onlyTrashed();
        
        const deleted_users = try repo.all(query);
        defer allocator.free(deleted_users);
        // Shows only deleted users
    }

    // Restore a deleted user
    {
        var query = try builder.from(UserTable, allocator);
        defer query.deinit();
        _ = try query.where(.{ .email = "user@example.com" });
        try repo.restore(&query);
    }

    // Permanently delete (cannot be restored)
    {
        var query = try builder.from(UserTable, allocator);
        defer query.deinit();
        _ = try query.where(.{ .email = "spam@example.com" });
        try repo.forceDelete(&query);
    }
}
```

## Database Schema

### SQLite
```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    name TEXT,
    email TEXT,
    deleted_at INTEGER  -- Unix timestamp in milliseconds
);
```

### PostgreSQL
```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name TEXT,
    email TEXT,
    deleted_at BIGINT  -- Unix timestamp in milliseconds
);
```

## Best Practices

### 1. Use Soft Delete for User Data
```zig
// Good: User-generated content
const Post = struct {
    id: ?i64 = null,
    title: []const u8,
    content: []const u8,
    deleted_at: ?i64 = null, // ✓ Can be recovered
};
```

### 2. Use Hard Delete for Temporary Data
```zig
// Good: Session tokens, cache entries
const Session = struct {
    id: ?i64 = null,
    token: []const u8,
    expires_at: i64,
    // No deleted_at - hard delete is fine
};
```

### 3. Audit Queries
```zig
// Generate compliance reports
var query = try builder.from(UserTable, allocator);
_ = try query.onlyTrashed();
_ = try query.where(.{ "deleted_at", .gte, last_month_timestamp });

const recently_deleted = try repo.all(query);
// Report on deleted users for compliance
```

### 4. Cleanup Old Soft-Deleted Records
```zig
// Permanently remove old soft-deleted records
const thirty_days_ago = std.time.timestamp() - (30 * 24 * 60 * 60 * 1000);

var query = try builder.from(UserTable, allocator);
_ = try query.whereNotNull("deleted_at");
_ = try query.where(.{ "deleted_at", .lt, thirty_days_ago });

try repo.forceDelete(&query); // Permanent cleanup
```

## Behavior Summary

| Operation | Model with `deleted_at` | Model without `deleted_at` |
|-----------|------------------------|---------------------------|
| `delete()` | Soft delete (sets timestamp) | Hard delete (removes row) |
| `forceDelete()` | Hard delete | Hard delete |
| `restore()` | Sets `deleted_at` to NULL | Error: not supported |
| `findBy()` | Excludes deleted | Normal query |
| `findAllBy()` | Excludes deleted | Normal query |
| `withTrashed()` | Includes deleted | N/A |
| `onlyTrashed()` | Only deleted | N/A |

## Migration from Hard Delete

If you're adding soft delete to an existing model:

1. **Add the field to your model:**
```zig
const User = struct {
    // ... existing fields ...
    deleted_at: ?i64 = null, // Add this
};
```

2. **Create a migration:**
```zig
pub fn up(helper: *MigrationHelper) !void {
    try helper.addColumn("users", "deleted_at", .integer, .{ .nullable = true });
}

pub fn down(helper: *MigrationHelper) !void {
    try helper.dropColumn("users", "deleted_at");
}
```

3. **Existing code continues to work:**
- `delete()` automatically switches to soft delete
- Queries automatically filter deleted records
- No code changes needed!

## Performance Considerations

- **Indexes**: Consider adding an index on `deleted_at` for large tables:
  ```sql
  CREATE INDEX idx_users_deleted_at ON users(deleted_at);
  ```

- **Query Performance**: Soft delete adds a `WHERE deleted_at IS NULL` clause to queries. This is typically very fast with proper indexing.

- **Storage**: Soft-deleted records consume storage. Implement periodic cleanup for old deleted records.

## Troubleshooting

### Issue: Can't find recently deleted record

**Solution**: Use `withTrashed()` to include deleted records:
```zig
var query = try builder.from(UserTable, allocator);
_ = try query.withTrashed();
const user = try repo.findBy(UserTable, .{ .id = 123 });
```

### Issue: Want to permanently delete immediately

**Solution**: Use `forceDelete()` instead of `delete()`:
```zig
try repo.forceDelete(&query); // Bypasses soft delete
```

### Issue: Restore not working

**Check**: Ensure model has `deleted_at` field and record is actually soft-deleted:
```zig
// Verify record exists and is deleted
var query = try builder.from(UserTable, allocator);
_ = try query.onlyTrashed();
_ = try query.where(.{ .id = 123 });
const deleted = try repo.all(query);
// If empty, record doesn't exist or isn't soft-deleted
```
