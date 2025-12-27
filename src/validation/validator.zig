const std = @import("std");

pub const ValidationError = error{
    Required,
    TooShort,
    TooLong,
    InvalidEmail,
    OutOfRange,
    InvalidFormat,
};

/// Validates that a value is not null or empty
pub fn required(value: ?[]const u8) ValidationError![]const u8 {
    if (value) |v| {
        if (v.len == 0) return error.Required;
        return v;
    }
    return error.Required;
}

/// Validates minimum string length
pub fn minLength(value: []const u8, min_len: usize) ValidationError!void {
    if (value.len < min_len) return error.TooShort;
}

/// Validates maximum string length
pub fn maxLength(value: []const u8, max_len: usize) ValidationError!void {
    if (value.len > max_len) return error.TooLong;
}

/// Validates string length is within range
pub fn lengthRange(value: []const u8, min_len: usize, max_len: usize) ValidationError!void {
    try minLength(value, min_len);
    try maxLength(value, max_len);
}

/// Simple email validation (contains @ and .)
pub fn email(value: []const u8) ValidationError!void {
    var has_at = false;
    var has_dot_after_at = false;
    var at_pos: usize = 0;

    for (value, 0..) |c, i| {
        if (c == '@') {
            if (has_at) return error.InvalidEmail; // Multiple @
            has_at = true;
            at_pos = i;
        }
        if (has_at and c == '.' and i > at_pos) {
            has_dot_after_at = true;
        }
    }

    if (!has_at or !has_dot_after_at) return error.InvalidEmail;
    if (at_pos == 0 or at_pos == value.len - 1) return error.InvalidEmail;
}

/// Validates numeric value is within range
pub fn range(value: anytype, min_val: anytype, max_val: anytype) ValidationError!void {
    if (value < min_val or value > max_val) return error.OutOfRange;
}

/// Validates numeric value is greater than or equal to minimum
pub fn min(value: anytype, min_val: anytype) ValidationError!void {
    if (value < min_val) return error.OutOfRange;
}

/// Validates numeric value is less than or equal to maximum
pub fn max(value: anytype, maximum: anytype) ValidationError!void {
    if (value > maximum) return error.OutOfRange;
}

/// Automatically validates a model instance based on its 'rules' declaration
pub fn validate(model: anytype) ValidationError!void {
    const T = if (@typeInfo(@TypeOf(model)) == .pointer) @typeInfo(@TypeOf(model)).pointer.child else @TypeOf(model);
    if (!@hasDecl(T, "rules")) return;

    const rules = T.rules;
    const rules_info = @typeInfo(@TypeOf(rules));
    if (rules_info != .@"struct") @compileError("Rules must be a struct");

    inline for (rules_info.@"struct".fields) |field| {
        const field_rules = @field(rules, field.name);
        const value = @field(model.*, field.name);

        const field_rules_info = @typeInfo(@TypeOf(field_rules));
        inline for (field_rules_info.@"struct".fields) |rule| {
            const rule_val = @field(field_rules, rule.name);

            if (comptime std.mem.eql(u8, rule.name, "required")) {
                if (rule_val) _ = try required(value);
            } else if (comptime std.mem.eql(u8, rule.name, "min_len")) {
                try minLength(value, rule_val);
            } else if (comptime std.mem.eql(u8, rule.name, "max_len")) {
                try maxLength(value, rule_val);
            } else if (comptime std.mem.eql(u8, rule.name, "email")) {
                if (rule_val) try email(value);
            } else if (comptime std.mem.eql(u8, rule.name, "min")) {
                try min(value, rule_val);
            } else if (comptime std.mem.eql(u8, rule.name, "max")) {
                try max(value, rule_val);
            }
        }
    }
}

test "required validator" {
    const valid = try required("hello");
    try std.testing.expectEqualStrings("hello", valid);

    try std.testing.expectError(error.Required, required(null));
    try std.testing.expectError(error.Required, required(""));
}

test "length validators" {
    try minLength("hello", 3);
    try std.testing.expectError(error.TooShort, minLength("hi", 3));

    try maxLength("hello", 10);
    try std.testing.expectError(error.TooLong, maxLength("hello world", 5));

    try lengthRange("hello", 3, 10);
    try std.testing.expectError(error.TooShort, lengthRange("hi", 3, 10));
    try std.testing.expectError(error.TooLong, lengthRange("hello world", 3, 5));
}

test "email validator" {
    try email("user@example.com");
    try email("test.user@domain.co.uk");

    try std.testing.expectError(error.InvalidEmail, email("invalid"));
    try std.testing.expectError(error.InvalidEmail, email("@example.com"));
    try std.testing.expectError(error.InvalidEmail, email("user@"));
    try std.testing.expectError(error.InvalidEmail, email("user@@example.com"));
}

test "range validators" {
    try range(5, 1, 10);
    try std.testing.expectError(error.OutOfRange, range(0, 1, 10));
    try std.testing.expectError(error.OutOfRange, range(11, 1, 10));

    try min(18, 18);
    try min(25, 18);
    try std.testing.expectError(error.OutOfRange, min(17, 18));

    try max(100, 120);
    try max(120, 120);
    try std.testing.expectError(error.OutOfRange, max(121, 120));
}
