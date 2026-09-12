# Async & Concurrency

## 1. Async all the way down - never block on async code

Never call `.Result`, `.Wait()`, or `.GetAwaiter().GetResult()` on a `Task` from what should be
synchronous code to "make it work." This is a common source of deadlocks and thread-pool
starvation.

```csharp
// Bad - can deadlock, blocks a thread-pool thread waiting on itself
var user = _userService.GetUserAsync(id).Result;

// Good
var user = await _userService.GetUserAsync(id);
```

**Flag:** any `.Result`, `.Wait()`, `.GetAwaiter().GetResult()` on a `Task`/`Task<T>` outside
of `Main` in a console app or genuinely justified low-level interop code (with a comment
explaining why).

## 2. Never use `async void` except for true event handlers

`async void` methods can't be awaited and their exceptions can't be caught by the caller -
they crash the process (or vanish) instead. The only legitimate use is a UI event handler
signature that requires `void`.

```csharp
// Bad
public async void ProcessOrder(Order order) { ... }

// Good
public async Task ProcessOrderAsync(Order order) { ... }
```

**Flag:** `async void` on anything other than an event handler; missing `Async` suffix on
async method names.

## 3. Accept and honor `CancellationToken`

Any async method that can be long-running (I/O, HTTP, DB) should accept a `CancellationToken`
parameter (default `= default` at public boundaries is fine) and pass it through to every
awaited call.

```csharp
public async Task<Order> GetOrderAsync(int id, CancellationToken cancellationToken)
{
    return await _db.Orders.FirstAsync(o => o.Id == id, cancellationToken);
}
```

**Flag:** async methods doing I/O with no `CancellationToken` parameter; a token accepted as a
parameter but never actually passed to the inner awaited calls (dead parameter).

## 4. Don't use `Task.Run` to "make something async" on the server

`Task.Run` offloads CPU-bound work to the thread pool - it does not make I/O-bound work faster
and, inside ASP.NET Core request handling, just wastes a thread-pool hop. Use it only for
genuinely CPU-bound work that needs to run off a request thread, not to wrap an I/O call.

```csharp
// Bad - pointless thread-pool hop around an already-async I/O call
public Task<Order> GetOrderAsync(int id) => Task.Run(() => _repo.GetOrderAsync(id).Result);

// Good
public Task<Order> GetOrderAsync(int id) => _repo.GetOrderAsync(id);
```

**Flag:** `Task.Run(() => someAsyncIoCall().Result)` or similar wrapping patterns.

## 5. `ConfigureAwait(false)` in library code

In reusable library code with no dependency on a `SynchronizationContext`, `ConfigureAwait(false)`
avoids unnecessary context-capture overhead. It is not required in typical ASP.NET Core app
code (no `SynchronizationContext` is present there), but is still good practice in shared
libraries consumed by contexts that do have one (e.g. WPF/WinForms/older ASP.NET).

**Flag:** inconsistent use within a single library (some awaits use it, others don't, with no
reason) rather than a project-wide "N/A for this app type" default.

## 6. Avoid unobserved fire-and-forget tasks

If a task's result and exceptions genuinely don't need to be awaited (e.g., a best-effort
background notification), don't just drop the `Task` - either await it through a proper
background queue/hosted service, or explicitly wrap it with exception logging so failures
aren't silently lost.

```csharp
// Bad - exception is silently swallowed, no one observes this task
_ = SendAnalyticsEventAsync(evt);

// Good - explicit, logged, and intentional
_ = Task.Run(async () =>
{
    try { await SendAnalyticsEventAsync(evt); }
    catch (Exception ex) { _logger.LogError(ex, "Failed to send analytics event"); }
});
```

**Flag:** a discarded (`_ =`) or otherwise unawaited `Task` with no visible error handling.

## 7. Use `IAsyncEnumerable<T>` for streaming, not materializing everything into memory

When producing a large or unbounded sequence asynchronously, prefer `IAsyncEnumerable<T>` +
`await foreach` over building a full `List<T>` first, especially for API endpoints or
processing pipelines over large datasets.

**Flag:** `.ToListAsync()`/`.ToList()` on a large/unbounded query purely to iterate once.
