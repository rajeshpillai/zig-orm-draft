const std = @import("std");

/// Check if a type has timestamp fields (created_at and/or updated_at)
pub fn hasTimestamps(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;

    var has_created = false;
    var has_updated = false;

    inline for (info.@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, "created_at")) has_created = true;
        if (std.mem.eql(u8, field.name, "updated_at")) has_updated = true;
    }

    return has_created or has_updated;
}

/// Check if a type has created_at field
pub fn hasCreatedAt(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;

    inline for (info.@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, "created_at")) return true;
    }
    return false;
}

/// Check if a type has updated_at field
pub fn hasUpdatedAt(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;

    inline for (info.@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, "updated_at")) return true;
    }
    return false;
}

/// Get current Unix timestamp in seconds
pub fn currentTimestamp() i64 {
    const builtin = @import("builtin");
    if (builtin.os.tag == .windows) {
        const kernel32 = struct {
            extern "kernel32" fn GetSystemTimeAsFileTime(lpSystemTimeAsFileTime: *FILETIME) callconv(.winapi) void;
            const FILETIME = struct {
                dwLowDateTime: u32,
                dwHighDateTime: u32,
            };
        };
        var ft: kernel32.FILETIME = undefined;
        kernel32.GetSystemTimeAsFileTime(&ft);
        const file_time = (@as(u64, ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
        // 116444736000000000 is the number of 100ns intervals between 1601-01-01 and 1970-01-01
        // We use the constant from std.time.epoch.windows if possible, but manual is safer here
        return @intCast(@divFloor(file_time - 116444736000000000, 10000000));
    } else {
        const c = struct {
            extern "c" fn clock_gettime(clk_id: i32, tp: *timespec) i32;
            const timespec = struct {
                tv_sec: i64,
                tv_nsec: i64,
            };
        };
        var ts: c.timespec = undefined;
        // 0 is CLOCK_REALTIME on most POSIX systems
        if (c.clock_gettime(0, &ts) == 0) {
            return ts.tv_sec;
        }
        return 0;
    }
}

/// Set created_at field on a struct instance
pub fn setCreatedAt(value: anytype) void {
    const T = @TypeOf(value.*);
    if (!hasCreatedAt(T)) return;

    if (@field(value.*, "created_at") == 0) {
        @field(value.*, "created_at") = currentTimestamp();
    }
}

/// Set updated_at field on a struct instance
pub fn setUpdatedAt(value: anytype) void {
    const T = @TypeOf(value.*);
    if (!hasUpdatedAt(T)) return;

    if (@field(value.*, "updated_at") == 0) {
        @field(value.*, "updated_at") = currentTimestamp();
    }
}

/// Set both created_at and updated_at fields on a struct instance
pub fn setTimestamps(value: anytype) void {
    setCreatedAt(value);
    setUpdatedAt(value);
}

test "hasTimestamps detection" {
    const WithTimestamps = struct {
        id: i64,
        name: []const u8,
        created_at: i64,
        updated_at: i64,
    };

    const WithCreatedAt = struct {
        id: i64,
        created_at: i64,
    };

    const WithUpdatedAt = struct {
        id: i64,
        updated_at: i64,
    };

    const NoTimestamps = struct {
        id: i64,
        name: []const u8,
    };

    try std.testing.expect(hasTimestamps(WithTimestamps));
    try std.testing.expect(hasCreatedAt(WithTimestamps));
    try std.testing.expect(hasUpdatedAt(WithTimestamps));

    try std.testing.expect(hasTimestamps(WithCreatedAt));
    try std.testing.expect(hasCreatedAt(WithCreatedAt));
    try std.testing.expect(!hasUpdatedAt(WithCreatedAt));

    try std.testing.expect(hasTimestamps(WithUpdatedAt));
    try std.testing.expect(!hasCreatedAt(WithUpdatedAt));
    try std.testing.expect(hasUpdatedAt(WithUpdatedAt));

    try std.testing.expect(!hasTimestamps(NoTimestamps));
}

test "setTimestamps functionality" {
    const User = struct {
        id: i64,
        name: []const u8,
        created_at: i64,
        updated_at: i64,
    };

    var user = User{
        .id = 1,
        .name = "Alice",
        .created_at = 0,
        .updated_at = 0,
    };

    setTimestamps(&user);

    try std.testing.expect(user.created_at > 0);
    try std.testing.expect(user.updated_at > 0);
    try std.testing.expectEqual(user.created_at, user.updated_at);
}

test "currentTimestamp returns valid value" {
    const ts = currentTimestamp();
    // Should be a reasonable Unix timestamp (after 2020-01-01)
    try std.testing.expect(ts > 1577836800);
}
