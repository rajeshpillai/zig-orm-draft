const std = @import("std");
const build_options = @import("build_options");

const HELP_TEXT =
    \\Zig ORM CLI
    \\
    \\Usage:
    \\  zig-orm [command] [options]
    \\
    \\Commands:
    \\  help                    Show this help
    \\  version                 Show version
    \\  generate:migration <name> Create a new migration file
    \\  migrate                 Run pending migrations
    \\  rollback                Rollback last migration
    \\
    \\Options:
    \\  --db <path>             Database path (default: development.db)
    \\
;

const VERSION = "0.1.0";

const orm = @import("zig-orm");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("{s}", .{HELP_TEXT});
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "help")) {
        std.debug.print("{s}", .{HELP_TEXT});
    } else if (std.mem.eql(u8, command, "version")) {
        std.debug.print("Zig ORM CLI v{s}\n", .{VERSION});
    } else if (std.mem.eql(u8, command, "generate:migration")) {
        if (args.len < 3) {
            std.debug.print("Error: migration name required\n", .{});
            return;
        }
        try generateMigration(allocator, args[2]);
    } else if (std.mem.eql(u8, command, "migrate")) {
        try executeMigrate(allocator);
    } else if (std.mem.eql(u8, command, "rollback")) {
        try executeRollback(allocator);
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        std.debug.print("{s}", .{HELP_TEXT});
    }
}

fn executeMigrate(allocator: std.mem.Allocator) !void {
    if (comptime !build_options.has_migrations) {
        std.debug.print("No migrations found. Run generate:migration first.\n", .{});
        return;
    }
    const migrations = @import("migrations");

    // Default to SQLite development.db for now
    var db = try orm.sqlite.SQLite.init("development.db");
    defer db.deinit();

    var runner = orm.migrations.MigrationRunner(orm.sqlite.SQLite).init(&db, allocator);
    try runner.migrate(&migrations.list);
}

fn executeRollback(allocator: std.mem.Allocator) !void {
    if (comptime !build_options.has_migrations) {
        std.debug.print("No migrations found.\n", .{});
        return;
    }
    const migrations = @import("migrations");

    var db = try orm.sqlite.SQLite.init("development.db");
    defer db.deinit();

    var runner = orm.migrations.MigrationRunner(orm.sqlite.SQLite).init(&db, allocator);
    // Rollback the last one
    if (migrations.list.len > 0) {
        try runner.rollback(&migrations.list, 1);
    }
}

fn generateMigration(allocator: std.mem.Allocator, name: []const u8) !void {
    const timestamp = orm.timestamps.currentTimestamp();

    // Ensure migrations directory exists
    std.fs.cwd().makePath("migrations") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const filename = try std.fmt.allocPrint(allocator, "migrations/{d}_{s}.zig", .{ timestamp, name });
    defer allocator.free(filename);

    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    const template =
        \\const std = @import("std");
        \\const orm = @import("zig-orm");
        \\
        \\pub fn up(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
        \\    _ = db_ptr;
        \\    _ = allocator;
        \\    // const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
        \\    // var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);
        \\    
        \\    // try helper.createTable("table_name", &[_]orm.migrations.helpers.Column{
        \\    //     .{ .name = "id", .type = .integer, .primary_key = true },
        \\    // });
        \\}
        \\
        \\pub fn down(db_ptr: *anyopaque, allocator: std.mem.Allocator) !void {
        \\    _ = db_ptr;
        \\    _ = allocator;
        \\    // const db: *orm.sqlite.SQLite = @ptrCast(@alignCast(db_ptr));
        \\    // var helper = orm.migrations.helpers.MigrationHelper(orm.sqlite.SQLite).init(db, allocator);
        \\    // try helper.dropTable("table_name");
        \\}
        \\
    ;

    try file.writeAll(template);
    std.debug.print("Created migration: {s}\n", .{filename});

    try updateRegistry(allocator);
}

fn updateRegistry(allocator: std.mem.Allocator) !void {
    var dir = try std.fs.cwd().openDir("migrations", .{ .iterate = true });
    defer dir.close();

    var list = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer {
        for (list.items) |item| allocator.free(item);
        list.deinit(allocator);
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig") and !std.mem.eql(u8, entry.name, "migrations.zig")) {
            try list.append(allocator, try allocator.dupe(u8, entry.name));
        }
    }

    // Sort by name (timestamp prefix)
    std.mem.sort([]const u8, list.items, {}, sortString);

    const reg_file = try std.fs.cwd().createFile("migrations/migrations.zig", .{});
    defer reg_file.close();

    try reg_file.writeAll("const std = @import(\"std\");\n");
    try reg_file.writeAll("const orm = @import(\"zig-orm\");\n\n");

    for (list.items, 0..) |file_name, i| {
        const import_line = try std.fmt.allocPrint(allocator, "const m{d} = @import(\"{s}\");\n", .{ i, file_name });
        defer allocator.free(import_line);
        try reg_file.writeAll(import_line);
    }

    try reg_file.writeAll("\npub const list = [_]orm.migrations.Migration{\n");

    for (list.items, 0..) |file_name, i| {
        // Extract name without extension and timestamp
        const dot_idx = std.mem.lastIndexOf(u8, file_name, ".") orelse file_name.len;
        const name_part = file_name[0..dot_idx];
        const under_idx = std.mem.indexOf(u8, name_part, "_") orelse 0;
        const version_str = if (under_idx > 0) name_part[0..under_idx] else "0";
        const name = if (under_idx > 0) name_part[under_idx + 1 ..] else name_part;

        const list_item = try std.fmt.allocPrint(allocator, "    .{{ .version = {s}, .name = \"{s}\", .up = m{d}.up, .down = m{d}.down }},\n", .{ version_str, name, i, i });
        defer allocator.free(list_item);
        try reg_file.writeAll(list_item);
    }

    try reg_file.writeAll("};\n");
    std.debug.print("Updated migration registry: migrations/migrations.zig\n", .{});
}

fn sortString(context: void, a: []const u8, b: []const u8) bool {
    _ = context;
    return std.mem.lessThan(u8, a, b);
}
