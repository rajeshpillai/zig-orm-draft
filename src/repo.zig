const std = @import("std");
const builder = @import("builder/query.zig");
const timestamps = @import("core/timestamps.zig");
const validation = @import("validation/validator.zig");
const core_types = @import("core/types.zig");
const hooks = @import("core/hooks.zig");

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

            const Q = if (@typeInfo(@TypeOf(q)) == .pointer) @typeInfo(@TypeOf(q)).pointer.child else @TypeOf(q);
            const Cols = Q.Table.columns;

            for (q.items.items) |*item| {
                // Call beforeInsert hook
                try hooks.callHook(item, "beforeInsert");

                // Auto-validate
                try validation.validate(item);

                // Auto-set timestamps
                if (comptime timestamps.hasTimestamps(@TypeOf(item.*))) {
                    timestamps.setCreatedAt(item);
                    timestamps.setUpdatedAt(item);
                }

                try stmt.reset();

                inline for (Cols, 0..) |col, i| {
                    const val = @field(item.*, col.name);
                    switch (col.type) {
                        .Integer => try stmt.bind_int(i, @intCast(val)),
                        .Text => try stmt.bind_text(i, val),
                        .Boolean => try stmt.bind_int(i, if (val) 1 else 0),
                        .Float, .Blob => return error.UnsupportedTypeBinding,
                    }
                }

                _ = try stmt.step();

                // Call afterInsert hook
                try hooks.callHook(item, "afterInsert");
            }
        }

        pub fn update(self: *Self, q: anytype) !void {
            var mutable_q = q;
            const sql = try mutable_q.toSql();
            defer self.allocator.free(sql);

            var stmt = try self.adapter.prepare(sql);
            defer stmt.deinit();

            // Bind params
            for (q.params.items, 0..) |param, i| {
                switch (param) {
                    .Integer => |val| try stmt.bind_int(i, val),
                    .Text => |val| try stmt.bind_text(i, val),
                    .Boolean => |val| try stmt.bind_int(i, if (val) 1 else 0),
                    .Float, .Blob => return error.UnsupportedTypeBinding,
                }
            }
            _ = try stmt.step();
        }

        pub fn delete(self: *Self, q: anytype) !void {
            var mutable_q = q;
            const sql = try mutable_q.toSql();
            defer self.allocator.free(sql);

            var stmt = try self.adapter.prepare(sql);
            defer stmt.deinit();

            // Bind params
            for (q.params.items, 0..) |param, i| {
                switch (param) {
                    .Integer => |val| try stmt.bind_int(i, val),
                    .Text => |val| try stmt.bind_text(i, val),
                    .Boolean => |val| try stmt.bind_int(i, if (val) 1 else 0),
                    .Float, .Blob => return error.UnsupportedTypeBinding,
                }
            }
            _ = try stmt.step();
        }

        /// Find a single record by condition, returns null if not found
        pub fn findBy(self: *Self, comptime TableT: type, condition: anytype) !?TableT.model_type {
            var q = try builder.from(TableT, self.allocator);
            defer q.deinit();
            _ = try q.where(condition);
            _ = q.limit(1);

            const results = try self.all(q);
            defer self.allocator.free(results);

            if (results.len == 0) return null;

            // Return first result (need to dupe strings to avoid use-after-free)
            return results[0];
        }

        /// Find all records matching condition
        pub fn findAllBy(self: *Self, comptime TableT: type, condition: anytype) ![]TableT.model_type {
            var q = try builder.from(TableT, self.allocator);
            defer q.deinit();
            _ = try q.where(condition);

            return try self.all(q);
        }

        pub fn all(self: *Self, q: anytype) ![]@TypeOf(q).Table.model_type {
            const Q = if (@typeInfo(@TypeOf(q)) == .pointer) @typeInfo(@TypeOf(q)).pointer.child else @TypeOf(q);
            const T = Q.Table.model_type;
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

        /// Execute a raw SQL query and map results to ResultT
        pub fn query(self: *Self, comptime ResultT: type, sql: [:0]const u8, params: []const core_types.Value) ![]ResultT {
            var stmt = try self.adapter.prepare(sql);
            defer stmt.deinit();

            // Bind params
            for (params, 0..) |param, i| {
                switch (param) {
                    .Integer => |val| try stmt.bind_int(i, val),
                    .Text => |val| try stmt.bind_text(i, val),
                    .Boolean => |val| try stmt.bind_int(i, if (val) 1 else 0),
                    .Float, .Blob => return error.UnsupportedTypeBinding,
                }
            }

            var results = try std.ArrayList(ResultT).initCapacity(self.allocator, 0);
            errdefer results.deinit(self.allocator);

            while (try stmt.step()) {
                var item: ResultT = undefined;
                const info = @typeInfo(ResultT);

                if (info != .@"struct") @compileError("ResultT must be a struct");

                inline for (info.@"struct".fields, 0..) |field, i| {
                    const field_type = field.type;
                    if (field_type == i64 or field_type == i32) {
                        const val = Adapter.column_int(&stmt, i);
                        @field(item, field.name) = @intCast(val);
                    } else if (field_type == []const u8 or field_type == [:0]const u8) {
                        const val_opt = Adapter.column_text(&stmt, i);
                        if (val_opt) |val| {
                            @field(item, field.name) = try self.allocator.dupe(u8, val);
                        } else {
                            @field(item, field.name) = "";
                        }
                    } else if (field_type == bool) {
                        const val = Adapter.column_int(&stmt, i);
                        @field(item, field.name) = (val != 0);
                    } else {
                        return error.UnsupportedTypeMapping;
                    }
                }
                try results.append(self.allocator, item);
            }

            return try results.toOwnedSlice(self.allocator);
        }

        /// Execute a raw SQL statement (INSERT, UPDATE, DELETE, etc.)
        pub fn execute(self: *Self, sql: [:0]const u8, params: []const core_types.Value) !void {
            var stmt = try self.adapter.prepare(sql);
            defer stmt.deinit();

            // Bind params
            for (params, 0..) |param, i| {
                switch (param) {
                    .Integer => |val| try stmt.bind_int(i, val),
                    .Text => |val| try stmt.bind_text(i, val),
                    .Boolean => |val| try stmt.bind_int(i, if (val) 1 else 0),
                    .Float, .Blob => return error.UnsupportedTypeBinding,
                }
            }

            _ = try stmt.step();
        }
    };
}
