# Zig ORM Architecture

This document describes the design, components, and future roadmap for the Zig ORM project.

## Core Design Philosophy

The Zig ORM is heavily inspired by **Elixir Ecto**. It prioritizes explicit database interactions and leverages Zig's **comptime** capabilities to avoid runtime reflection and overhead.

1.  **Repo Pattern**: All database interactions go through a `Repo`. The `Repo` is decoupled from the SQL builders and the database drivers.
2.  **Comptime Schema**: Tables and column mappings are derived at compile-time from standard Zig structs.
3.  **Data-Centric Builders**: Queries are constructed using functional-style builders (`from`, `where`, `preload`) that return data structures instead of immediately executing SQL.
4.  **Adapter-Based Drivers**: A unified interface (`Adapter`) allows switching between SQLite, PostgreSQL, and other backends without changing business logic.

---

## Component Breakdown

### 1. Adapters (`src/adapters/`)
Adapters provide the low-level bridge to database drivers.
-   **SQLite**: Direct C-bindings to `sqlite3.c` (bundled).
-   **Postgres**: C-bindings to `libpq`.
-   **Common Interface**: Every adapter must implement `init`, `deinit`, `prepare`, `exec`, and bind methods.

### 2. Core Library (`src/core/`)
-   **Schema**: Generic `Table(T, name)` that uses `@typeInfo` to automatically map struct fields to DB columns.
-   **Types**: Maps Zig primitive types (`i64`, `[]const u8`, `bool`) to database-neutral ORM types.
-   **Timestamps**: Cross-platform system time implementation for automatic `created_at` and `updated_at` management.

### 3. Query Builder (`src/builder/`)
-   **DSL-like API**: Supports `from(Table)`, `where(struct)`, `limit(n)`, `offset(n)`, and `preload(assoc)`.
-   **SQL Generation**: Converts query structures into dialect-specific SQL strings.
-   **Parameter Tracking**: Manages the list of values to be bound, ensuring safe parameterization.

### 4. Repository (`src/repo.zig`)
The main entry point for applications.
-   **Mapping**: Converts database result rows back into Zig structs using comptime logic.
-   **Lifecycle**: Triggers automatic validations, timestamping, and **Model Hooks** (`beforeInsert`, `afterUpdate`, etc.) before execution.
-   **Instance Operations**: Support for `updateModel` and `deleteModel` which take model instances.
-   **Transactions**: Provides a clean wrapper around `BEGIN`, `COMMIT`, and `ROLLBACK`.

### 5. Utilities
-   **Connection Pooling**: Generic, thread-safe pool management using Mutexes.
-   **Migrations**: Versioned Up/Down migration runner with persistence in a `schema_migrations` table.
-   **Migration Helpers**: Fluent DSL for schema changes (`createTable`, `addColumn`, `addIndex`).
-   **Validation**: Declarative rules (`rules` decl inside structs) enforced by the Repo.

---

### Technical Features
*   [x] **Core ORM**: `Repo(Adapter)` pattern with `insert`, `update`, `delete`, `all`.
*   [x] **Query Builder**: Fluent interface (`where`, `limit`, `orderBy`, `join`, `groupBy`).
*   [x] **Adapter System**: SQLite (Native/C-ABI) implemented.
*   [x] **Validation**: `Validator` struct with `required`, `length`, `email`, `regex`.
*   [x] **Migrations**: Fluent DSL for schema definition.
*   [x] **CLI Tools**: Automatic registry, migration generator and execution (Core Completed).
*   [x] **Logging**: SQL execution logging with timing.
*   [x] **Optimistic Locking**: Automatic version checking and incrementing.
*   [x] **Connection Pooling**: Generic `Pool(Adapter)` implementation.
*   [x] **Model Generation**: CLI command to inspect DB and generate Zig structs.

---

## Future Feature Roadmap (Suggestions)

The following features would bring the ORM to full production readiness:

### Phase 4: Developer Experience (DX)
-   **CLI Tool**: A standalone binary (e.g., `zig-orm CLI`) for:
    -   Generating new migration files.
    -   Running/rolling back migrations.
    -   Generating boilerplate models from an existing database.
-   **Generic Logger**: A way to plug in custom logging to see generated SQL and execution times.

### Phase 5: Production Hardening
-   **Soft Deletes**: Automatically handling a `deleted_at` field so rows are hidden but not removed.
-   **Optimistic Locking**: Support for a `version` or `lock_version` field to prevent concurrent update conflicts.
-   **Enum Mapping**: Native mapping between Zig `enum` and DB `TEXT` or `INTEGER` types.
-   **Read-Only Replicas**: Support in the Connection Pool for routing SELECTs to replicas and writes to a primary.

---

## Folder Structure

```text
src/
├── adapters/     # DB-specific drivers (sqlite.zig, postgres.zig)
├── builder/      # SQL generation (query.zig, insert.zig, etc.)
├── cli/          # CLI tool implementation (main.zig)
├── core/         # Type systems and metadata (schema.zig, timestamps.zig)
├── migrations/   # Migration runner and logic
├── validation/   # Rule-based validation framework
├── repo.zig      # Central Repository pattern
├── root.zig      # Module entry point
└── pool.zig      # Connection pooling
```
