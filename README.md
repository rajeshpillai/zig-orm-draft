# Zig ORM

**Status**: Experimental / Pre-alpha

A typed, compile-time schema ORM for Zig, inspired by Elixir Ecto. Supports SQLite (embedded).

## Features

*   **No runtime reflection**: Schema defined at compile-time.
*   **Repo Pattern**: Ecto-style `Repo` for database interactions.
*   **Explicit SQL**: Typed query builder (`from`, `where`, `insert`).
*   **Secure**: Automatic parameter binding for `insert` and queries.
*   **Embedded SQLite**: Zero-dependency build (bundles `sqlite3.c`).

## Installation

1.  Add `zig-orm` to your `build.zig` (assuming you have it locally or via package manager):

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
};
const Users = orm.Table(User, "users");
```

### 2. Initialize Repo

```zig
const Repo = orm.Repo(orm.sqlite.SQLite);

var repo = try Repo.init(allocator, "path/to/db.sqlite");
defer repo.deinit();
```

### 3. CRUD Operations

```zig
// Insert
var changeset = try Users.insert(allocator);
defer changeset.deinit();
try changeset.add(.{ .id = 1, .name = "Alice", .active = true });
try repo.insert(changeset);

// Select with filters
var q = try orm.from(Users, allocator);
defer q.deinit();
_ = try q.where(.{ .active = true });
_ = q.limit(10).offset(0);

const users = try repo.all(q);
defer allocator.free(users);
defer {
    for (users) |u| allocator.free(u.name);
}

// Update
var u = try Users.update(allocator);
defer u.deinit();
_ = try u.set(.{ .active = false });
_ = try u.where(.{ .name = "Alice" });
try repo.update(u);

// Delete
var d = try Users.delete(allocator);
defer d.deinit();
_ = try d.where(.{ .active = false });
try repo.delete(d);

// Transactions
try repo.begin();
errdefer repo.rollback() catch {};
// ... operations ...
try repo.commit();
```

### 4. Relationships

```zig
// One-to-One: Load profile for user
const profile = try repo.findBy(Profiles, .{ .user_id = user.id });

// One-to-Many: Load all posts for user
const posts = try repo.findAllBy(Posts, .{ .user_id = user.id });
defer allocator.free(posts);

// N+1 Elimination: Batch load posts for multiple users
const user_ids = [_]i64{ 1, 2, 3 };
var q = try orm.from(Posts, allocator);
defer q.deinit();
_ = try q.whereIn("user_id", &user_ids);
const all_posts = try repo.all(q);
```

## Design Principles

*   **Driver-agnostic core**: Separation between Builder/Schema and Adapter.
*   **Think “typed SQL builder + mapper”**: Not a full object graph manager.
