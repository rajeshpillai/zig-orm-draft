const std = @import("std");
const orm = @import("zig-orm");

const m0 = @import("1766914842_test_inspect.zig");
const m1 = @import("1766915492_create_users.zig");
const m2 = @import("1766915503_create_posts.zig");
const m3 = @import("1766915513_create_comments.zig");
const m4 = @import("1766915522_create_tags.zig");

pub const list = [_]orm.migrations.Migration{
    .{ .version = 1766914842, .name = "test_inspect", .up = m0.up, .down = m0.down },
    .{ .version = 1766915492, .name = "create_users", .up = m1.up, .down = m1.down },
    .{ .version = 1766915503, .name = "create_posts", .up = m2.up, .down = m2.down },
    .{ .version = 1766915513, .name = "create_comments", .up = m3.up, .down = m3.down },
    .{ .version = 1766915522, .name = "create_tags", .up = m4.up, .down = m4.down },
};
