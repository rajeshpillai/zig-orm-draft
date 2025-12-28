const std = @import("std");

pub fn hasHook(comptime T: type, comptime name: []const u8) bool {
    if (!@hasDecl(T, name)) return false;
    // Basic check if it's a function, could be more strict on signature
    return true;
}

pub fn callHook(item: anytype, comptime name: []const u8) !void {
    const T = if (@typeInfo(@TypeOf(item)) == .pointer) @typeInfo(@TypeOf(item)).pointer.child else @TypeOf(item);
    if (comptime hasHook(T, name)) {
        if (@typeInfo(@TypeOf(item)) == .pointer) {
            try @field(T, name)(item);
        } else {
            var mutable = item;
            try @field(T, name)(&mutable);
        }
    }
}
