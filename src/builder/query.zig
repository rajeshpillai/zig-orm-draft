const std = @import("std");
const core_types = @import("../core/types.zig");
const timestamps = @import("../core/timestamps.zig");

pub const Operator = enum {
    eq,
    neq,
    gt,
    gte,
    lt,
    lte,
    like,
    in,
    not_in,
    is_null,
    is_not_null,

    pub fn toSql(self: Operator) []const u8 {
        return switch (self) {
            .eq => "=",
            .neq => "!=",
            .gt => ">",
            .gte => ">=",
            .lt => "<",
            .lte => "<=",
            .like => "LIKE",
            .in => "IN",
            .not_in => "NOT IN",
            .is_null => "IS NULL",
            .is_not_null => "IS NOT NULL",
        };
    }
};

pub const Logical = enum {
    AND,
    OR,
    NOT,

    pub fn toSql(self: Logical) []const u8 {
        return switch (self) {
            .AND => "AND",
            .OR => "OR",
            .NOT => "NOT",
        };
    }
};

pub fn Query(comptime TableT: type) type {
    return struct {
        pub const Table = TableT;
        const Self = @This();

        allocator: std.mem.Allocator,
        params: std.ArrayList(core_types.Value),
        where_exprs: std.ArrayList(u8),
        select_exprs: std.ArrayList(u8),
        group_by_exprs: std.ArrayList(u8),
        limit_val: ?u64 = null,
        offset_val: ?u64 = null,

        pub fn init(allocator: std.mem.Allocator) !Self {
            return Self{
                .allocator = allocator,
                .params = try std.ArrayList(core_types.Value).initCapacity(allocator, 0),
                .where_exprs = try std.ArrayList(u8).initCapacity(allocator, 0),
                .select_exprs = try std.ArrayList(u8).initCapacity(allocator, 0),
                .group_by_exprs = try std.ArrayList(u8).initCapacity(allocator, 0),
            };
        }

        pub fn deinit(self: *Self) void {
            self.params.deinit(self.allocator);
            self.where_exprs.deinit(self.allocator);
            self.select_exprs.deinit(self.allocator);
            self.group_by_exprs.deinit(self.allocator);
        }

        // Allow chaining
        pub fn where(self: *Self, condition: anytype) !*Self {
            return try self.whereInternal(condition, true);
        }

        fn whereInternal(self: *Self, condition: anytype, add_prefix: bool) !*Self {
            const T = @TypeOf(condition);
            const info = @typeInfo(T);

            // Handle Tuple Conditions: .{ .field, .operator, value }
            if (info == .@"struct" and info.@"struct".is_tuple) {
                const fields = info.@"struct".fields;
                if (fields.len == 3) {
                    const field_or_expr = @field(condition, "0");
                    const op_or_log_val = @field(condition, "1");
                    const val_or_expr = @field(condition, "2");

                    const op_or_log_type = @TypeOf(op_or_log_val);
                    const op_or_log_info = @typeInfo(op_or_log_type);

                    const maybe_op: ?Operator = comptime blk: {
                        if (op_or_log_type == Operator) break :blk op_or_log_val;
                        if (op_or_log_info == .@"enum" or op_or_log_info == .enum_literal) {
                            for (std.enums.values(Operator)) |op| {
                                if (std.mem.eql(u8, @tagName(op), @tagName(op_or_log_val))) break :blk op;
                            }
                        }
                        break :blk null;
                    };
                    const maybe_log: ?Logical = comptime blk: {
                        if (op_or_log_type == Logical) break :blk op_or_log_val;
                        if (op_or_log_info == .@"enum" or op_or_log_info == .enum_literal) {
                            for (std.enums.values(Logical)) |log| {
                                if (std.mem.eql(u8, @tagName(log), @tagName(op_or_log_val))) break :blk log;
                            }
                        }
                        break :blk null;
                    };

                    if (maybe_op) |op| {
                        if (add_prefix and self.where_exprs.items.len > 0) {
                            try self.where_exprs.appendSlice(self.allocator, " AND ");
                        }

                        const field_str = blk: {
                            const FT = @TypeOf(field_or_expr);
                            if (FT == []const u8) break :blk field_or_expr;
                            if (@typeInfo(FT) == .@"enum" or @typeInfo(FT) == .enum_literal) break :blk @tagName(field_or_expr);
                            break :blk "";
                        };
                        try self.where_exprs.appendSlice(self.allocator, field_str);
                        try self.where_exprs.appendSlice(self.allocator, " ");
                        try self.where_exprs.appendSlice(self.allocator, op.toSql());

                        if (op != .is_null and op != .is_not_null) {
                            try self.where_exprs.appendSlice(self.allocator, " ?");
                            try self.addParam(val_or_expr);
                        }
                        return self;
                    }

                    if (maybe_log) |log| {
                        if (add_prefix and self.where_exprs.items.len > 0) {
                            try self.where_exprs.appendSlice(self.allocator, " AND ");
                        }
                        try self.where_exprs.appendSlice(self.allocator, "(");

                        const FT = @TypeOf(field_or_expr);
                        if (comptime @typeInfo(FT) == .@"struct") {
                            _ = try self.whereInternal(field_or_expr, false);
                        } else {
                            return error.InvalidConditionType;
                        }

                        try self.where_exprs.appendSlice(self.allocator, " ");
                        try self.where_exprs.appendSlice(self.allocator, log.toSql());
                        try self.where_exprs.appendSlice(self.allocator, " ");

                        const VT = @TypeOf(val_or_expr);
                        if (comptime @typeInfo(VT) == .@"struct") {
                            _ = try self.whereInternal(val_or_expr, false);
                        } else {
                            return error.InvalidConditionType;
                        }

                        try self.where_exprs.appendSlice(self.allocator, ")");
                        return self;
                    }
                }
            }

            // Fallback to existing struct-based equality
            if (info != .@"struct") @compileError("Condition must be a struct");

            inline for (info.@"struct".fields) |field| {
                if (add_prefix and self.where_exprs.items.len > 0) {
                    try self.where_exprs.appendSlice(self.allocator, " AND ");
                }

                try self.where_exprs.appendSlice(self.allocator, field.name);
                try self.where_exprs.appendSlice(self.allocator, " = ?");

                try self.addParam(@field(condition, field.name));
            }
            return self;
        }

        fn addParam(self: *Self, val: anytype) !void {
            const T = @TypeOf(val);
            switch (@typeInfo(T)) {
                .int, .comptime_int => try self.params.append(self.allocator, .{ .Integer = @intCast(val) }),
                .bool => try self.params.append(self.allocator, .{ .Boolean = val }),
                .pointer => |ptr| {
                    if (ptr.child == u8) {
                        try self.params.append(self.allocator, .{ .Text = val });
                    } else if (@typeInfo(ptr.child) == .array and (@typeInfo(ptr.child).array.child == u8 or @typeInfo(ptr.child).array.child == comptime_int)) {
                        try self.params.append(self.allocator, .{ .Text = val });
                    } else {
                        return error.UnsupportedTypeInWhere;
                    }
                },
                .optional => {
                    if (val) |v| {
                        try self.addParam(v);
                    }
                },
                .null => {},
                else => return error.UnsupportedTypeInWhere,
            }
        }

        /// Add WHERE field IN (?, ?, ...) clause
        pub fn whereIn(self: *Self, comptime field: []const u8, values: []const i64) !*Self {
            if (values.len == 0) return self;

            if (self.where_exprs.items.len > 0) {
                try self.where_exprs.appendSlice(self.allocator, " AND ");
            }

            try self.where_exprs.appendSlice(self.allocator, field);
            try self.where_exprs.appendSlice(self.allocator, " IN (");

            for (values, 0..) |val, i| {
                if (i > 0) try self.where_exprs.appendSlice(self.allocator, ", ");
                try self.where_exprs.appendSlice(self.allocator, "?");
                try self.params.append(self.allocator, .{ .Integer = val });
            }

            try self.where_exprs.appendSlice(self.allocator, ")");
            return self;
        }

        pub fn limit(self: *Self, value: u64) *Self {
            self.limit_val = value;
            return self;
        }

        pub fn offset(self: *Self, value: u64) *Self {
            self.offset_val = value;
            return self;
        }

        pub fn select(self: *Self, expr: []const u8) !*Self {
            if (self.select_exprs.items.len > 0) {
                try self.select_exprs.appendSlice(self.allocator, ", ");
            }
            try self.select_exprs.appendSlice(self.allocator, expr);
            return self;
        }

        pub fn count(self: *Self, field: []const u8) !*Self {
            var buf: [256]u8 = undefined;
            const expr = try std.fmt.bufPrint(&buf, "COUNT({s})", .{field});
            return try self.select(expr);
        }

        pub fn groupBy(self: *Self, field: []const u8) !*Self {
            if (self.group_by_exprs.items.len > 0) {
                try self.group_by_exprs.appendSlice(self.allocator, ", ");
            }
            try self.group_by_exprs.appendSlice(self.allocator, field);
            return self;
        }

        pub fn toSql(self: Self, allocator: std.mem.Allocator) ![:0]u8 {
            var list = try std.ArrayList(u8).initCapacity(allocator, 0);
            errdefer list.deinit(allocator);

            try list.appendSlice(allocator, "SELECT ");

            if (self.select_exprs.items.len > 0) {
                try list.appendSlice(allocator, self.select_exprs.items);
            } else {
                inline for (TableT.columns, 0..) |col, i| {
                    if (i > 0) try list.appendSlice(allocator, ", ");
                    try list.appendSlice(allocator, col.name);
                }
            }

            try list.appendSlice(allocator, " FROM ");
            try list.appendSlice(allocator, TableT.table_name);

            if (self.where_exprs.items.len > 0) {
                try list.appendSlice(allocator, " WHERE ");
                try list.appendSlice(allocator, self.where_exprs.items);
            }

            if (self.group_by_exprs.items.len > 0) {
                try list.appendSlice(allocator, " GROUP BY ");
                try list.appendSlice(allocator, self.group_by_exprs.items);
            }

            if (self.limit_val) |_| {
                try list.appendSlice(allocator, " LIMIT ?");
            }

            if (self.offset_val) |_| {
                try list.appendSlice(allocator, " OFFSET ?");
            }

            return try list.toOwnedSliceSentinel(allocator, 0);
        }
    };
}

