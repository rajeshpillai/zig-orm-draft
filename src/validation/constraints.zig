const std = @import("std");
const schema = @import("../core/schema.zig");
const validation = @import("validator.zig");

/// Validates constraints defined in model schema
pub fn validateConstraints(
    comptime T: type,
    repo: anytype,
    model: *const T,
) !void {
    if (!@hasDecl(T, "constraints")) return;

    const constraints = T.constraints;
    inline for (constraints) |constraint| {
        switch (constraint) {
            .unique => |unique| try validateUnique(T, repo, model, unique),
            .check => |check| try validateCheck(T, model, check),
            .foreign_key => {}, // TODO: Implement in Phase 4
        }
    }
}

/// Validates unique constraint by checking database for existing records
fn validateUnique(
    comptime T: type,
    repo: anytype,
    model: *const T,
    comptime unique: schema.Constraint.UniqueConstraint,
) !void {
    _ = repo; // TODO: Use repo to query database in actual implementation

    // Build a query to check if a record with the same unique field values exists
    // For now, we'll do a simple implementation for single-field unique constraints

    if (unique.fields.len == 0) return;

    // For single field unique constraint
    if (unique.fields.len == 1) {
        const field_name = unique.fields[0];
        const field_value = @field(model.*, field_name);

        // Check if a record with this value already exists
        // This is a simplified check - in real implementation, we'd need to:
        // 1. Build a proper query
        // 2. Exclude the current record if updating (check for id)
        // 3. Handle different field types properly

        // For now, return UniqueViolation if we detect a duplicate
        // The actual database will also enforce this, but this gives better errors
        _ = field_value; // Use the value in actual query

        // TODO: Implement actual database query
        // const existing = try repo.findBy(T, .{ field_name = field_value });
        // if (existing != null) return error.UniqueViolation;
    }

    // For composite unique constraints (multiple fields)
    if (unique.fields.len > 1) {
        // TODO: Build query with multiple WHERE conditions
        // For now, skip composite unique validation
    }
}

/// Validates check constraint
fn validateCheck(
    comptime T: type,
    model: *const T,
    check: schema.Constraint.CheckConstraint,
) !void {
    const field_value = @field(model.*, check.field);

    // Parse and evaluate the condition
    // For now, we support simple conditions like "age >= 18"
    // TODO: Implement a simple expression parser

    _ = field_value;
    _ = check.condition;

    // Placeholder - actual implementation would parse and evaluate the condition
    // if (!evaluateCondition(field_value, check.condition)) {
    //     return error.CheckViolation;
    // }
}

test "validate constraints - no constraints" {
    const User = struct {
        id: i64,
        name: []const u8,
    };

    const user = User{ .id = 1, .name = "Test" };

    // Should not error when no constraints defined
    const MockRepo = struct {};
    const mock_repo = MockRepo{};
    try validateConstraints(User, mock_repo, &user);
}

test "validate constraints - with unique constraint" {
    const User = struct {
        id: i64,
        email: []const u8,

        pub const constraints = [_]schema.Constraint{
            .{ .unique = .{ .fields = &[_][]const u8{"email"} } },
        };
    };

    const user = User{ .id = 1, .email = "test@example.com" };

    const MockRepo = struct {};
    const mock_repo = MockRepo{};

    // Should not error (actual database check not implemented yet)
    try validateConstraints(User, mock_repo, &user);
}

test "validate constraints - composite unique" {
    const Post = struct {
        id: i64,
        user_id: i64,
        slug: []const u8,

        pub const constraints = [_]schema.Constraint{
            .{ .unique = .{
                .fields = &[_][]const u8{ "user_id", "slug" },
                .name = "unique_user_slug",
            } },
        };
    };

    const post = Post{ .id = 1, .user_id = 123, .slug = "my-post" };

    const MockRepo = struct {};
    const mock_repo = MockRepo{};

    try validateConstraints(Post, mock_repo, &post);
}
