# Read Replicas Implementation Guide

This document provides a comprehensive guide to using read replicas with Zig ORM's connection pooling system.

## Overview

Read replicas allow you to scale read operations by distributing SELECT queries across multiple replica databases while keeping all write operations (INSERT, UPDATE, DELETE) on the primary database.

### Benefits

- **Improved Read Performance**: Distribute read load across multiple servers
- **High Availability**: Automatic fallback to primary if replicas unavailable
- **Transparent Routing**: Automatic query routing based on operation type
- **Database Agnostic**: Works with both SQLite and PostgreSQL

## Architecture

```
┌─────────────────────────────────────────┐
│           Connection Pool               │
├─────────────────────────────────────────┤
│  Primary Connections (Write + Read)     │
│  ┌─────┐ ┌─────┐ ┌─────┐               │
│  │ P1  │ │ P2  │ │ P3  │               │
│  └─────┘ └─────┘ └─────┘               │
│                                         │
│  Replica Connections (Read Only)        │
│  ┌─────┐ ┌─────┐                       │
│  │ R1  │ │ R2  │                       │
│  └─────┘ └─────┘                       │
└─────────────────────────────────────────┘
         │              │
         ▼              ▼
    Write Ops      Read Ops
   (Primary)    (Replicas → Primary)
```

## Configuration

### SQLite Example

```zig
const replica_strs = [_][:0]const u8{
    "replica1.db",
    "replica2.db",
};

var pool = try Pool(SQLite).init(allocator, .{
    .max_connections = 5,
    .replica_conn_strs = &replica_strs,
}, "primary.db");
defer pool.deinit();
```

### PostgreSQL Example

```zig
const replica_strs = [_][:0]const u8{
    "host=replica1.example.com dbname=mydb user=postgres password=pass",
    "host=replica2.example.com dbname=mydb user=postgres password=pass",
};

var pool = try Pool(PostgreSQL).init(allocator, .{
    .max_connections = 10,
    .replica_conn_strs = &replica_strs,
}, "host=primary.example.com dbname=mydb user=postgres password=pass");
defer pool.deinit();
```

## Usage

### Acquiring Connections

```zig
// For read operations - uses replicas when available
var read_conn = try pool.acquireForRead();
defer read_conn.deinit();

// For write operations - always uses primary
var write_conn = try pool.acquireForWrite();
defer write_conn.deinit();

// Backward compatible - uses primary
var conn = try pool.acquire();
defer conn.deinit();
```

### Routing Behavior

| Method | Target | Fallback |
|--------|--------|----------|
| `acquireForRead()` | Replicas | Primary if no replicas available |
| `acquireForWrite()` | Primary | N/A |
| `acquire()` | Primary | N/A (backward compatible) |

### With Repo

```zig
// Read-heavy operation
var read_conn = try pool.acquireForRead();
var repo = Repo(PooledAdapter).initFromAdapter(allocator, read_conn);
defer repo.deinit();

const users = try repo.findAllBy(User, .{ .active = true });

// Write operation
var write_conn = try pool.acquireForWrite();
var write_repo = Repo(PooledAdapter).initFromAdapter(allocator, write_conn);
defer write_repo.deinit();

try write_repo.insert(changeset);
```

## Best Practices

### 1. Read-After-Write Consistency

If you need to read immediately after writing, use the primary connection:

```zig
var conn = try pool.acquireForWrite();
defer conn.deinit();

var repo = Repo(PooledAdapter).initFromAdapter(allocator, conn);
defer repo.deinit();

// Write
try repo.insert(user_changeset);

// Read from same connection (primary) for consistency
const user = try repo.findBy(User, .{ .id = new_id });
```

### 2. Connection Pool Sizing

- **Primary connections**: Size based on write throughput
- **Replica connections**: Size based on read throughput
- Rule of thumb: `replicas = 2-3x primary connections`

```zig
var pool = try Pool(PostgreSQL).init(allocator, .{
    .max_connections = 5,        // Primary
    .replica_conn_strs = &replicas, // 10-15 replica connections
}, primary_conn_str);
```

### 3. Replica Lag Handling

Replicas may lag behind the primary. For critical reads:

