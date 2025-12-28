# Schema Constraints Guide

Zig ORM provides strong support for database-level constraints, allowing you to declare constraints in your schema and map database violations to typed Zig errors.

## Declaring Constraints

Constraints are defined in a `const constraints` declaration within your model struct.

### Unique Constraints

Ensure one or more fields are unique across the table.

```zig
const User = struct {
    id: i32,
    email: []const u8,
    username: []const u8,

    pub const constraints = .{
        // Single field unique constraint
        .unique = .{
            .fields = &[_][]const u8{ "email" },
            .name = "unique_email", // Optional custom name
        },
        // Composite unique constraint
        .unique_username = .{
            .fields = &[_][]const u8{ "username", "email" },
        },
    };
};
```

### Check Constraints

Enforce arbitrary SQL conditions on your data.

```zig
const Product = struct {
    id: i32,
    price: f64,
    stock: i32,

    pub const constraints = .{
        .check_price = .{
            .field = "price",
            .condition = "price > 0",
        },
        .check_stock = .{
            .field = "stock",
            .condition = "stock >= 0",
        },
    };
};
```

### Foreign Key Constraints

Enforce referential integrity between tables.

```zig
const Post = struct {
    id: i32,
    user_id: i32,

    pub const constraints = .{
        .fk_user = .{
            .field = "user_id",
            .references_table = "users",
            .references_field = "id",
            .on_delete = .cascade,
        },
    };
};
```

## Handling Constraint Violations

Zig ORM automatically maps database constraint violations to typed members of the `ValidationError` set.

```zig
const user = User{ ... };

repo.insert(&user) catch |err| switch (err) {
    error.UniqueViolation => {
        // Handle duplicate entry
        std.log.err("Email already exists!", .{});
    },
    error.CheckViolation => {
        // Handle check constraint failure
        std.log.err("Invalid data format!", .{});
    },
    error.ForeignKeyViolation => {
        // Handle invalid reference
        std.log.err("Referenced record not found!", .{});
    },
    else => return err,
};
```

## Pre-Flight Validation

For some constraints (like `Unique` and `Check` if implemented in logic), the ORM can perform pre-flight validation before hitting the database, saving a round-trip and providing faster feedback.

```zig
// The ORM automatically checks known constraints before insertion
try repo.insert(&user); 
```
