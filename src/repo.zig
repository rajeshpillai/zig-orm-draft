const std = @import("std");
const query = @import("builder/query.zig");

pub fn Repo(comptime Adapter: type) type {
    return struct {
        const Self = @This();

        adapter: Adapter,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, connection_string: [:0]const u8) !Self {
            const adapter = try Adapter.init(connection_string);
            return Self{
                .adapter = adapter,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.adapter.deinit();
        }

        pub fn begin(self: *Self) !void {
            try self.adapter.exec("BEGIN");
        }

        pub fn commit(self: *Self) !void {
            try self.adapter.exec("COMMIT");
        }

        pub fn rollback(self: *Self) !void {
            try self.adapter.exec("ROLLBACK");
        }

        pub fn insert(self: *Self, q: anytype) !void {
            if (q.items.items.len == 0) return;

            const sql = try q.toStatementSql();
            defer self.allocator.free(sql);

            var stmt = try self.adapter.prepare(sql);
            defer stmt.deinit();

            const Cols = @TypeOf(q).Table.columns;

            for (q.items.items) |item| {
                try stmt.reset();

                inline for (Cols, 0..) |col, i| {
                    const val = @field(item, col.name);
                    switch (col.type) {
                        .Integer => try stmt.bind_int(i, @intCast(val)),
                        .Text => try stmt.bind_text(i, val),
                        .Boolean => try stmt.bind_int(i, if (val) 1 else 0),
                        .Float, .Blob => return error.UnsupportedTypeBinding,
                    }
                }

                _ = try stmt.step();
            }
        }

        pub fn all(self: *Self, q: anytype) ![]@TypeOf(q).Table.model_type {
            const T = @TypeOf(q).Table.model_type;
            const sql = try q.toSql(self.allocator);
            defer self.allocator.free(sql);

            var stmt = try self.adapter.prepare(sql);
            defer stmt.deinit();

            // Bind WHERE clause parameters
            // q.params is ArrayList(Value) where Value = union(enum) { Integer: i64, Text: []const u8, Boolean: bool }

            for (q.params.items, 0..) |param, i| {
                switch (param) {
                    .Integer => |val| try stmt.bind_int(i, val),
                    .Text => |val| try stmt.bind_text(i, val),
                    .Boolean => |val| try stmt.bind_int(i, if (val) 1 else 0),
                    .Float, .Blob => return error.UnsupportedTypeBinding,
                }
            }

            var bind_idx = q.params.items.len;
            if (q.limit_val) |lim| {
                try stmt.bind_int(bind_idx, @intCast(lim));
                bind_idx += 1;
            }
            if (q.offset_val) |off| {
                try stmt.bind_int(bind_idx, @intCast(off));
                bind_idx += 1;
            }

            var results = try std.ArrayList(T).initCapacity(self.allocator, 0);

            errdefer results.deinit(self.allocator);

            while (try stmt.step()) {
                var item: T = undefined;

                inline for (@TypeOf(q).Table.columns, 0..) |col, i| {
                    switch (col.type) {
                        .Integer => {
                            const val = Adapter.column_int(&stmt, i);
                            @field(item, col.name) = @intCast(val);
                        },
                        .Text => {
                            const val_opt = Adapter.column_text(&stmt, i);
                            if (val_opt) |val| {
                                @field(item, col.name) = try self.allocator.dupe(u8, val);
                            } else {
                                @field(item, col.name) = ""; // Empty string for null?
                            }
                        },
                        .Boolean => {
                            const val = Adapter.column_int(&stmt, i);
                            @field(item, col.name) = (val != 0);
                        },
                        // Missing: Float, Blob
                        else => {
                            // Ignore others for now or verify in schema matches
                            // compilation error for unsupported?
                            return error.UnsupportedTypeMapping;
                        },
                    }
                }
                try results.append(self.allocator, item);
            }
            return results.toOwnedSlice(self.allocator);
        }
    };
}
