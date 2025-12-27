const std = @import("std");
const orm = @import("zig-orm");

pub fn main() !void {
    std.debug.print("Testing PostgreSQL connection...\n", .{});

    const Repo = orm.Repo(orm.postgres.PostgreSQL);

    var repo = Repo.init(
        std.heap.page_allocator,
        "postgresql://postgres:root123@localhost:5432/postgres",
    ) catch |err| {
        std.debug.print("Connection failed with error: {}\n", .{err});
        std.debug.print("\nTroubleshooting:\n", .{});
        std.debug.print("1. Is PostgreSQL running? Check with: pg_isready\n", .{});
        std.debug.print("2. Can you connect with psql? Try: psql -U postgres -d postgres\n", .{});
        std.debug.print("3. Is libpq.dll in PATH? Check: D:\\Program Files\\PostgreSQL\\18\\bin\n", .{});
        return err;
    };
    defer repo.deinit();

    std.debug.print("✅ Connection successful!\n", .{});

    // Test basic query
    repo.adapter.exec("SELECT 1") catch |err| {
        std.debug.print("Query failed: {}\n", .{err});
        return err;
    };

    std.debug.print("✅ Query successful!\n", .{});
}
