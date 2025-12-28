const std = @import("std");
const Allocator = std.mem.Allocator;

pub const DataType = enum {
    integer,
    text,
    float,
    boolean,
    blob,
    timestamp,

    pub fn toSql(self: DataType, adapter_type: []const u8) []const u8 {
        _ = adapter_type; // For now, simple mapping
        return switch (self) {
            .integer => "BIGINT",
            .text => "TEXT",
            .float => "DOUBLE PRECISION",
            .boolean => "BOOLEAN",
            .blob => "BLOB",
            .timestamp => "BIGINT",
        };
    }
};

pub const Column = struct {
    name: []const u8,
    type: DataType,
    primary_key: bool = false,
    nullable: bool = true,
    unique: bool = false,
    default: ?[]const u8 = null,
    // Future: references: ?struct { table: []const u8, column: []const u8 } = null,
};

pub fn MigrationHelper(comptime Adapter: type) type {
    return struct {
        const Self = @This();
        adapter: *Adapter,
        allocator: Allocator,

        pub fn init(adapter: *Adapter, allocator: Allocator) Self {
            return .{
                .adapter = adapter,
                .allocator = allocator,
            };
        }

        pub fn createTable(self: *Self, name: []const u8, columns: []const Column) !void {
            var sql = std.ArrayList(u8){};
            defer sql.deinit(self.allocator);

            try sql.appendSlice(self.allocator, "CREATE TABLE ");
            try sql.appendSlice(self.allocator, name);
            try sql.appendSlice(self.allocator, " (");

            for (columns, 0..) |col, i| {
                if (i > 0) try sql.appendSlice(self.allocator, ", ");
                try sql.appendSlice(self.allocator, col.name);
                try sql.appendSlice(self.allocator, " ");
                try sql.appendSlice(self.allocator, col.type.toSql(""));

                if (col.primary_key) try sql.appendSlice(self.allocator, " PRIMARY KEY");
                if (!col.nullable) try sql.appendSlice(self.allocator, " NOT NULL");
                if (col.unique) try sql.appendSlice(self.allocator, " UNIQUE");
                if (col.default) |def| {
                    try sql.appendSlice(self.allocator, " DEFAULT ");
                    try sql.appendSlice(self.allocator, def);
                }
            }

            try sql.appendSlice(self.allocator, ")");

            const final_sql = try self.allocator.dupeZ(u8, sql.items);
            defer self.allocator.free(final_sql);

            try self.adapter.exec(final_sql);
        }

        pub fn dropTable(self: *Self, name: []const u8) !void {
            const sql_raw = try std.fmt.allocPrint(self.allocator, "DROP TABLE {s}", .{name});
            defer self.allocator.free(sql_raw);
            const sql = try self.allocator.dupeZ(u8, sql_raw);
            defer self.allocator.free(sql);
            try self.adapter.exec(sql);
        }

        pub fn addColumn(self: *Self, table: []const u8, col: Column) !void {
            var sql = std.ArrayList(u8){};
            defer sql.deinit(self.allocator);

            try sql.appendSlice(self.allocator, "ALTER TABLE ");
            try sql.appendSlice(self.allocator, table);
            try sql.appendSlice(self.allocator, " ADD COLUMN ");
            try sql.appendSlice(self.allocator, col.name);
            try sql.appendSlice(self.allocator, " ");
            try sql.appendSlice(self.allocator, col.type.toSql(""));

            if (!col.nullable) try sql.appendSlice(self.allocator, " NOT NULL");
            if (col.unique) try sql.appendSlice(self.allocator, " UNIQUE");
            if (col.default) |def| {
                try sql.appendSlice(self.allocator, " DEFAULT ");
                try sql.appendSlice(self.allocator, def);
            }

            const final_sql = try self.allocator.dupeZ(u8, sql.items);
            defer self.allocator.free(final_sql);

            try self.adapter.exec(final_sql);
        }

        pub fn removeColumn(self: *Self, table: []const u8, name: []const u8) !void {
            const sql_raw = try std.fmt.allocPrint(self.allocator, "ALTER TABLE {s} DROP COLUMN {s}", .{ table, name });
            defer self.allocator.free(sql_raw);
            const sql = try self.allocator.dupeZ(u8, sql_raw);
            defer self.allocator.free(sql);
            try self.adapter.exec(sql);
        }

        pub fn addIndex(self: *Self, table: []const u8, name: []const u8, columns: []const []const u8, unique: bool) !void {
            var sql = std.ArrayList(u8){};
            defer sql.deinit(self.allocator);

            try sql.appendSlice(self.allocator, "CREATE ");
            if (unique) try sql.appendSlice(self.allocator, "UNIQUE ");
            try sql.appendSlice(self.allocator, "INDEX ");
            try sql.appendSlice(self.allocator, name);
            try sql.appendSlice(self.allocator, " ON ");
            try sql.appendSlice(self.allocator, table);
            try sql.appendSlice(self.allocator, " (");

            for (columns, 0..) |col, i| {
                if (i > 0) try sql.appendSlice(self.allocator, ", ");
                try sql.appendSlice(self.allocator, col);
            }
            try sql.appendSlice(self.allocator, ")");

            const final_sql = try self.allocator.dupeZ(u8, sql.items);
            defer self.allocator.free(final_sql);
            try self.adapter.exec(final_sql);
        }
    };
}