pub fn from(comptime TableT: type, allocator: std.mem.Allocator) !Query(TableT) {
    return try Query(TableT).init(allocator);
}

pub fn Insert(comptime TableT: type) type {
    return struct {
        pub const Table = TableT;
        const Self = @This();

        items: std.ArrayList(TableT.model_type),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{
                .items = try std.ArrayList(TableT.model_type).initCapacity(allocator, 0),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit(self.allocator);
        }

        pub fn add(self: *Self, item: TableT.model_type) !void {
            try self.items.append(self.allocator, item);
        }

        pub fn toStatementSql(self: Self) ![:0]u8 {
            var list = try std.ArrayList(u8).initCapacity(self.allocator, 0);
            errdefer list.deinit(self.allocator);

            try list.appendSlice(self.allocator, "INSERT INTO ");
            try list.appendSlice(self.allocator, TableT.table_name);
            try list.appendSlice(self.allocator, " (");

            inline for (TableT.columns, 0..) |col, i| {
                if (i > 0) try list.appendSlice(self.allocator, ", ");
                try list.appendSlice(self.allocator, col.name);
            }
            try list.appendSlice(self.allocator, ") VALUES (");

            inline for (TableT.columns, 0..) |col, i| {
                _ = col;
                if (i > 0) try list.appendSlice(self.allocator, ", ");
                try list.appendSlice(self.allocator, "?");
            }
            try list.appendSlice(self.allocator, ")");

            return try list.toOwnedSliceSentinel(self.allocator, 0);
        }

        pub fn toSql(self: Self) ![:0]u8 {
            if (self.items.items.len == 0) return error.NoItemsToInsert;

            var list = try std.ArrayList(u8).initCapacity(self.allocator, 0);
            errdefer list.deinit(self.allocator);

            try list.appendSlice(self.allocator, "INSERT INTO ");
            try list.appendSlice(self.allocator, TableT.table_name);
            try list.appendSlice(self.allocator, " (");

            inline for (TableT.columns, 0..) |col, i| {
                if (i > 0) try list.appendSlice(self.allocator, ", ");
                try list.appendSlice(self.allocator, col.name);
            }
            try list.appendSlice(self.allocator, ") VALUES ");

            for (self.items.items, 0..) |item, row_idx| {
                _ = item;
                if (row_idx > 0) try list.appendSlice(self.allocator, ", ");
                try list.appendSlice(self.allocator, "(");

                inline for (TableT.columns, 0..) |col, i| {
                    _ = col;
                    if (i > 0) try list.appendSlice(self.allocator, ", ");
                    try list.appendSlice(self.allocator, "?");
                }
                try list.appendSlice(self.allocator, ")");
            }

            return try list.toOwnedSliceSentinel(self.allocator, 0);
        }
    };
}

