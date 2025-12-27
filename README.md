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
_ = try q.where(.{ .active = true });
const users = try repo.all(q);

// Update (Auto-refreshes updated_at)
var u = try Users.update(allocator);
defer u.deinit();
_ = try u.set(.{ .active = false });
_ = try u.where(.{ .name = "Alice" });
try repo.update(u);
```

### 5. Relationships

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

### 6. Migrations

```zig
pub fn up_001(db_ptr: *anyopaque) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    try db.exec("CREATE TABLE users (id BIGINT PRIMARY KEY, name TEXT, created_at INTEGER, updated_at INTEGER)");
}

const migrations_list = [_]orm.migrations.Migration{
    .{ .version = 1, .name = "create_users", .up = &up_001, .down = &down_001 },
};

var runner = orm.migrations.MigrationRunner(orm.sqlite.SQLite).init(&db, allocator);
try runner.migrate(&migrations_list);
```

## Design Principles

*   **Driver-agnostic core**: Separation between Builder/Schema and Adapter.
*   **No Runtime Reflection**: Leveraging Zig's comptime for safety and performance.
*   **Think “typed SQL builder + mapper”**: Explicit over magic.
