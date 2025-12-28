# Zig ORM

Zig Version: 0.16.0-dev.1326+2e6f7d36b

**Status**: Experimental / Pre-alpha

A typed, compile-time schema ORM for Zig, inspired by Elixir Ecto. Supports SQLite and PostgreSQL.

## Features

*   **No runtime reflection**: Schema defined at compile-time.
*   **Repo Pattern**: Ecto-style `Repo` for database interactions.
*   **Explicit SQL**: Typed query builder (`from`, `where`, `insert`, `update`, `delete`).
*   **PostgreSQL Support**: Support for `libpq`-based adapters.
*   **Connection Pooling**: Generic, thread-safe connection pooling.
*   **Automated Migrations**: Schema versioning with up/down support.
*   **Validation Framework**: Schema-level data validation rules.
*   **Automatic Timestamps**: Managed `created_at` and `updated_at` fields.
*   **Secure**: Automatic parameter binding for all operations.
*   **Embedded SQLite**: Zero-dependency build (bundles `sqlite3.c`).

## Installation

1.  Add `zig-orm` to your `build.zig`:

    ```zig
    const orm = b.dependency("zig-orm", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zig-orm", orm.module("zig-orm"));
    ```

## Usage

### 1. Define your Schema

```zig
const orm = @import("zig-orm");

const User = struct {
    id: i64,
    name: []const u8,
    active: bool,
    created_at: i64, // Auto-managed if present
    updated_at: i64, // Auto-managed if present

    // Optional validation rules
    pub const rules = .{
        .name = .{ .min_len = 3 },
    };
};
const Users = orm.Table(User, "users");
```

### 2. Initialize Repo

```zig
// SQLite
const Repo = orm.Repo(orm.sqlite.SQLite);
var repo = try Repo.init(allocator, "path/to/db.sqlite");
defer repo.deinit();

// PostgreSQL (requires libpq installed)
// const PGRepo = orm.Repo(orm.postgres.Postgres);
// var pg_repo = try PGRepo.init(allocator, "host=localhost dbname=test");
```

### 3. Connection Pooling

```zig
const Pool = orm.ConnectionPool(orm.sqlite.SQLite);
var pool = try Pool.init(allocator, .{
    .connection_string = "test.db",
    .max_connections = 10,
});
defer pool.deinit();

const conn = try pool.acquire();
defer pool.release(conn);
```

### 4. CRUD Operations

```zig
// Insert (Auto-validates and sets timestamps)
var changeset = try Users.insert(allocator);
defer changeset.deinit();
try changeset.add(.{ 
    .id = 1, 
    .name = "Alice", 
    .active = true, 
    .created_at = 0, 
    .updated_at = 0 
});
try repo.insert(changeset);

// Select with filters
var q = try orm.from(Users, allocator);
defer q.deinit();

// Simple equality (existing)
_ = try q.where(.{ .active = true });

// Comparison operators
_ = try q.where(.{ .age, .gt, 18 });
_ = try q.where(.{ .name, .like, "Ali%" });

// Logical grouping (OR/AND/NOT)
_ = try q.where(.{ .{ .active = true }, .OR, .{ .id, .lt, 100 } });

const users = try repo.all(q);

// Raw SQL Support
const Result = struct { id: i64, name: []const u8 };
const sql = "SELECT id, name FROM users WHERE age > ?";
const params = &[_]orm.Value{ .{ .Integer = 21 } };
const results = try repo.query(Result, sql, params);

// Execute non-SELECT raw SQL
try repo.execute("UPDATE users SET active = ? WHERE id = ?", &.{
    .{ .Boolean = false },
    .{ .Integer = 1 }
});

// Update (Auto-refreshes updated_at)
var u = try Users.update(allocator);
defer u.deinit();
_ = try u.set(.{ .active = false });
_ = try u.where(.{ .name = "Alice" });
try repo.update(u);
```

### 5. Model Hooks (Lifecycles)

Define methods on your model structs that run automatically before or after database operations.

```zig
pub const User = struct {
    id: i64,
    name: []const u8,

    // Runs before repository insertion
    pub fn beforeInsert(self: *User) !void {
        if (std.mem.eql(u8, self.name, "forbidden")) return error.InvalidName;
        // Logic to modify self before insert
    }

    // Runs after repository insertion
    pub fn afterInsert(self: *User) !void {
        std.debug.print("User {s} persisted successfully\n", .{self.name});
    }

    // Runs before repository update
    pub fn beforeUpdate(self: *User) !void {
        // Validation or auditing logic
    }

    // Runs before repository deletion
    pub fn beforeDelete(self: *User) !void {
        // Cleanup or restriction logic
    }
};

// Instance-based operations triggering hooks:
try repo.updateModel(Users, &user);
try repo.deleteModel(Users, &user);
```