pub fn Update(comptime TableT: type) type {
    return struct {
        pub const Table = TableT;
        const Self = @This();

        allocator: std.mem.Allocator,
        params: std.ArrayList(core_types.Value),
        set_exprs: std.ArrayList(u8),
        where_exprs: std.ArrayList(u8),
        set_params_count: usize = 0,

        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{
                .allocator = allocator,
                .params = try std.ArrayList(core_types.Value).initCapacity(allocator, 0),
                .set_exprs = try std.ArrayList(u8).initCapacity(allocator, 0),
                .where_exprs = try std.ArrayList(u8).initCapacity(allocator, 0),
            };
        }

        pub fn deinit(self: *Self) void {
            self.params.deinit(self.allocator);
            self.set_exprs.deinit(self.allocator);
            self.where_exprs.deinit(self.allocator);
        }

        pub fn set(self: *Self, values: anytype) !*Self {
            const T = @TypeOf(values);
            const info = @typeInfo(T);

            if (info != .@"struct") @compileError("Values must be a struct");

            inline for (info.@"struct".fields) |field| {
                if (self.set_exprs.items.len > 0) {
                    try self.set_exprs.appendSlice(self.allocator, ", ");
                }

                try self.set_exprs.appendSlice(self.allocator, field.name);
                try self.set_exprs.appendSlice(self.allocator, " = ?");

                const val = @field(values, field.name);
                const val_t = @TypeOf(val);

                // Improved type handling
                const type_info = @typeInfo(val_t);
                var handled = false;

                if (type_info == .pointer) {
                    const ptr_info = type_info.pointer;
                    if (ptr_info.size == .one) {
                        const child_info = @typeInfo(ptr_info.child);
                        if (child_info == .array) {
                            if (child_info.array.child == u8) {
                                const slice: []const u8 = val;
                                try self.params.append(self.allocator, .{ .Text = slice });
                                handled = true;
                            }
                        }
                    }
                }

                if (!handled) {
                    if (val_t == []const u8 or val_t == [:0]const u8) {
                        try self.params.append(self.allocator, .{ .Text = val });
                    } else if (val_t == i64 or val_t == i32 or val_t == comptime_int) {
                        try self.params.append(self.allocator, .{ .Integer = @intCast(val) });
                    } else if (val_t == bool) {
                        try self.params.append(self.allocator, .{ .Boolean = val });
                    } else {
                        return error.UnsupportedTypeInUpdate;
                    }
                }
                self.set_params_count += 1;
            }
            return self;
        }

        pub fn where(self: *Self, condition: anytype) !*Self {
            // Reuse logic? Or copy-paste for speed safely?
            // Copy-paste safely for now to avoid cross-dependency complexity in immediate step
            const T = @TypeOf(condition);
            const info = @typeInfo(T);

            if (info != .@"struct") @compileError("Condition must be a struct");

            inline for (info.@"struct".fields) |field| {
                if (self.where_exprs.items.len > 0) {
                    try self.where_exprs.appendSlice(self.allocator, " AND ");
                }

                try self.where_exprs.appendSlice(self.allocator, field.name);
                try self.where_exprs.appendSlice(self.allocator, " = ?");

                const val = @field(condition, field.name);
                const val_t = @TypeOf(val);

                // Improved type handling
                const type_info = @typeInfo(val_t);
                var handled = false;

                if (type_info == .pointer) {
                    const ptr_info = type_info.pointer;
                    if (ptr_info.size == .one) {
                        const child_info = @typeInfo(ptr_info.child);
                        if (child_info == .array) {
                            if (child_info.array.child == u8) {
                                const slice: []const u8 = val;
                                try self.params.append(self.allocator, .{ .Text = slice });
                                handled = true;
                            }
                        }
                    }
                }

                if (!handled) {
                    if (val_t == []const u8 or val_t == [:0]const u8) {
                        try self.params.append(self.allocator, .{ .Text = val });
                    } else if (val_t == i64 or val_t == i32 or val_t == comptime_int) {
                        try self.params.append(self.allocator, .{ .Integer = @intCast(val) });
                    } else if (val_t == bool) {
                        try self.params.append(self.allocator, .{ .Boolean = val });
                    } else {
                        return error.UnsupportedTypeInWhere;
                    }
                }
            }
            return self;
        }

        pub fn toSql(self: *Self) ![:0]u8 {
            // Auto-update updated_at if it exists and wasn't explicitly set
            if (comptime timestamps.hasUpdatedAt(TableT.model_type)) {
                const updated_at_field = "updated_at";
                if (std.mem.indexOf(u8, self.set_exprs.items, updated_at_field) == null) {
                    if (self.set_exprs.items.len > 0) {
                        try self.set_exprs.appendSlice(self.allocator, ", ");
                    }
                    try self.set_exprs.appendSlice(self.allocator, updated_at_field);
                    try self.set_exprs.appendSlice(self.allocator, " = ?");

                    // Insert updated_at param at the end of SET params
                    try self.params.insert(self.allocator, self.set_params_count, .{ .Integer = timestamps.currentTimestamp() });
                    self.set_params_count += 1;
                }
            }

            var list = try std.ArrayList(u8).initCapacity(self.allocator, 0);
            errdefer list.deinit(self.allocator);

            try list.appendSlice(self.allocator, "UPDATE ");
            try list.appendSlice(self.allocator, TableT.table_name);
            try list.appendSlice(self.allocator, " SET ");
            try list.appendSlice(self.allocator, self.set_exprs.items);

            if (self.where_exprs.items.len > 0) {
                try list.appendSlice(self.allocator, " WHERE ");
                try list.appendSlice(self.allocator, self.where_exprs.items);
            }

            return try list.toOwnedSliceSentinel(self.allocator, 0);
        }
    };
}

