# Zig ORM CLI Tutorial: Building a Blog Schema

This tutorial demonstrates how to use the Zig ORM CLI tools to create a database schema for a simple Blog application.

We will create the following entities:
- **User**: The author of posts and comments.
- **Post**: A blog entry belonging to a User.
- **Comment**: A comment on a Post, written by a User.
- **Tag**: A label for Posts (Many-to-Many).

## Prerequisites

Ensure you have built the project and the CLI is available via `zig build run`.

```bash
zig build
```

## Step 1: Generate Migrations

We will create separate migrations for each logical unit.

### 1.1 Create Users Table

Run the generator:
```bash
zig build run -- generate:migration create_users
```

Open the generated file in `migrations/` and define the table:

```zig
pub fn up(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);

    try helper.createTable("users", &.{
        .{ .name = "id", .type = .integer, .primary_key = true },
        .{ .name = "name", .type = .text, .nullable = false },
        .{ .name = "email", .type = .text, .nullable = false },
        .{ .name = "created_at", .type = .integer }, // Timestamp
        .{ .name = "updated_at", .type = .integer },
    });
    
    // Add unique index on email
    try helper.addIndex("users", "idx_users_email", &.{ "email" }, true);
}

pub fn down(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);
    try helper.dropTable("users");
}
```

### 1.2 Create Posts Table

Run:
```bash
zig build run -- generate:migration create_posts
```

Edit the migration:

```zig
pub fn up(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);

    try helper.createTable("posts", &.{
        .{ .name = "id", .type = .integer, .primary_key = true },
        .{ .name = "user_id", .type = .integer, .nullable = false }, // FK
        .{ .name = "title", .type = .text, .nullable = false },
        .{ .name = "body", .type = .text },
        .{ .name = "created_at", .type = .integer },
        .{ .name = "updated_at", .type = .integer },
    });
    
    try helper.addIndex("posts", "idx_posts_user_id", &.{ "user_id" }, false);
}

pub fn down(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);
    try helper.dropTable("posts");
}
```

### 1.3 Create Comments Table

Run:
```bash
zig build run -- generate:migration create_comments
```

Edit the migration:

```zig
pub fn up(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);

    try helper.createTable("comments", &.{
        .{ .name = "id", .type = .integer, .primary_key = true },
        .{ .name = "post_id", .type = .integer, .nullable = false },
        .{ .name = "user_id", .type = .integer, .nullable = false },
        .{ .name = "body", .type = .text, .nullable = false },
        .{ .name = "created_at", .type = .integer },
    });
    
    try helper.addIndex("comments", "idx_comments_post_id", &.{ "post_id" }, false);
}

pub fn down(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);
    try helper.dropTable("comments");
}
```

### 1.4 Create Tags and Join Table

Run:
```bash
zig build run -- generate:migration create_tags
```

Edit the migration:

```zig
pub fn up(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);

    // Tags Table
    try helper.createTable("tags", &.{
        .{ .name = "id", .type = .integer, .primary_key = true },
        .{ .name = "name", .type = .text, .nullable = false },
    });
    try helper.addIndex("tags", "idx_tags_name", &.{ "name" }, true);

    // Join Table: posts_tags
    try helper.createTable("posts_tags", &.{
        .{ .name = "post_id", .type = .integer, .nullable = false },
        .{ .name = "tag_id", .type = .integer, .nullable = false },
    });
    
    // Composite Primary Key (via unique index for now, or raw SQL if preferred)
    try helper.addIndex("posts_tags", "idx_posts_tags_unique", &.{ "post_id", "tag_id" }, true);
}

pub fn down(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
    const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
    var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);
    try helper.dropTable("posts_tags");
    try helper.dropTable("tags");
}
```

## Step 2: Run Migrations

Apply the changes to your `development.db`:

```bash
zig build run -- migrate
```

You should see output confirming each migration was applied.

## Step 3: Generate Models

Now utilize the inspection tool to generate Zig structs for your schema.

```bash
zig build run -- generate:model users
zig build run -- generate:model posts
zig build run -- generate:model comments
zig build run -- generate:model tags
```

### Example Model Output (`users`)

The CLI will output code similar to this:

```zig
// Generated Model for 'users':

const orm = @import("zig-orm");

pub const Users = struct {
    const Self = @This();
    pub const table_name = "users";

    id: ?i64,
    name: []const u8,
    email: []const u8,
    created_at: ?i64,
    updated_at: ?i64,
};
```

Copy this output into your project (e.g., `src/models/user.zig`).

## Step 4: Using the Models

In your application code (`src/main.zig`), you can now use these models with the Repo.

```zig
const User = @import("models/user.zig").Users;
const Post = @import("models/post.zig").Posts;

// ... init repo ...

// Create a user
var changeset = try orm.Table(User, "users").insert(allocator);
try changeset.add(.{ .name = "Alice", .email = "alice@example.com" });
try repo.insert(changeset);

// Query
const users = try repo.findAllBy(User, .{ .name = "Alice" });
```
