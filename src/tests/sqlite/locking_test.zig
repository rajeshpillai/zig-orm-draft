const std = @import("std");
const orm = @import("zig-orm");
const testing = std.testing;

const Product = struct {
    id: i64,
    name: []const u8,
    version: i64,
};

const Products = orm.Table(Product, "products");

test "optimistic locking - increments version on update" {
    var db = try orm.sqlite.SQLite.init(":memory:");
    defer db.deinit();

    try db.exec("CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, version INTEGER)");

    const Repo = orm.Repo(orm.sqlite.SQLite);
    var repo = try Repo.init(testing.allocator, ":memory:");
    // Setup table through repo adapter
    try repo.adapter.exec("CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, version INTEGER)");
    defer repo.deinit();

    // Insert
    var p = Product{ .id = 1, .name = "Widget", .version = 1 };
    const sql = "INSERT INTO products (id, name, version) VALUES (1, 'Widget', 1)";
    try repo.adapter.exec(sql);

    // Update
    p.name = "Widget V2";
    try repo.updateModel(Products, &p);

    try testing.expectEqual(@as(i64, 2), p.version);

    // Verify in DB
    var stmt = try repo.adapter.prepare("SELECT version FROM products WHERE id = 1");
    defer stmt.deinit();
    _ = try stmt.step();
    const db_ver = orm.sqlite.SQLite.column_int(&stmt, 0);
    try testing.expectEqual(@as(i64, 2), db_ver);
}

test "optimistic locking - detects stale object" {
    const Repo = orm.Repo(orm.sqlite.SQLite);
    var repo = try Repo.init(testing.allocator, ":memory:");
    try repo.adapter.exec("CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, version INTEGER)");
    defer repo.deinit();

    // Insert initial record (Version 1)
    try repo.adapter.exec("INSERT INTO products (id, name, version) VALUES (1, 'Widget', 1)");

    var p = Product{ .id = 1, .name = "Widget", .version = 1 };

    // Simulate concurrent update: Someone else updates row to Version 2
    try repo.adapter.exec("UPDATE products SET version = 2 WHERE id = 1");

    // Now try to update p (which still thinks version is 1)
    p.name = "My Update";
    const result = repo.updateModel(Products, &p);

    try testing.expectError(orm.errors.OptimisticLockError.StaleObject, result);
}