pub fn Delete(comptime TableT: type) type {
    return struct {
        pub const Table = TableT;
        const Self = @This();

        allocator: std.mem.Allocator,
        params: std.ArrayList(core_types.Value),
        where_exprs: std.ArrayList(u8),

        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{
                .allocator = allocator,
                .params = try std.ArrayList(core_types.Value).initCapacity(allocator, 0),
                .where_exprs = try std.ArrayList(u8).initCapacity(allocator, 0),
            };
        }

        pub fn deinit(self: *Self) void {
            self.params.deinit(self.allocator);
            self.where_exprs.deinit(self.allocator);
        }

        pub fn where(self: *Self, condition: anytype) !*Self {
            const T = @TypeOf(condition);
            const info = @typeInfo(T);

            if (info != .@"struct") @compileError("Condition must be a struct");

            inline for (info.@"struct".fields) |field| {
                if (self.where_exprs.items.len > 0) {
                    try self.where_exprs.appendSlice(self.allocator, " AND ");
                }

                try self.where_exprs.appendSlice(self.allocator, field.name);
                try self.where_exprs.appendSlice(self.allocator, " = ?");

                const val = @field(condition, field.name);
                const val_t = @TypeOf(val);

                // Improved type handling
                const type_info = @typeInfo(val_t);
                var handled = false;

                if (type_info == .pointer) {
                    const ptr_info = type_info.pointer;
                    if (ptr_info.size == .one) {
                        const child_info = @typeInfo(ptr_info.child);
                        if (child_info == .array) {
                            if (child_info.array.child == u8) {
                                const slice: []const u8 = val;
                                try self.params.append(self.allocator, .{ .Text = slice });
                                handled = true;
                            }
                        }
                    }
                }

                if (!handled) {
                    if (val_t == []const u8 or val_t == [:0]const u8) {
                        try self.params.append(self.allocator, .{ .Text = val });
                    } else if (val_t == i64 or val_t == i32 or val_t == comptime_int) {
                        try self.params.append(self.allocator, .{ .Integer = @intCast(val) });
                    } else if (val_t == bool) {
                        try self.params.append(self.allocator, .{ .Boolean = val });
                    } else {
                        return error.UnsupportedTypeInWhere;
                    }
                }
            }
            return self;
        }

        pub fn toSql(self: Self) ![:0]u8 {
            var list = try std.ArrayList(u8).initCapacity(self.allocator, 0);
            errdefer list.deinit(self.allocator);

            try list.appendSlice(self.allocator, "DELETE FROM ");
            try list.appendSlice(self.allocator, TableT.table_name);

            if (self.where_exprs.items.len > 0) {
                try list.appendSlice(self.allocator, " WHERE ");
                try list.appendSlice(self.allocator, self.where_exprs.items);
            }

            return try list.toOwnedSliceSentinel(self.allocator, 0);
        }
    };
}
