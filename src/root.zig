const std = @import("std");

pub const sqlite = @import("adapters/sqlite.zig");
pub const postgres = @import("adapters/postgres.zig");
pub const types = @import("core/types.zig");
pub const schema = @import("core/schema.zig");
pub const query = @import("builder/query.zig");
pub const Repo = @import("repo.zig").Repo;
pub const from = query.from;
pub const Query = query.Query;
pub const Table = schema.Table;
pub const ConnectionPool = @import("pool.zig").ConnectionPool;
pub const migrations = @import("migrations/runner.zig");
pub const validation = @import("validation/validator.zig");

test {
    _ = sqlite;
    _ = types;
    _ = schema;
    _ = query;
    _ = @import("pool.zig");
    _ = @import("validation/validator.zig");
}