### 6. Aggregates and Field Selection
You can select specific columns, use aggregate functions, and group results.

```zig
var q = try orm.from(Users, allocator);
_ = try q.where(.{ .active = true });

// Basic count
const total = try repo.count(&q);

// Custom selection and sum
_ = try q.select("SUM(age)");
const sum = try repo.scalar(i64, &q);

// Group by
_ = try q.select("active");
_ = try q.count("*");
_ = try q.groupBy("active");
```

### 7. Table Joins
You can perform `INNER JOIN` and `LEFT JOIN` and map results to custom structs.

```zig
const PostWithUser = struct {
    post_title: []const u8,
    user_name: []const u8,
};

var q = try orm.from(Posts, allocator);
_ = try q.select("posts.title as post_title");
_ = try q.select("users.name as user_name");
_ = try q.innerJoin(Users, "posts.user_id = users.id");

const results = try repo.allAs(PostWithUser, &q);
```

### 8. Migrations
Schema versioning with up/down support and a fluent DSL for table management.

```zig
// Migrations with DSL
pub fn up_001(db_ptr: *anyopaque) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    // Migration helpers are available via the runner or directly
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);

    try helper.createTable("users", &[_]orm.migrations.helpers.Column{
        .{ .name = "id", .type = .integer, .primary_key = true },
        .{ .name = "name", .type = .text, .nullable = false },
        .{ .name = "created_at", .type = .timestamp },
        .{ .name = "updated_at", .type = .timestamp },
    });

    try helper.addIndex("idx_users_name", &[_][]const u8{"name"}, true);
}

pub fn down_001(db_ptr: *anyopaque) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);
    try helper.dropTable("users");
}

const migrations_list = [_]orm.migrations.Migration{
    .{ .version = 1, .name = "create_users", .up = &up_001, .down = &down_001 },
};

var runner = orm.migrations.MigrationRunner(orm.sqlite.SQLite).init(&db, allocator);
try runner.migrate(&migrations_list);
```

### 9. Relationships
The ORM facilitates building associations using explicit queries.

```zig
// One-to-One
const profile = try repo.findBy(Profiles, .{ .user_id = user.id });

// One-to-Many
const posts = try repo.findAllBy(Posts, .{ .user_id = user.id });

// Eager Loading (Preload)
const user_ids = [_]i64{ 1, 2, 3 };
var q = try orm.from(Posts, allocator);
defer q.deinit();
_ = try q.whereIn("user_id", &user_ids);
const all_posts = try repo.all(q);
```

### 10. CLI Tools
A standalone CLI is provided for managing migrations without manual boilerplate.

```bash
# General help
zig build run -- help

# Generate a new timestamped migration
zig build run -- generate:migration create_users

# Run all pending migrations
zig build run -- migrate

# Rollback the last migration
zig build run -- rollback
```

> The CLI automatically manages your `migrations/migrations.zig` registry file, keeping it in sync as you add or remove migration files.

### 11. SQL Logging
You can hook into the execution pipeline to log generated SQL and timing information.

```zig
fn myLogger(ctx: orm.logging.LogContext) void {
    std.debug.print("Query: {s} (took {d}ns)\n", .{ctx.sql, ctx.duration_ns});
}

// ... in your setup ...
repo.setLogger(myLogger);
```

### 12. Optimistic Locking
To prevent concurrent updates from overwriting each other, add a `version: i64` field to your model. The ORM will automatically check and increment this version.

```zig
const Product = struct {
    id: i64,
    // ...
    version: i64, // Enables optimistic locking
};

// ...

// If the record was modified by another request since you fetched it:
repo.updateModel(Products, &product) catch |err| {
    if (err == orm.errors.OptimisticLockError.StaleObject) {
         // Handle conflict
    }
};
```

## Design Principles

*   **Driver-agnostic core**: Separation between Builder/Schema and Adapter.
*   **No Runtime Reflection**: Leveraging Zig's comptime for safety and performance.
*   **Think “typed SQL builder + mapper”**: Explicit over magic.
