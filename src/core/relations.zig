const std = @import("std");

/// Metadata for belongs_to relationship
/// Example: Post belongs_to User via user_id
pub fn BelongsTo(comptime Parent: type, comptime fk_field: []const u8) type {
    return struct {
        pub const RelatedTable = Parent;
        pub const foreign_key = fk_field;
    };
}

/// Metadata for has_one relationship
/// Example: User has_one Profile via user_id in profiles table
pub fn HasOne(comptime Child: type, comptime fk_field: []const u8) type {
    return struct {
        pub const RelatedTable = Child;
        pub const foreign_key_field = fk_field;
    };
}

/// Metadata for has_many relationship
/// Example: User has_many Posts via user_id in posts table
pub fn HasMany(comptime Child: type, comptime fk_field: []const u8) type {
    return struct {
        pub const RelatedTable = Child;
        pub const foreign_key_field = fk_field;
    };
}

test "relation metadata" {
    const User = struct { id: i64, name: []const u8 };
    const Profile = struct { id: i64, user_id: i64, bio: []const u8 };

    const ProfileBelongsToUser = BelongsTo(User, "user_id");
    const UserHasOneProfile = HasOne(Profile, "user_id");

    try std.testing.expectEqual(User, ProfileBelongsToUser.RelatedTable);
    try std.testing.expectEqualStrings("user_id", ProfileBelongsToUser.foreign_key);

    try std.testing.expectEqual(Profile, UserHasOneProfile.RelatedTable);
    try std.testing.expectEqualStrings("user_id", UserHasOneProfile.foreign_key_field);
}
