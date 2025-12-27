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
            .root_source_file = b.path("test/relations_test.zig"),
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
            .root_source_file = b.path("test/preload_test.zig"),
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
            .root_source_file = b.path("test/many_to_many_test.zig"),
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
            .root_source_file = b.path("test/postgres_test.zig"),
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
            .root_source_file = b.path("test/migrations_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    migrations_tests.root_module.addImport("zig-orm", mod);
    migrations_tests.linkLibC();

    const run_migrations_tests = b.addRunArtifact(migrations_tests);
    test_step.dependOn(&run_migrations_tests.step);
}
