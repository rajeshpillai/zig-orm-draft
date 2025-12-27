const std = @import("std");
const core_types = @import("../core/types.zig");

pub fn Query(comptime TableT: type) type {
    return struct {
        pub const Table = TableT;
        const Self = @This();

        allocator: std.mem.Allocator,
        params: std.ArrayList(core_types.Value),
        where_exprs: std.ArrayList(u8),

        pub fn init(allocator: std.mem.Allocator) !Self {
            return Self{
                .allocator = allocator,
                .params = try std.ArrayList(core_types.Value).initCapacity(allocator, 0),
                .where_exprs = try std.ArrayList(u8).initCapacity(allocator, 0),
            };
        }

        pub fn deinit(self: *Self) void {
            self.params.deinit(self.allocator);
            self.where_exprs.deinit(self.allocator);
        }

        // Allow chaining
        pub fn where(self: *Self, condition: anytype) !*Self {
            const T = @TypeOf(condition);
            const info = @typeInfo(T);

            // Zig master: .Struct -> .@"struct"
            if (info != .@"struct") @compileError("Condition must be a struct");

            inline for (info.@"struct".fields) |field| {
                if (self.where_exprs.items.len > 0) {
                    try self.where_exprs.appendSlice(self.allocator, " AND ");
                }

                try self.where_exprs.appendSlice(self.allocator, field.name);
                try self.where_exprs.appendSlice(self.allocator, " = ?");

                const val = @field(condition, field.name);
                const val_t = @TypeOf(val);

                // Inspect type to handle params
                const type_info = @typeInfo(val_t);

                // Handle String Literal / Slice
                var handled = false;

                // Zig master: .Pointer -> .pointer
                if (type_info == .pointer) {
                    const ptr_info = type_info.pointer;
                    if (ptr_info.size == .one) {
                        const child_info = @typeInfo(ptr_info.child);
                        // Zig master: .Array -> .array
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

        pub fn toSql(self: Self, allocator: std.mem.Allocator) ![:0]u8 {
            var list = try std.ArrayList(u8).initCapacity(allocator, 0);
            errdefer list.deinit(allocator);

            try list.appendSlice(allocator, "SELECT ");

            inline for (TableT.columns, 0..) |col, i| {
                if (i > 0) try list.appendSlice(allocator, ", ");
                try list.appendSlice(allocator, col.name);
            }

            try list.appendSlice(allocator, " FROM ");
            try list.appendSlice(allocator, TableT.table_name);

            if (self.where_exprs.items.len > 0) {
                try list.appendSlice(allocator, " WHERE ");
                try list.appendSlice(allocator, self.where_exprs.items);
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
