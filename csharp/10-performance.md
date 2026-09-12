# Performance

## 1. Measure before optimizing

Don't restructure clear, correct code for performance without a measured reason (a profiler
result, a benchmark, a known hot path). Premature micro-optimization that sacrifices
readability for an unmeasured gain is a net loss.

**Flag:** performance-motivated code changes (manual loops replacing LINQ, `Span<T>`
rewrites, caching) introduced without any stated measurement or clearly hot code path
justifying it.

## 2. Avoid unnecessary allocations in hot paths

Be deliberate about allocations inside loops or frequently-called code: repeated string
concatenation, unnecessary LINQ intermediate collections, boxing of value types, and
repeatedly re-serializing the same data are common sources of avoidable pressure on the
garbage collector.

```csharp
// Bad - quadratic string rebuilding in a loop
var result = "";
foreach (var item in items) result += item.Name + ", ";

// Good
var sb = new StringBuilder();
foreach (var item in items) sb.Append(item.Name).Append(", ");
```

**Flag:** string concatenation (`+=`) inside a loop; `.ToList()`/`.ToArray()` materialization
chained multiple times in a row purely to satisfy LINQ syntax rather than necessity.

## 3. Don't fetch more data than you need

Push filtering, projection, and pagination down to the database query rather than loading
everything into memory and then filtering/paging in code.

```csharp
// Bad - loads the entire table into memory, then filters
var orders = (await _db.Orders.ToListAsync()).Where(o => o.UserId == userId).ToList();

// Good - filtering happens in the database
var orders = await _db.Orders.Where(o => o.UserId == userId).ToListAsync();
```

**Flag:** `.Where()`/`.Take()`/`.Skip()` applied to an already-materialized in-memory
collection when it could instead be part of the database query (`IQueryable`).

## 4. Cache deliberately, with a clear invalidation story

Caching (in-memory, distributed, HTTP response caching) is appropriate for expensive,
frequently-requested, and either immutable or tolerant-of-staleness data. Every cache needs an
explicit expiration policy or invalidation trigger; a cache that never expires and never gets
invalidated on writes will silently serve stale data.

**Flag:** caching added with no expiration/invalidation strategy at all; a cache used for data
that must always be strictly current (e.g., account balances, permission checks) without a
justified staleness tolerance.

## 5. Avoid sync-over-async and thread-pool starvation

See [04-async-and-concurrency.md](./04-async-and-concurrency.md). Blocking on async I/O ties
up thread-pool threads and directly hurts throughput under load.

## 6. Use streaming APIs for large payloads

For large request/response bodies, file uploads/downloads, or large query results, stream
data (`IAsyncEnumerable<T>`, `Stream`-based APIs) rather than buffering the entire payload in
memory.

**Flag:** an endpoint reading an entire large file/upload into a `byte[]`/`MemoryStream`
before it needs to be fully materialized; large query results forced into a single in-memory
`List<T>` when the consumer only needs to iterate once.

## 7. Reuse `HttpClient` via `IHttpClientFactory`

Never `new HttpClient()` per request/call - this can exhaust sockets under load due to how
`HttpClient`'s underlying handler manages connections. Use `IHttpClientFactory` (typed clients
or named clients) which manages handler lifetime correctly.

```csharp
// Bad
public async Task CallApiAsync() { using var client = new HttpClient(); ... }

// Good
public class MyApiClient(HttpClient httpClient) { ... } // registered via AddHttpClient<MyApiClient>()
```

**Flag:** `new HttpClient()` instantiated per method call or per request instead of coming
from `IHttpClientFactory`/a registered typed client.

## 8. Be cautious with reflection in hot paths

Reflection-heavy code (`Activator.CreateInstance`, `PropertyInfo.GetValue` in loops) is
significantly slower than direct calls. Cache reflection results (delegates, compiled
expressions) if reflection is unavoidable in a hot path, or avoid it entirely with a
source-generated or explicit alternative.

**Flag:** reflection calls repeated inside a loop or per-request instead of being computed
once and cached/reused.
