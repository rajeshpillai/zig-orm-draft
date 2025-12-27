# Timestamp Implementation in Zig ORM

The Zig ORM provides automatic tracking of creation and modification times through `created_at` and `updated_at` fields. This document details how this is implemented and how to use it.

## Core Implementation

The core logic resides in [timestamps.zig](file:///d:/lab/zig/zig-orm/src/core/timestamps.zig).

### Platform-Independent `currentTimestamp()`

The `currentTimestamp()` function provides a stable way to get the current Unix timestamp in seconds across different operating systems:

- **Windows**: Uses `GetSystemTimeAsFileTime` from `kernel32` to get 100-nanosecond intervals since January 1, 1601, then converts it to Unix Epoch seconds.
- **POSIX (Linux/macOS)**: Uses `clock_gettime(CLOCK_REALTIME)` to get seconds since the Unix Epoch.

### Metadata Detection

The system uses Zig's metaprogramming capabilities to detect timestamp fields at compile-time:

- `hasTimestamps(T)`: Checks if a struct has either `created_at` or `updated_at`.
- `hasCreatedAt(T)`: Checks for the existence of the `created_at` field.
- `hasUpdatedAt(T)`: Checks for the existence of the `updated_at` field.

## Automatic Tracking

### During Insert

When using `Repo.insert()`, the ORM automatically checks for timestamp fields. If they exist and are set to `0`, they are initialized with the current timestamp.

Implementation in [repo.zig](file:///d:/lab/zig/zig-orm/src/repo.zig):
```zig
// Auto-set timestamps during insert
if (comptime timestamps.hasTimestamps(@TypeOf(item.*))) {
    timestamps.setCreatedAt(item);
    timestamps.setUpdatedAt(item);
}
```

### During Update

The `Update` query builder automatically appends `updated_at = ?` to the SQL statement if the field exists and hasn't been explicitly set in the `set()` call.

Implementation in [query.zig](file:///d:/lab/zig/zig-orm/src/builder/query.zig):
```zig
if (comptime timestamps.hasUpdatedAt(TableT.model_type)) {
    if (std.mem.indexOf(u8, self.set_exprs.items, "updated_at") == null) {
        // ... appends updated_at = ? and binds currentTimestamp()
    }
}
```

## Usage in Migrations

Migrations also leverage the stable `currentTimestamp()` to record when a migration was applied.

Implementation in [runner.zig](file:///d:/lab/zig/zig-orm/src/migrations/runner.zig):
```zig
pub fn recordMigration(self: *Self, migration: Migration) !void {
    // ...
    try stmt.bind_int(2, timestamps.currentTimestamp());
    _ = try stmt.step();
}
```

## How to use in Models

To enable automatic timestamp tracking, simply include `created_at` and/or `updated_at` fields of type `i64` in your model struct.

```zig
pub const User = struct {
    id: i64,
    username: []const u8,
    created_at: i64 = 0, // Automatically managed
    updated_at: i64 = 0, // Automatically managed
};
```

> [!NOTE]
> Initializing these fields to `0` allows the ORM to recognize they need to be set. If you provide a non-zero value, the ORM will respect your value and not override it during the initial insert.
