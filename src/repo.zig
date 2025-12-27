const std = @import("std");

pub fn Repo(comptime Adapter: type) type {
    return struct {
        const Self = @This();

        adapter: Adapter,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, connection_string: [:0]const u8) !Self {
            const adapter = try Adapter.init(connection_string);
            return Self{
                .adapter = adapter,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.adapter.deinit();
        }

        // Placeholder for future execution logic
        // pub fn all(self: *Self, query: anytype) ![]T { ... }
    };
}
