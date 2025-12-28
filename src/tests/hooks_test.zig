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
