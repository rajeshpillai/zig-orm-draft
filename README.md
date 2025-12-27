# Zig ORM (Design Goals & Principles)

**Status**: Experimental / Pre-alpha

## Core Principles

*   **No runtime reflection**: All schema information must be known at compile time.
*   **Compile-time schema**: DB schema matches Zig structs/declarations exactly.
*   **Zero-cost abstractions**: The abstractions should compile down to what you would hand-write.
*   **Explicit SQL generation**: No "magic" queries. You build a query, it generates a string (or prepared statement).
*   **Driver-agnostic core**: The ORM logic is separate from the DB driver.
*   **Postgres + SQLite adapters**: Initial targets.
*   **Opt-in conveniences**: Not magic.

Think “typed SQL builder + mapper”, not Rails/EF.

## Usage

```zig
const orm = @import("zig-orm");
// ... usage example to be added ...
```
