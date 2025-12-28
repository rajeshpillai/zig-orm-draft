const std = @import("std");
const builder = @import("builder/query.zig");
const timestamps = @import("core/timestamps.zig");
const validation = @import("validation/validator.zig");
const core_types = @import("core/types.zig");
const hooks = @import("core/hooks.zig");
const logging = @import("core/logging.zig");
const errors = @import("core/errors.zig");

pub fn Repo(comptime Adapter: type) type {
    return struct {
        const Self = @This();

        adapter: Adapter,
        allocator: std.mem.Allocator,
        log_fn: ?logging.LogFn = null,

        pub fn init(allocator: std.mem.Allocator, connection_string: [:0]const u8) !Self {
            const adapter = try Adapter.init(connection_string);
            return Self{
                .adapter = adapter,
                .allocator = allocator,
                .log_fn = null,
            };
        }

        pub fn initFromAdapter(allocator: std.mem.Allocator, adapter: Adapter) Self {
            return Self{
                .adapter = adapter,
                .allocator = allocator,
                .log_fn = null,
            };
        }

        pub fn setLogger(self: *Self, logger: logging.LogFn) void {
            self.log_fn = logger;
        }

        fn dispatchLog(self: *Self, sql: []const u8, duration_ns: u64) void {
            if (self.log_fn) |log| {
                log(.{
                    .sql = sql,
                    .duration_ns = duration_ns,
                });
            }
        }

        pub fn deinit(self: *Self) void {
            self.adapter.deinit();
        }

        /// Check if a model type has soft delete support (deleted_at field)
        fn hasSoftDelete(comptime T: type) bool {
            return @hasField(T, "deleted_at");
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

            var timer = std.time.Timer.start() catch unreachable;
            var stmt = try self.adapter.prepare(sql);
            defer {
                stmt.deinit();
                self.dispatchLog(sql, timer.read());
            }

            const Q = if (@typeInfo(@TypeOf(q)) == .pointer) @typeInfo(@TypeOf(q)).pointer.child else @TypeOf(q);
            const Cols = Q.Table.columns;

            for (q.items.items) |*item| {
                // Call beforeInsert hook
                try hooks.callHook(item, "beforeInsert");

                // Auto-validate
                try validation.validate(item);

                // Validate constraints (unique, check, etc.)
                const constraints_mod = @import("validation/constraints.zig");
                try constraints_mod.validateConstraints(@TypeOf(item.*), self, item);

                // Auto-set timestamps
                if (comptime timestamps.hasTimestamps(@TypeOf(item.*))) {
                    timestamps.setCreatedAt(item);
                    timestamps.setUpdatedAt(item);
                }

                try stmt.reset();

                inline for (Cols, 0..) |col, i| {
                    const val = @field(item.*, col.name);
                    const FieldType = @TypeOf(val);

                    // Handle enums
                    const type_info = @typeInfo(FieldType);
                    if (type_info == .@"enum") {
                        if (core_types.shouldStoreEnumAsText(FieldType)) {
                            const text = core_types.enumToText(FieldType, val);
                            try stmt.bind_text(i, text);
                        } else {
                            const int_val = core_types.enumToInt(FieldType, val);
                            try stmt.bind_int(i, int_val);
                        }
                    } else {
                        // Handle regular types
                        switch (col.type) {
                            .Integer => try stmt.bind_int(i, @intCast(val)),
                            .Text => try stmt.bind_text(i, val),
                            .Boolean => try stmt.bind_int(i, if (val) 1 else 0),
                            .Float, .Blob => return error.UnsupportedTypeBinding,
                        }
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

            var timer = std.time.Timer.start() catch unreachable;
            var stmt = try self.adapter.prepare(sql);
            defer {
                stmt.deinit();
                self.dispatchLog(sql, timer.read());
            }

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
            const Q = if (@typeInfo(@TypeOf(q)) == .pointer) @typeInfo(@TypeOf(q)).pointer.child else @TypeOf(q);
            const ModelType = Q.Table.model_type;

            // Check if model has soft delete support
            if (comptime hasSoftDelete(ModelType)) {
                // Soft delete: UPDATE table SET deleted_at = ? WHERE ...
                return try self.softDelete(q);
            } else {
                // Hard delete: DELETE FROM table WHERE ...
                return try self.forceDelete(q);
            }
        }

        /// Soft delete: sets deleted_at timestamp instead of removing record
        fn softDelete(self: *Self, q: anytype) !void {
            var mutable_q = q;
            const timestamp = timestamps.currentTimestamp();

            // Build UPDATE query manually since we need to set deleted_at
            const Q = if (@typeInfo(@TypeOf(q)) == .pointer) @typeInfo(@TypeOf(q)).pointer.child else @TypeOf(q);
            const table_name = Q.Table.table_name;

            // Build SQL: UPDATE table SET deleted_at = ? WHERE <conditions>
            var sql_list = try std.ArrayList(u8).initCapacity(self.allocator, 0);
            defer sql_list.deinit(self.allocator);

            try sql_list.appendSlice(self.allocator, "UPDATE ");
            try sql_list.appendSlice(self.allocator, table_name);
            try sql_list.appendSlice(self.allocator, " SET deleted_at = ?");

            if (mutable_q.where_exprs.items.len > 0) {
                try sql_list.appendSlice(self.allocator, " WHERE ");
                try sql_list.appendSlice(self.allocator, mutable_q.where_exprs.items);
            }

            const sql = try sql_list.toOwnedSliceSentinel(self.allocator, 0);
            defer self.allocator.free(sql);

            var timer = std.time.Timer.start() catch unreachable;
            var stmt = try self.adapter.prepare(sql);
            defer {
                stmt.deinit();
                self.dispatchLog(sql, timer.read());
            }

            // Bind timestamp first
            try stmt.bind_int(0, timestamp);

            // Bind WHERE params
            for (mutable_q.params.items, 0..) |param, i| {
                switch (param) {
                    .Integer => |val| try stmt.bind_int(i + 1, val),
                    .Text => |val| try stmt.bind_text(i + 1, val),
                    .Boolean => |val| try stmt.bind_int(i + 1, if (val) 1 else 0),
                    .Float, .Blob => return error.UnsupportedTypeBinding,
                }
            }
            _ = try stmt.step();
        }

        /// Force delete: permanently removes record from database
        pub fn forceDelete(self: *Self, q: anytype) !void {
            var mutable_q = q;
            const sql = try mutable_q.toSql();
            defer self.allocator.free(sql);

            var timer = std.time.Timer.start() catch unreachable;
            var stmt = try self.adapter.prepare(sql);
            defer {
                stmt.deinit();
                self.dispatchLog(sql, timer.read());
            }

            // Bind params
            for (mutable_q.params.items, 0..) |param, i| {
                switch (param) {
                    .Integer => |val| try stmt.bind_int(i, val),
                    .Text => |val| try stmt.bind_text(i, val),
                    .Boolean => |val| try stmt.bind_int(i, if (val) 1 else 0),
                    .Float, .Blob => return error.UnsupportedTypeBinding,
                }
            }
            _ = try stmt.step();
        }

        /// Restore a soft-deleted record by setting deleted_at to NULL
        pub fn restore(self: *Self, q: anytype) !void {
            const Q = if (@typeInfo(@TypeOf(q)) == .pointer) @typeInfo(@TypeOf(q)).pointer.child else @TypeOf(q);
            const ModelType = Q.Table.model_type;

            if (comptime !hasSoftDelete(ModelType)) {
                return error.SoftDeleteNotSupported;
            }

            var mutable_q = q;
            const table_name = Q.Table.table_name;

            // Build SQL: UPDATE table SET deleted_at = NULL WHERE <conditions>
            var sql_list = try std.ArrayList(u8).initCapacity(self.allocator, 0);
            defer sql_list.deinit(self.allocator);

            try sql_list.appendSlice(self.allocator, "UPDATE ");
            try sql_list.appendSlice(self.allocator, table_name);
            try sql_list.appendSlice(self.allocator, " SET deleted_at = NULL");

            if (mutable_q.where_exprs.items.len > 0) {
                try sql_list.appendSlice(self.allocator, " WHERE ");
                try sql_list.appendSlice(self.allocator, mutable_q.where_exprs.items);
            }

            const sql = try sql_list.toOwnedSliceSentinel(self.allocator, 0);
            defer self.allocator.free(sql);

            var timer = std.time.Timer.start() catch unreachable;
            var stmt = try self.adapter.prepare(sql);
            defer {
                stmt.deinit();
                self.dispatchLog(sql, timer.read());
            }

            // Bind WHERE params
            for (mutable_q.params.items, 0..) |param, i| {
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

            // Automatically filter soft-deleted records
            if (comptime hasSoftDelete(TableT.model_type) and !q.include_trashed) {
                _ = try q.whereNull("deleted_at");
            }

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

            // Automatically filter soft-deleted records
            if (comptime hasSoftDelete(TableT.model_type) and !q.include_trashed) {
                _ = try q.whereNull("deleted_at");
            }

            _ = try q.where(condition);

            return try self.all(q);
        }

        pub fn all(self: *Self, q: anytype) ![]@TypeOf(q).Table.model_type {
            const Q = if (@typeInfo(@TypeOf(q)) == .pointer) @typeInfo(@TypeOf(q)).pointer.child else @TypeOf(q);
            const T = Q.Table.model_type;
            const sql = try q.toSql(self.allocator);
            defer self.allocator.free(sql);

            var timer = std.time.Timer.start() catch unreachable;
            var stmt = try self.adapter.prepare(sql);
            defer {
                stmt.deinit();
                self.dispatchLog(sql, timer.read());
            }

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
                    const FieldType = @TypeOf(@field(item, col.name));
                    const field_type_info = @typeInfo(FieldType);

                    // Handle enums
                    if (field_type_info == .@"enum") {
                        if (core_types.shouldStoreEnumAsText(FieldType)) {
                            const text = Adapter.column_text(&stmt, i) orelse return error.NullEnumValue;
                            @field(item, col.name) = try core_types.textToEnum(FieldType, text);
                        } else {
                            const int_val = Adapter.column_int(&stmt, i);
                            @field(item, col.name) = try core_types.intToEnum(FieldType, @intCast(int_val));
                        }
                    } else if (field_type_info == .optional) {
                        const OptChild = @typeInfo(FieldType).optional.child;
                        const opt_child_info = @typeInfo(OptChild);

                        // Handle optional enums
                        if (opt_child_info == .@"enum") {
                            const text_or_null = Adapter.column_text(&stmt, i);
                            if (text_or_null) |text| {
                                if (core_types.shouldStoreEnumAsText(OptChild)) {
                                    @field(item, col.name) = try core_types.textToEnum(OptChild, text);
                                } else {
                                    const int_val = Adapter.column_int(&stmt, i);
                                    @field(item, col.name) = try core_types.intToEnum(OptChild, @intCast(int_val));
                                }
                            } else {
                                @field(item, col.name) = null;
                            }
                        } else {
                            // Handle regular optional types
                            switch (col.type) {
                                .Integer => {
                                    const text = Adapter.column_text(&stmt, i);
                                    if (text == null) {
                                        @field(item, col.name) = null;
                                    } else {
                                        @field(item, col.name) = Adapter.column_int(&stmt, i);
                                    }
                                },
                                .Text => {
                                    const val_opt = Adapter.column_text(&stmt, i);
                                    if (val_opt) |val| {
                                        @field(item, col.name) = try self.allocator.dupe(u8, val);
                                    } else {
                                        @field(item, col.name) = null;
                                    }
                                },
                                .Boolean => {
                                    const text = Adapter.column_text(&stmt, i);
                                    if (text == null) {
                                        @field(item, col.name) = null;
                                    } else {
                                        const val = Adapter.column_int(&stmt, i);
                                        @field(item, col.name) = (val != 0);
                                    }
                                },
                                .Float, .Blob => return error.UnsupportedTypeMapping,
                            }
                        }
                    } else {
                        // Handle regular non-optional types
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
                                    @field(item, col.name) = "";
                                }
                            },
                            .Boolean => {
                                const val = Adapter.column_int(&stmt, i);
                                @field(item, col.name) = (val != 0);
                            },
                            .Float, .Blob => return error.UnsupportedTypeMapping,
                        }
                    }
                }
                try results.append(self.allocator, item);
            }
            return results.toOwnedSlice(self.allocator);
        }

        pub fn count(self: *Self, q: anytype) !u64 {
            const QT = @TypeOf(q);
            if (comptime @typeInfo(QT) == .pointer) {
                _ = try q.select("COUNT(*)");
                return try self.scalar(u64, q);
            } else {
                var mutable_q = q;
                _ = try mutable_q.select("COUNT(*)");
                return try self.scalar(u64, &mutable_q);
            }
        }

        pub fn scalar(self: *Self, comptime T: type, q: anytype) !T {
            const sql = try q.toSql(self.allocator);
            defer self.allocator.free(sql);

            var timer = std.time.Timer.start() catch unreachable;
            var stmt = try self.adapter.prepare(sql);
            defer {
                stmt.deinit();
                self.dispatchLog(sql, timer.read());
            }

            // Bind WHERE clause parameters
            for (q.params.items, 0..) |param, i| {
                switch (param) {
                    .Integer => |val| try stmt.bind_int(i, val),
                    .Text => |val| try stmt.bind_text(i, val),
                    .Boolean => |val| try stmt.bind_int(i, if (val) 1 else 0),
                    .Float, .Blob => return error.UnsupportedTypeBinding,
                }
            }

            if (try stmt.step()) {
                if (T == i64 or T == u64 or T == i32 or T == usize) {
                    return @intCast(Adapter.column_int(&stmt, 0));
                } else if (T == []const u8) {
                    const val_opt = Adapter.column_text(&stmt, 0);
                    return try self.allocator.dupe(u8, val_opt orelse "");
                }
                return error.UnsupportedScalarType;
            }
            return error.NoResults;
        }

        /// Execute query and map results to custom struct
        pub fn allAs(self: *Self, comptime ResultT: type, q: anytype) ![]ResultT {
            const sql = try q.toSql(self.allocator);
            defer self.allocator.free(sql);

            var timer = std.time.Timer.start() catch unreachable;
            var stmt = try self.adapter.prepare(sql);
            defer {
                stmt.deinit();
                self.dispatchLog(sql, timer.read());
            }

            // Bind params
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
            return results.toOwnedSlice(self.allocator);
        }

        /// Execute a raw SQL query and map results to ResultT
        pub fn query(self: *Self, comptime ResultT: type, sql: [:0]const u8, params: []const core_types.Value) ![]ResultT {
            var timer = std.time.Timer.start() catch unreachable;
            var stmt = try self.adapter.prepare(sql);
            defer {
                stmt.deinit();
                self.dispatchLog(sql, timer.read());
            }

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
            var timer = std.time.Timer.start() catch unreachable;
            var stmt = try self.adapter.prepare(sql);
            defer {
                stmt.deinit();
                self.dispatchLog(sql, timer.read());
            }

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

        /// Update a specific model instance by ID, triggering hooks
        pub fn updateModel(self: *Self, comptime TableT: type, item: *TableT.model_type) !void {
            const has_version = comptime blk: {
                for (std.meta.fields(TableT.model_type)) |field| {
                    if (std.mem.eql(u8, field.name, "version")) {
                        break :blk true;
                    }
                }
                break :blk false;
            };

            // Call beforeUpdate hook
            try hooks.callHook(item, "beforeUpdate");

            // Auto-update timestamps
            if (comptime timestamps.hasUpdatedAt(TableT.model_type)) {
                timestamps.setUpdatedAt(item);
            }

            var sql = std.ArrayList(u8){};
            defer sql.deinit(self.allocator);

            try sql.appendSlice(self.allocator, "UPDATE ");
            try sql.appendSlice(self.allocator, TableT.table_name);
            try sql.appendSlice(self.allocator, " SET ");

            var first = true;
            inline for (TableT.columns) |col| {
                if (comptime std.mem.eql(u8, col.name, "id")) continue;
                if (comptime has_version and std.mem.eql(u8, col.name, "version")) {
                    if (!first) try sql.appendSlice(self.allocator, ", ");
                    try sql.appendSlice(self.allocator, "version = version + 1");
                    first = false;
                    continue;
                }

                if (!first) try sql.appendSlice(self.allocator, ", ");
                try sql.appendSlice(self.allocator, col.name);
                try sql.appendSlice(self.allocator, " = ?");
                first = false;
            }

            try sql.appendSlice(self.allocator, " WHERE id = ?");

            if (comptime has_version) {
                try sql.appendSlice(self.allocator, " AND version = ?");
            }

            const sql_z = try self.allocator.dupeZ(u8, sql.items);
            defer self.allocator.free(sql_z);

            var timer = std.time.Timer.start() catch unreachable;
            var stmt = try self.adapter.prepare(sql_z);
            defer {
                stmt.deinit();
                self.dispatchLog(sql_z, timer.read());
            }

            var bind_idx: usize = 0;
            inline for (TableT.columns) |col| {
                if (comptime std.mem.eql(u8, col.name, "id")) continue;
                if (comptime has_version and std.mem.eql(u8, col.name, "version")) continue;

                const val = @field(item.*, col.name);
                switch (col.type) {
                    .Integer => try stmt.bind_int(bind_idx, @intCast(val)),
                    .Text => try stmt.bind_text(bind_idx, val),
                    .Boolean => try stmt.bind_int(bind_idx, if (val) 1 else 0),
                    else => return error.UnsupportedTypeBinding,
                }
                bind_idx += 1;
            }

            // Bind ID
            try stmt.bind_int(bind_idx, @intCast(item.id));
            bind_idx += 1;

            if (comptime has_version) {
                // Bind current version for WHERE clause
                const current_ver = @field(item.*, "version");
                try stmt.bind_int(bind_idx, @intCast(current_ver));
            }

            _ = try stmt.step();

            if (comptime has_version) {
                if (self.adapter.changes() == 0) {
                    return errors.OptimisticLockError.StaleObject;
                }
                // Update struct version in memory on success
                @field(item.*, "version") += 1;
            }

            // Call afterUpdate hook
            try hooks.callHook(item, "afterUpdate");
        }

        /// Delete a specific model instance by ID, triggering hooks
        pub fn deleteModel(self: *Self, comptime TableT: type, item: *TableT.model_type) !void {
            // Call beforeDelete hook
            try hooks.callHook(item, "beforeDelete");

            const sql_raw = try std.fmt.allocPrint(self.allocator, "DELETE FROM {s} WHERE id = ?", .{TableT.table_name});
            defer self.allocator.free(sql_raw);
            const sql = try self.allocator.dupeZ(u8, sql_raw);
            defer self.allocator.free(sql);

            var timer = std.time.Timer.start() catch unreachable;
            var stmt = try self.adapter.prepare(sql);
            defer {
                stmt.deinit();
                self.dispatchLog(sql, timer.read());
            }

            try stmt.bind_int(0, @intCast(item.id));
            _ = try stmt.step();

            // Call afterDelete hook
            try hooks.callHook(item, "afterDelete");
        }
    };
}
