const std = @import("std");
const orm = @import("zig-orm");

const User = struct {
    id: i64,
    name: []const u8,
    hook_called: bool = false,

    pub fn beforeInsert(self: *User) !void {
        if (std.mem.eql(u8, self.name, "forbidden")) {
            return error.ForbiddenName;
        }
        self.hook_called = true;
    }

    pub fn afterInsert(self: *User) !void {
        // Just as proof it was called
        std.debug.print("User {s} was inserted!\n", .{self.name});
    }
};

test "model hooks - beforeInsert success" {
    const Repo = orm.Repo(orm.sqlite.SQLite);
    var repo = try Repo.init(std.testing.allocator, ":memory:");
    defer repo.deinit();

    try repo.adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, hook_called BOOLEAN)");

    const Users = orm.Table(User, "users");

    var changeset = try Users.insert(std.testing.allocator);
    defer changeset.deinit();

    try changeset.add(.{ .id = 1, .name = "Alice" });

    try repo.insert(changeset);

    try std.testing.expect(changeset.items.items[0].hook_called);
}

test "model hooks - beforeInsert failure" {
    const Repo = orm.Repo(orm.sqlite.SQLite);
    var repo = try Repo.init(std.testing.allocator, ":memory:");
    defer repo.deinit();

    try repo.adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, hook_called BOOLEAN)");

    const Users = orm.Table(User, "users");

    var changeset = try Users.insert(std.testing.allocator);
    defer changeset.deinit();

    try changeset.add(.{ .id = 1, .name = "forbidden" });

    const result = repo.insert(changeset);
    try std.testing.expectError(error.ForbiddenName, result);
}

test "model hooks - Update and Delete" {
    const Repo = orm.Repo(orm.sqlite.SQLite);
    var repo = try Repo.init(std.testing.allocator, ":memory:");
    defer repo.deinit();

    try repo.adapter.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, hook_called BOOLEAN)");

    const Users = orm.Table(User, "users");

    // 1. Insert
    var user = User{ .id = 1, .name = "Alice", .hook_called = false };
    var changeset = try Users.insert(std.testing.allocator);
    defer changeset.deinit();
    try changeset.add(user);
    try repo.insert(changeset);

    // 2. Update
    user.name = "Bob";
    try repo.updateModel(Users, &user);
    try std.testing.expectEqualStrings("Bob", user.name);

    // Verify in DB
    const found = try repo.findBy(Users, .{ .id = 1 });
    if (found) |f| {
        defer repo.allocator.free(f.name);
        try std.testing.expectEqualStrings("Bob", f.name);
    } else {
        try std.testing.expect(false);
    }

    // 3. Delete
    try repo.deleteModel(Users, &user);

    // Verify gone
    const found_after = try repo.findBy(Users, .{ .id = 1 });
    if (found_after) |f| {
        defer repo.allocator.free(f.name);
        try std.testing.expect(false);
    }
}
