const std = @import("std");
const orm = @import("zig-orm");
const testing = std.testing;

const Product = struct {
    id: i64,
    name: []const u8,
    version: i64,
};

const Products = orm.Table(Product, "products_lock");

// Default local connection string
const CONN_STR = "postgresql://postgres:root123@localhost:5432/mydb";

test "postgres optimistic locking - increments version on update" {
    var db = try orm.postgres.PostgreSQL.init(CONN_STR);
    defer db.deinit();

    // Setup table
    try db.exec("DROP TABLE IF EXISTS products_lock");
    try db.exec("CREATE TABLE products_lock (id SERIAL PRIMARY KEY, name TEXT, version INTEGER)");

    const Repo = orm.Repo(orm.postgres.PostgreSQL);
    var repo = try Repo.init(testing.allocator, CONN_STR);
    defer repo.deinit();

    // Insert
    var p = Product{ .id = 1, .name = "Widget", .version = 1 };
    try db.exec("INSERT INTO products_lock (id, name, version) VALUES (1, 'Widget', 1)");

    // Update
    p.name = "Widget V2";
    try repo.updateModel(Products, &p);

    try testing.expectEqual(@as(i64, 2), p.version);

    // Verify in DB
    var stmt = try repo.adapter.prepare("SELECT version FROM products WHERE id = 1");
    defer stmt.deinit();
    _ = try stmt.step();
    const db_ver = orm.postgres.PostgreSQL.column_int(&stmt, 0);
    try testing.expectEqual(@as(i64, 2), db_ver);
}

test "postgres optimistic locking - detects stale object" {
    var db = try orm.postgres.PostgreSQL.init(CONN_STR);
    defer db.deinit();

    try db.exec("DROP TABLE IF EXISTS products_lock");
    try db.exec("CREATE TABLE products_lock (id SERIAL PRIMARY KEY, name TEXT, version INTEGER)");

    const Repo = orm.Repo(orm.postgres.PostgreSQL);
    var repo = try Repo.init(testing.allocator, CONN_STR);
    defer repo.deinit();

    // Insert initial record (Version 1)
    try db.exec("INSERT INTO products_lock (id, name, version) VALUES (1, 'Widget', 1)");

    var p = Product{ .id = 1, .name = "Widget", .version = 1 };

    // Simulate concurrent update: Someone else updates row to Version 2
    try db.exec("UPDATE products_lock SET version = 2 WHERE id = 1");

    // Now try to update p (which still thinks version is 1)
    p.name = "My Update";
    const result = repo.updateModel(Products, &p);

    try testing.expectError(orm.errors.OptimisticLockError.StaleObject, result);
}
