const std = @import("std");
const orm = @import("zig-orm");

const CONN_STR = "postgresql://postgres:root123@localhost:5432/mydb";

test "pg validation integration - insert with valid data" {
    const User = struct {
        id: i64,
        name: []const u8,
        email: []const u8,
        age: i32,
    };

    const Users = orm.Table(User, "users_val");
    const Repo = orm.Repo(orm.postgres.PostgreSQL);

    var repo = try Repo.init(std.testing.allocator, CONN_STR);
    defer repo.deinit();

    // Create table
    try repo.adapter.exec("DROP TABLE IF EXISTS users_val");
    try repo.adapter.exec(
        \\CREATE TABLE users_val (
        \\    id BIGINT PRIMARY KEY,
        \\    name TEXT NOT NULL,
        \\    email TEXT NOT NULL,
        \\    age INTEGER NOT NULL
        \\)
    );

    // Valid data should succeed
    {
        var changeset = try Users.insert(std.testing.allocator);
        defer changeset.deinit();
        try changeset.add(.{
            .id = 1,
            .name = "Alice",
            .email = "alice@example.com",
            .age = 25,
        });
        try repo.insert(changeset);
    }

    // Verify insertion
    var q = try orm.from(Users, std.testing.allocator);
    defer q.deinit();
    const users = try repo.all(q);
    defer std.testing.allocator.free(users);
    defer for (users) |u| {
        std.testing.allocator.free(u.name);
        std.testing.allocator.free(u.email);
    };

    try std.testing.expectEqual(@as(usize, 1), users.len);
    try std.testing.expectEqualStrings("Alice", users[0].name);
}

test "pg validation integration - manual validation" {
    // Demonstrate manual validation before insert
    const email = "user@example.com";
    const name = "John Doe";
    const age: i32 = 25;

    // Validate email format
    try orm.validation.email(email);

    // Validate name length
    try orm.validation.lengthRange(name, 2, 100);

    // Validate age range
    try orm.validation.range(age, 18, 120);

    // All validations passed
}

test "pg validation - error cases" {
    // Email validation
    try std.testing.expectError(
        error.InvalidEmail,
        orm.validation.email("invalid-email"),
    );

    // Length validation
    try std.testing.expectError(
        error.TooShort,
        orm.validation.minLength("ab", 3),
    );

    try std.testing.expectError(
        error.TooLong,
        orm.validation.maxLength("hello world", 5),
    );

    // Range validation
    try std.testing.expectError(
        error.OutOfRange,
        orm.validation.range(17, 18, 120),
    );

    // Required validation
    try std.testing.expectError(
        error.Required,
        orm.validation.required(null),
    );
}

test "pg automatic validation on insert" {
    const Product = struct {
        id: i64,
        name: []const u8,
        price: i64,

        pub const rules = .{
            .name = .{ .min_len = 3 },
            .price = .{ .min = 1 },
        };
    };

    const Products = orm.Table(Product, "products_val");
    const Repo = orm.Repo(orm.postgres.PostgreSQL);

    const allocator = std.testing.allocator;
    var repo = try Repo.init(allocator, CONN_STR);
    defer repo.deinit();

    try repo.adapter.exec("DROP TABLE IF EXISTS products_val");
    try repo.adapter.exec("CREATE TABLE products_val (id BIGINT PRIMARY KEY, name TEXT NOT NULL, price INTEGER NOT NULL)");

    // Invalid data (name too short)
    {
        var insert = try Products.insert(allocator);
        defer insert.deinit();
        try insert.add(.{ .id = 1, .name = "a", .price = 10 });

        try std.testing.expectError(error.TooShort, repo.insert(&insert));
    }

    // Invalid data (price too low)
    {
        var insert = try Products.insert(allocator);
        defer insert.deinit();
        try insert.add(.{ .id = 2, .name = "Apple", .price = 0 });

        try std.testing.expectError(error.OutOfRange, repo.insert(&insert));
    }

    // Valid data
    {
        var insert = try Products.insert(allocator);
        defer insert.deinit();
        try insert.add(.{ .id = 3, .name = "Apple", .price = 100 });
        try repo.insert(&insert);
    }
}
