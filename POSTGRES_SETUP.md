# PostgreSQL Adapter Setup

## Status
✅ PostgreSQL adapter implemented
⏸️ Awaiting PostgreSQL installation for testing

## Installation Requirements

### Windows
1. Download PostgreSQL from https://www.postgresql.org/download/windows/
2. Install PostgreSQL (default port 5432)
3. Add PostgreSQL bin directory to PATH:
   ```
   D:\Program Files\PostgreSQL\18\bin
   D:\Program Files\PostgreSQL\18\lib
   ```
   *(Note: The `bin/` directory in the repository root also contains necessary DLLs for runtime if they are not in your system PATH).*
4. Set environment variables (optional):
   ```
   PGHOST=localhost
   PGPORT=5432
   PGUSER=postgres
   PGPASSWORD=your_password
   ```

### Build Configuration
The build.zig will need to be updated to link against libpq once PostgreSQL is installed:

```zig
// Add to build.zig after mod setup
if (target.result.os.tag == .windows) {
    mod.addIncludePath(.{ .cwd_relative = "D:/Program Files/PostgreSQL/18/include" });
    mod.addLibraryPath(.{ .cwd_relative = "D:/Program Files/PostgreSQL/18/lib" });
    mod.linkSystemLibrary("libpq", .{});
}
```

## Connection String Format
```
postgresql://username:password@host:port/database
```

Example:
```
postgresql://postgres:password@localhost:5432/mydb
```

## Next Steps
1. Install PostgreSQL on Windows
2. Update build.zig with libpq linking
3. Create test database
4. Run PostgreSQL integration tests
5. Test connection pooling with PostgreSQL

## Usage Example
```zig
const orm = @import("zig-orm");

// PostgreSQL connection
var pool = try orm.ConnectionPool(orm.postgres.PostgreSQL).init(allocator, .{
    .max_connections = 10,
    .min_connections = 2,
    .connection_string = "postgresql://postgres:password@localhost:5432/mydb",
});
defer pool.deinit();

var repo = orm.Repo(orm.postgres.PostgreSQL).initWithPool(&pool);

// Use repo same as with SQLite
const users = try repo.all(user_query);
```
