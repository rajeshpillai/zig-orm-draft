const std = @import("std");
const timestamps = @import("../core/timestamps.zig");
pub const helpers = @import("helpers.zig");
const Allocator = std.mem.Allocator;

pub const MigrationFn = *const fn (db: *anyopaque, allocator: Allocator) anyerror!void;

pub const Migration = struct {
    version: i64,
    name: []const u8,
    up: MigrationFn,
    down: MigrationFn,
};

pub fn MigrationRunner(comptime Adapter: type) type {
    return struct {
        const Self = @This();

        adapter: *Adapter,
        allocator: Allocator,
        migrations_table: []const u8 = "schema_migrations",

        pub fn init(adapter: *Adapter, allocator: Allocator) Self {
            return .{
                .adapter = adapter,
                .allocator = allocator,
            };
        }

        pub fn helper(self: *Self) helpers.MigrationHelper(Adapter) {
            return helpers.MigrationHelper(Adapter).init(self.adapter, self.allocator);
        }

        pub fn createMigrationsTable(self: *Self) !void {
            const sql =
                \\CREATE TABLE IF NOT EXISTS schema_migrations (
                \\    version BIGINT PRIMARY KEY,
                \\    name TEXT NOT NULL,
                \\    applied_at BIGINT NOT NULL
                \\)
            ;
            try self.adapter.exec(sql);
        }

        pub fn getCurrentVersion(self: *Self) !?i64 {
            const sql = "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1";
            var stmt = try self.adapter.prepare(sql);
            defer stmt.deinit();

            if (try stmt.step()) {
                return Adapter.column_int(&stmt, 0);
            }
            return null;
        }

        pub fn isApplied(self: *Self, version: i64) !bool {
            const sql = "SELECT 1 FROM schema_migrations WHERE version = ?";
            var stmt = try self.adapter.prepare(sql);
            defer stmt.deinit();

            try stmt.bind_int(0, version);
            return try stmt.step();
        }

        pub fn recordMigration(self: *Self, migration: Migration) !void {
            const sql = "INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, ?)";
            var stmt = try self.adapter.prepare(sql);
            defer stmt.deinit();

            // Use the stable currentTimestamp helper
            try stmt.bind_int(0, migration.version);
            try stmt.bind_text(1, migration.name);
            try stmt.bind_int(2, timestamps.currentTimestamp());
            _ = try stmt.step();
        }

        pub fn removeMigration(self: *Self, version: i64) !void {
            const sql = "DELETE FROM schema_migrations WHERE version = ?";
            var stmt = try self.adapter.prepare(sql);
            defer stmt.deinit();

            try stmt.bind_int(0, version);
            _ = try stmt.step();
        }

        pub fn migrate(self: *Self, migrations: []const Migration) !void {
            try self.createMigrationsTable();

            for (migrations) |migration| {
                if (try self.isApplied(migration.version)) {
                    std.debug.print("Migration {d} ({s}) already applied, skipping\n", .{ migration.version, migration.name });
                    continue;
                }

                std.debug.print("Applying migration {d}: {s}\n", .{ migration.version, migration.name });
                try migration.up(@ptrCast(self.adapter), self.allocator);
                try self.recordMigration(migration);
                std.debug.print("OK: Migration {d} applied\n", .{migration.version});
            }
        }

        pub fn rollback(self: *Self, migrations: []const Migration, steps: usize) !void {
            const current_version = try self.getCurrentVersion() orelse {
                std.debug.print("No migrations to rollback\n", .{});
                return;
            };

            var rolled_back: usize = 0;
            var i: usize = migrations.len;
            while (i > 0 and rolled_back < steps) {
                i -= 1;
                const migration = migrations[i];

                if (migration.version > current_version) continue;
                if (!(try self.isApplied(migration.version))) continue;

                std.debug.print("Rolling back migration {d}: {s}\n", .{ migration.version, migration.name });
                try migration.down(@ptrCast(self.adapter), self.allocator);
                try self.removeMigration(migration.version);
                std.debug.print("OK: Migration {d} rolled back\n", .{migration.version});

                rolled_back += 1;
            }

            if (rolled_back == 0) {
                std.debug.print("No migrations to rollback\n", .{});
            }
        }
    };
}
