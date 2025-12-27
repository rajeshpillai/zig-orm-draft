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

### 3. Insert and Query

```zig
// Insert
var changeset = try Users.insert(allocator);
defer changeset.deinit();
try changeset.add(.{ .id = 1, .name = "Alice", .active = true });

try repo.insert(changeset);

// Query
const q = orm.from(Users); 
// Future: .where(.{ .active = true })

const users = try repo.all(q);
defer allocator.free(users);
defer {
    for (users) |u| allocator.free(u.name);
}

for (users) |user| {
    std.debug.print("User: {s}\n", .{user.name});
}
```

## Design Principles

*   **Driver-agnostic core**: Separation between Builder/Schema and Adapter.
*   **Think “typed SQL builder + mapper”**: Not a full object graph manager.
