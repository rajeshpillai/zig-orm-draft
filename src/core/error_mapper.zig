const std = @import("std");
const validation = @import("../validation/validator.zig");

/// Maps database-specific errors to typed constraint errors
pub const ErrorMapper = struct {
    /// Map SQLite error to ValidationError
    pub fn mapSQLiteError(err: anytype) ?validation.ValidationError {
        // SQLite error codes for constraints:
        // SQLITE_CONSTRAINT = 19
        // SQLITE_CONSTRAINT_UNIQUE = 2067
        // SQLITE_CONSTRAINT_FOREIGNKEY = 787
        // SQLITE_CONSTRAINT_CHECK = 275
        // SQLITE_CONSTRAINT_NOTNULL = 1299

        const err_name = @errorName(err);

        // Check for constraint violations
        if (std.mem.indexOf(u8, err_name, "UNIQUE") != null or
            std.mem.indexOf(u8, err_name, "Unique") != null)
        {
            return error.UniqueViolation;
        }

        if (std.mem.indexOf(u8, err_name, "FOREIGN") != null or
            std.mem.indexOf(u8, err_name, "ForeignKey") != null)
        {
            return error.ForeignKeyViolation;
        }

        if (std.mem.indexOf(u8, err_name, "CHECK") != null or
            std.mem.indexOf(u8, err_name, "Check") != null)
        {
            return error.CheckViolation;
        }

        if (std.mem.indexOf(u8, err_name, "NOT NULL") != null or
            std.mem.indexOf(u8, err_name, "NotNull") != null)
        {
            return error.NotNullViolation;
        }

        return null; // Not a constraint error
    }

    /// Map PostgreSQL error to ValidationError
    pub fn mapPostgreSQLError(err: anytype) ?validation.ValidationError {
        // PostgreSQL SQLSTATE codes:
        // 23505 = unique_violation
        // 23503 = foreign_key_violation
        // 23514 = check_violation
        // 23502 = not_null_violation

        const err_name = @errorName(err);

        // Check for constraint violations
        if (std.mem.indexOf(u8, err_name, "unique") != null or
            std.mem.indexOf(u8, err_name, "Unique") != null or
            std.mem.indexOf(u8, err_name, "23505") != null)
        {
            return error.UniqueViolation;
        }

        if (std.mem.indexOf(u8, err_name, "foreign") != null or
            std.mem.indexOf(u8, err_name, "Foreign") != null or
            std.mem.indexOf(u8, err_name, "23503") != null)
        {
            return error.ForeignKeyViolation;
        }

        if (std.mem.indexOf(u8, err_name, "check") != null or
            std.mem.indexOf(u8, err_name, "Check") != null or
            std.mem.indexOf(u8, err_name, "23514") != null)
        {
            return error.CheckViolation;
        }

        if (std.mem.indexOf(u8, err_name, "not_null") != null or
            std.mem.indexOf(u8, err_name, "NotNull") != null or
            std.mem.indexOf(u8, err_name, "23502") != null)
        {
            return error.NotNullViolation;
        }

        return null; // Not a constraint error
    }
};

test "map SQLite unique violation" {
    // Simulate a unique constraint error
    const err = error.SQLiteConstraintUnique;
    const mapped = ErrorMapper.mapSQLiteError(err);

    if (mapped) |m| {
        try std.testing.expectEqual(validation.ValidationError.UniqueViolation, m);
    }
}

test "map PostgreSQL unique violation" {
    // Simulate a PostgreSQL unique violation
    const err = error.PostgreSQLUniqueViolation;
    const mapped = ErrorMapper.mapPostgreSQLError(err);

    if (mapped) |m| {
        try std.testing.expectEqual(validation.ValidationError.UniqueViolation, m);
    }
}
