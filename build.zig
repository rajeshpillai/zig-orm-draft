const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Expose the library module
    const mod = b.addModule("zig-orm", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addCSourceFile(.{
        .file = b.path("src/c/sqlite3.c"),
        .flags = &.{},
    });
    mod.addIncludePath(b.path("src/c"));

    // CLI executable
    const exe = b.addExecutable(.{
        .name = "zig-orm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("zig-orm", mod);

    // Build options for CLI
    const options = b.addOptions();
    var has_migrations = false;

    // Conditionally add migrations if they exist
    if (b.build_root.handle.access("migrations/migrations.zig", .{})) |_| {
        has_migrations = true;
        const migrations_mod = b.createModule(.{
            .root_source_file = b.path("migrations/migrations.zig"),
        });
        migrations_mod.addImport("zig-orm", mod);
        exe.root_module.addImport("migrations", migrations_mod);
    } else |_| {}

    options.addOption(bool, "has_migrations", has_migrations);
    exe.root_module.addOptions("build_options", options);

    exe.linkLibC();
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the CLI");
    run_step.dependOn(&run_cmd.step);

    // PostgreSQL support (libpq)
    // Note: Requires PostgreSQL to be installed
    // Windows: D:\Program Files\PostgreSQL\18\
    if (target.result.os.tag == .windows) {
        mod.addIncludePath(.{ .cwd_relative = "D:/Program Files/PostgreSQL/18/include" });
        mod.addLibraryPath(.{ .cwd_relative = "D:/Program Files/PostgreSQL/18/lib" });
        mod.linkSystemLibrary("libpq", .{});
    } else if (target.result.os.tag == .linux) {
        mod.linkSystemLibrary("pq", .{});
    } else if (target.result.os.tag == .macos) {
        mod.linkSystemLibrary("pq", .{});
    }

    // Library tests
    const lib_unit_tests = b.addTest(.{
        .root_module = mod,
    });
    lib_unit_tests.linkLibC();

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Integration tests
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("integration_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link expected modules
    integration_tests.root_module.addImport("zig-orm", mod);
    // Needed to call sqlite functions from integration test? No, it imports module which has sqlite.
    // However, if the module has C sources, does the consumer get them? Yes.
    integration_tests.linkLibC();

    const run_integration_tests = b.addRunArtifact(integration_tests);
    test_step.dependOn(&run_integration_tests.step);

    // Relations tests
    const relations_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/sqlite/relations_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    relations_tests.root_module.addImport("zig-orm", mod);
    relations_tests.linkLibC();

    const run_relations_tests = b.addRunArtifact(relations_tests);
    test_step.dependOn(&run_relations_tests.step);

    // Preload tests
    const preload_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/sqlite/preload_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    preload_tests.root_module.addImport("zig-orm", mod);
    preload_tests.linkLibC();

    const run_preload_tests = b.addRunArtifact(preload_tests);
    test_step.dependOn(&run_preload_tests.step);

    // Many-to-Many tests
    const m2m_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/sqlite/many_to_many_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    m2m_tests.root_module.addImport("zig-orm", mod);
    m2m_tests.linkLibC();

    const run_m2m_tests = b.addRunArtifact(m2m_tests);
    test_step.dependOn(&run_m2m_tests.step);

    // PostgreSQL tests (optional - requires PostgreSQL installation)
    const postgres_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/pg/postgres_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    postgres_tests.root_module.addImport("zig-orm", mod);
    postgres_tests.linkLibC();

    const run_postgres_tests = b.addRunArtifact(postgres_tests);
    test_step.dependOn(&run_postgres_tests.step);

    // Migrations tests
    const migrations_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/sqlite/migrations_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    migrations_tests.root_module.addImport("zig-orm", mod);
    migrations_tests.linkLibC();

    const run_migrations_tests = b.addRunArtifact(migrations_tests);
    test_step.dependOn(&run_migrations_tests.step);

    // Validation tests
    const validation_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/sqlite/validation_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    validation_tests.root_module.addImport("zig-orm", mod);
    validation_tests.linkLibC();

    const run_validation_tests = b.addRunArtifact(validation_tests);
    test_step.dependOn(&run_validation_tests.step);

    // Timestamp tests
    const timestamp_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/sqlite/timestamp_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    timestamp_tests.root_module.addImport("zig-orm", mod);
    timestamp_tests.linkLibC();

    const run_timestamp_tests = b.addRunArtifact(timestamp_tests);
    test_step.dependOn(&run_timestamp_tests.step);

    // Raw SQL tests
    const raw_sql_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/sqlite/raw_sql_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    raw_sql_tests.root_module.addImport("zig-orm", mod);
    raw_sql_tests.linkLibC();

    const run_raw_sql_tests = b.addRunArtifact(raw_sql_tests);
    test_step.dependOn(&run_raw_sql_tests.step);

    // Query builder tests
    const query_builder_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/core/query_builder_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    query_builder_tests.root_module.addImport("zig-orm", mod);
    query_builder_tests.linkLibC();

    const run_query_builder_tests = b.addRunArtifact(query_builder_tests);
    test_step.dependOn(&run_query_builder_tests.step);

    // Migration Helpers tests
    const migration_helpers_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/sqlite/migration_helpers_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    migration_helpers_tests.root_module.addImport("zig-orm", mod);
    migration_helpers_tests.linkLibC();

    const run_migration_helpers_tests = b.addRunArtifact(migration_helpers_tests);
    test_step.dependOn(&run_migration_helpers_tests.step);

    // Logging tests
    const logging_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/sqlite/logging_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    logging_test.root_module.addImport("zig-orm", mod);
    logging_test.linkLibC();
    const run_logging_test = b.addRunArtifact(logging_test);
    test_step.dependOn(&run_logging_test.step);

    // Locking tests
    const locking_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/sqlite/locking_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    locking_test.root_module.addImport("zig-orm", mod);
    locking_test.linkLibC();
    const run_locking_test = b.addRunArtifact(locking_test);
    test_step.dependOn(&run_locking_test.step);

    // Postgres Locking tests
    const pg_locking_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/pg/postgres_locking_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pg_locking_test.root_module.addImport("zig-orm", mod);
    pg_locking_test.linkLibC();
    const run_pg_locking_test = b.addRunArtifact(pg_locking_test);
    test_step.dependOn(&run_pg_locking_test.step);

    // Model Hooks tests
    const hooks_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/sqlite/hooks_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    hooks_tests.root_module.addImport("zig-orm", mod);
    hooks_tests.linkLibC();

    const run_hooks_tests = b.addRunArtifact(hooks_tests);
    test_step.dependOn(&run_hooks_tests.step);

    // Aggregates tests
    const aggregates_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/sqlite/aggregates_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    aggregates_tests.root_module.addImport("zig-orm", mod);
    aggregates_tests.linkLibC();

    const run_aggregates_tests = b.addRunArtifact(aggregates_tests);
    test_step.dependOn(&run_aggregates_tests.step);

    // Joins tests
    const joins_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests/sqlite/joins_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    joins_tests.root_module.addImport("zig-orm", mod);
    joins_tests.linkLibC();

    const run_joins_tests = b.addRunArtifact(joins_tests);
    test_step.dependOn(&run_joins_tests.step);
}
