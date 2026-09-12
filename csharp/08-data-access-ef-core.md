# Data Access & EF Core

## 1. `DbContext` is scoped, never singleton or static

`DbContext` is not thread-safe and is designed to be short-lived, one instance per unit of
work/request. Registering it as `Singleton`, storing it in a static field, or sharing one
instance across concurrent operations will cause data corruption or exceptions under load.

**Flag:** `AddDbContext` lifetime overridden to `Singleton`; a static field holding a
`DbContext`; a `DbContext` instance captured in a background task that outlives the request
scope it came from.

## 2. Use `AsNoTracking()` for read-only queries

Any query whose results won't be modified and saved back should use `AsNoTracking()` (or
`AsNoTrackingWithIdentityResolution()` when duplicate entity identity resolution is needed).
This avoids the overhead of EF Core's change tracker for data that is never mutated.

```csharp
// Bad - change tracking overhead for a read-only list
var orders = await _db.Orders.Where(o => o.UserId == userId).ToListAsync();

// Good
var orders = await _db.Orders.AsNoTracking()
    .Where(o => o.UserId == userId)
    .ToListAsync();
```

**Flag:** queries feeding read-only views/DTOs/API responses with no `AsNoTracking()`.

## 3. Avoid N+1 queries

Use `.Include()`/`.ThenInclude()` or projection (`.Select()`) to fetch related data in one
query, rather than looping and querying per item.

```csharp
// Bad - one query per order to fetch its items (N+1)
foreach (var order in orders)
{
    order.Items = await _db.OrderItems.Where(i => i.OrderId == order.Id).ToListAsync();
}

// Good - one query total
var orders = await _db.Orders
    .Include(o => o.Items)
    .Where(o => o.UserId == userId)
    .ToListAsync();
```

**Flag:** database queries inside a loop; lazy-loading proxies enabled and relied upon
implicitly in hot paths without awareness of the query cost.

## 4. Project to DTOs instead of loading full entities when possible

If an endpoint only needs a few fields, `.Select()` into a DTO/projection rather than loading
the full entity graph. This reduces data transferred from the database and avoids unnecessary
tracking.

```csharp
var summaries = await _db.Orders
    .Where(o => o.UserId == userId)
    .Select(o => new OrderSummary(o.Id, o.Total, o.CreatedAt))
    .ToListAsync();
```

**Flag:** an endpoint that loads full entities (with all columns and included relations) only
to expose 2-3 fields in the response.

## 5. Don't expose `IQueryable<T>` outside the data-access layer

Returning `IQueryable<T>` from a repository leaks the ability for callers to compose arbitrary,
untracked-by-the-team queries against the database from anywhere in the codebase, and makes it
hard to reason about what queries actually run. Repositories should return materialized
results (`IReadOnlyList<T>`, a single entity, etc.) or accept explicit query parameters.

**Flag:** a repository/service interface with a method returning `IQueryable<T>` consumed by
callers outside the data-access layer.

## 6. Keep entity classes focused on state and simple invariants

Entities may contain simple, self-contained business rules (e.g., a method that enforces an
invariant about their own state), but should not depend on external services, call the
database, or contain orchestration logic that belongs in an application service.

**Flag:** entity classes with injected dependencies, static service-locator calls, or methods
that perform I/O.

## 7. Use migrations, never hand-edit the schema

All schema changes go through EF Core migrations (or an equivalent versioned migration tool)
checked into source control. Don't apply ad hoc `ALTER TABLE` statements directly against a
shared database.

**Flag:** raw SQL DDL scripts outside the migrations folder; a migration that has been edited
after being applied to any shared environment instead of being superseded by a new migration.

## 8. Use `ExecuteUpdate`/`ExecuteDelete` for bulk operations

For simple bulk field updates or deletes that don't need per-row business logic, use EF Core's
`ExecuteUpdateAsync`/`ExecuteDeleteAsync` instead of loading every row into memory just to
change one field and save it back.

```csharp
// Bad - loads every matching row into memory to change one field
var orders = await _db.Orders.Where(o => o.Status == "Pending").ToListAsync();
foreach (var o in orders) o.Status = "Cancelled";
await _db.SaveChangesAsync();

// Good
await _db.Orders
    .Where(o => o.Status == "Pending")
    .ExecuteUpdateAsync(setters => setters.SetProperty(o => o.Status, "Cancelled"));
```

**Flag:** load-all-then-loop-and-save patterns for bulk updates/deletes with no per-row logic.

## 9. Wrap multi-step writes in a transaction

If a unit of work involves multiple `SaveChangesAsync` calls or multiple related writes that
must succeed or fail together, wrap them in an explicit transaction
(`_db.Database.BeginTransactionAsync()` or `IDbContextTransaction`), or restructure so a single
`SaveChangesAsync` covers all of them (EF Core already wraps one `SaveChangesAsync` call in an
implicit transaction).

**Flag:** multiple sequential `SaveChangesAsync()` calls representing one logical operation
with no surrounding transaction and no compensating rollback logic.