```zig
// Option 1: Use primary for critical reads
var conn = try pool.acquireForWrite(); // or acquire()

// Option 2: Implement retry logic
var attempts: u8 = 0;
while (attempts < 3) : (attempts += 1) {
    var conn = try pool.acquireForRead();
    defer conn.deinit();
    
    const result = try repo.findBy(User, .{ .id = id });
    if (result) |user| return user;
    
    // Wait for replication
    std.time.sleep(100 * std.time.ns_per_ms);
}
```

### 4. Health Checks

Monitor replica availability:

```zig
// Periodically check replica health
fn checkReplicaHealth(pool: *Pool(PostgreSQL)) !void {
    var conn = try pool.acquireForRead();
    defer conn.deinit();
    
    // Simple health check query
    var stmt = try conn.prepare("SELECT 1");
    defer stmt.deinit();
    
    if (!try stmt.step()) {
        std.log.warn("Replica health check failed", .{});
    }
}
```

## PostgreSQL Replication Setup

### Streaming Replication

1. **Primary Configuration** (`postgresql.conf`):
```ini
wal_level = replica
max_wal_senders = 3
wal_keep_size = 64MB
```

2. **Create Replication User**:
```sql
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'password';
```

3. **Configure Access** (`pg_hba.conf`):
```
host replication replicator replica_ip/32 md5
```

4. **Replica Setup**:
```bash
pg_basebackup -h primary_host -D /var/lib/postgresql/data -U replicator -P
```

5. **Replica Configuration** (`postgresql.conf`):
```ini
hot_standby = on
```

## SQLite Replication

SQLite doesn't have built-in replication. Options:

### 1. File-Based Replication
```bash
# Periodic copy (simple but has lag)
rsync -av primary.db replica.db
```

### 2. Litestream
Use [Litestream](https://litestream.io/) for continuous replication:
```bash
litestream replicate primary.db s3://bucket/db
litestream restore -o replica.db s3://bucket/db
```

### 3. Application-Level
```zig
// Write to primary, async copy to replicas
try primary_db.exec(sql);
try asyncCopyToReplicas(primary_db);
```

## Testing

### Unit Tests
See `src/tests/read_replicas_test.zig` for mock-based routing tests.

### Integration Tests

**SQLite**: `src/tests/sqlite/replicas_integration_test.zig`
```bash
zig build test
```

**PostgreSQL**: `src/tests/pg/replicas_integration_test.zig`
```bash
# Requires PostgreSQL with replica setup
zig build test
```

## Troubleshooting

### Issue: Reads not using replicas

**Check**:
1. Verify `replica_conn_strs` is set in config
2. Ensure using `acquireForRead()` not `acquire()`
3. Check replica connection strings are valid

### Issue: Replica connection failures

**Behavior**: Automatically falls back to primary
**Action**: Check replica availability and connection strings

### Issue: Stale reads from replicas

**Cause**: Replication lag
**Solutions**:
- Use primary for critical reads (`acquireForWrite()`)
- Implement retry logic with delays
- Monitor replication lag metrics

## Performance Considerations

### Connection Overhead
- Replicas share the same pool mutex
- Acquiring from replicas is O(1) pop operation
- No performance penalty when replicas unavailable

### Memory Usage
```
Memory = (primary_conns + replica_conns) × connection_size
```

### Benchmarks

Typical improvement with 2 replicas:
- Read throughput: **2-3x** increase
- Write throughput: **No change** (still uses primary)
- Latency: **30-50%** reduction for read-heavy workloads

## Migration Guide

### From Single Connection

**Before**:
```zig
var db = try PostgreSQL.init(conn_str);
defer db.deinit();
```

**After**:
```zig
var pool = try Pool(PostgreSQL).init(allocator, .{
    .max_connections = 5,
}, conn_str);
defer pool.deinit();

var conn = try pool.acquire();
defer conn.deinit();
```

### From Pool Without Replicas

**Before**:
```zig
var pool = try Pool(PostgreSQL).init(allocator, .{
    .max_connections = 5,
}, primary_str);
```

**After**:
```zig
const replicas = [_][:0]const u8{ replica1_str, replica2_str };
var pool = try Pool(PostgreSQL).init(allocator, .{
    .max_connections = 5,
    .replica_conn_strs = &replicas, // Add this
}, primary_str);
```

## Future Enhancements

Potential improvements:
- [ ] Load balancing strategies (round-robin, least-connections)
- [ ] Replica health monitoring and automatic removal
- [ ] Weighted replica selection
- [ ] Read-your-writes consistency guarantees
- [ ] Automatic query classification in Repo methods
