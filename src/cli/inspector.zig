const std = @import("std");
const orm = @import("zig-orm");

pub const ColumnInfo = struct {
    name: []const u8,
    type: []const u8,
    notnull: bool,
    pk: bool,
};

pub fn inspectSqlite(allocator: std.mem.Allocator, db: *orm.sqlite.SQLite, table_name: []const u8) ![]ColumnInfo {
    // PRAGMA table_info(table_name)
    // Results: cid, name, type, notnull, dflt_value, pk
    const sql_raw = try std.fmt.allocPrint(allocator, "PRAGMA table_info({s})", .{table_name});
    defer allocator.free(sql_raw);
    const sql = try allocator.dupeZ(u8, sql_raw);
    defer allocator.free(sql);

    // Note: Parameter binding for PRAGMA table name might not work in all drivers,
    // so we format the string. Minimal SQL injection risk if run by dev in CLI.
    var stmt = try db.prepare(sql);
    defer stmt.deinit();

    var columns = try std.ArrayList(ColumnInfo).initCapacity(allocator, 0);
    errdefer {
        for (columns.items) |col| {
            allocator.free(col.name);
            allocator.free(col.type);
        }
        columns.deinit(allocator);
    }

    while (try stmt.step()) {
        const name_val = orm.sqlite.SQLite.column_text(&stmt, 1) orelse continue;
        const type_val = orm.sqlite.SQLite.column_text(&stmt, 2) orelse "TEXT";
        const notnull_val = orm.sqlite.SQLite.column_int(&stmt, 3);
        const pk_val = orm.sqlite.SQLite.column_int(&stmt, 5);

        try columns.append(allocator, .{
            .name = try allocator.dupe(u8, name_val),
            .type = try allocator.dupe(u8, type_val),
            .notnull = (notnull_val != 0),
            .pk = (pk_val != 0),
        });
    }

    return columns.toOwnedSlice(allocator);
}

pub fn generateModelCode(allocator: std.mem.Allocator, table_name: []const u8, columns: []const ColumnInfo) ![]const u8 {
    var code = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer code.deinit(allocator);

    // Convert table_name (snake_case) to PascalCase for struct name
    const struct_name = try toPascalCase(allocator, table_name);
    defer allocator.free(struct_name);

    const header = try std.fmt.allocPrint(allocator,
        \\const orm = @import("zig-orm");
        \\
        \\pub const {s} = struct {{
        \\    const Self = @This();
        \\    pub const table_name = "{s}";
        \\
        \\
    , .{ struct_name, table_name });
    defer allocator.free(header);
    try code.appendSlice(allocator, header);

    for (columns) |col| {
        const zig_type = mapSqlTypeToZig(col.type);

        const is_optional = !col.notnull;

        var line: []u8 = undefined;
        if (is_optional) {
            line = try std.fmt.allocPrint(allocator, "    {s}: ?{s},\n", .{ col.name, zig_type });
        } else {
            line = try std.fmt.allocPrint(allocator, "    {s}: {s},\n", .{ col.name, zig_type });
        }
        defer allocator.free(line);
        try code.appendSlice(allocator, line);
    }

    // Generate 'columns' decl for introspection/internal use if needed
    // (Optional, based on how existing models work. Existing examples don't strictly require it unless used by internal macros,
    // but users often add rules there. Let's keep it simple for now).

    try code.appendSlice(allocator, "};\n");

    return code.toOwnedSlice(allocator);
}

fn mapSqlTypeToZig(sql_type_raw: []const u8) []const u8 {
    // Make uppercase for comparison
    // We assume the caller (inspect) passed a string we can read.
    // Ideally we should normalize, but simple contains check works for now.

    // SQLite types: INTEGER, TEXT, REAL, BLOB
    // Postgres types: integer, varchar, text, boolean, timestamp...

    // Simple heuristic mapping
    if (containsIgnoreCase(sql_type_raw, "INT")) return "i64";
    if (containsIgnoreCase(sql_type_raw, "CHAR") or containsIgnoreCase(sql_type_raw, "TEXT") or containsIgnoreCase(sql_type_raw, "CLOB")) return "[]const u8";
    if (containsIgnoreCase(sql_type_raw, "REAL") or containsIgnoreCase(sql_type_raw, "FLOAT") or containsIgnoreCase(sql_type_raw, "DOUBLE")) return "f64";
    if (containsIgnoreCase(sql_type_raw, "BOOL")) return "bool";
    if (containsIgnoreCase(sql_type_raw, "BLOB")) return "[]const u8";

    // Fallback
    return "[]const u8";
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    // Very inefficient check, but fine for type mapping logic
    // Just simple substring search ignoring case
    // For now, simpler: case insensitive compare if lengths equal?
    // No, "VARCHAR(255)" contains "CHAR".

    // Let's iterate
    if (needle.len > haystack.len) return false;
    for (0..(haystack.len - needle.len + 1)) |i| {
        var match = true;
        for (0..needle.len) |j| {
            if (std.ascii.toUpper(haystack[i + j]) != std.ascii.toUpper(needle[j])) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

fn toPascalCase(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, input.len);
    var capitalize_next = true;
    for (input) |c| {
        if (c == '_') {
            capitalize_next = true;
        } else {
            if (capitalize_next) {
                try out.append(allocator, std.ascii.toUpper(c));
                capitalize_next = false;
            } else {
                try out.append(allocator, std.ascii.toLower(c));
            }
        }
    }
    return out.toOwnedSlice(allocator);
}
