const std = @import("std");

pub fn Query(comptime TableT: type) type {
    return struct {
        pub const Table = TableT;
        const Self = @This();

        pub fn init() Self {
            return .{};
        }

        // Allow chaining
        pub fn where(self: Self, condition: anytype) Self {
            _ = condition;
            _ = self;
            return .{};
        }

        pub fn toSql(self: Self, allocator: std.mem.Allocator) ![:0]u8 {
            _ = self;
            var list = try std.ArrayList(u8).initCapacity(allocator, 0);
            errdefer list.deinit(allocator);

            try list.appendSlice(allocator, "SELECT ");

            inline for (TableT.columns, 0..) |col, i| {
                if (i > 0) try list.appendSlice(allocator, ", ");
                try list.appendSlice(allocator, col.name);
            }

            try list.appendSlice(allocator, " FROM ");
            try list.appendSlice(allocator, TableT.table_name);
            return try list.toOwnedSliceSentinel(allocator, 0);
        }
    };
}

pub fn from(comptime TableT: type) Query(TableT) {
    return Query(TableT).init();
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
            // Generates a single-row INSERT statement: "INSERT INTO table (col1, col2) VALUES (?, ?)"
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
