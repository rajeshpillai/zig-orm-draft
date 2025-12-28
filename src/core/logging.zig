const std = @import("std");

pub const LogContext = struct {
    sql: []const u8,
    duration_ns: u64,
};

pub const LogFn = *const fn (context: LogContext) void;
