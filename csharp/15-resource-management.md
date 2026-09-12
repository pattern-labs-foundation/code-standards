# Resource Management (`IDisposable`/`IAsyncDisposable`)

## 1. Use `using` for anything disposable

Any `IDisposable`/`IAsyncDisposable` you create and own should be wrapped in a `using`
statement or declaration so it's disposed deterministically, including on exception paths.

```csharp
// Bad - leaked if ReadAsync throws
var stream = File.OpenRead(path);
var data = await ReadAsync(stream);

// Good
using var stream = File.OpenRead(path);
var data = await ReadAsync(stream);
```

**Flag:** a locally-created `IDisposable`/`IAsyncDisposable` with no `using` and no other
clear disposal path (e.g., manually calling `.Dispose()` in a `finally` block, which is
equivalent but more verbose and error-prone than `using`).

## 2. Don't dispose dependencies you don't own

If a disposable object was injected (via DI) rather than created locally, do not dispose it
yourself - the DI container owns its lifetime and will dispose it appropriately.

```csharp
// Bad - disposes a dependency the DI container still needs for other consumers
public class ReportService(AppDbContext db)
{
    public void Generate() { ... db.Dispose(); ... }
}
```

**Flag:** `.Dispose()`/`using` applied to a constructor-injected dependency.

## 3. Implement `IDisposable` correctly when a class directly owns unmanaged/scarce resources

If a class owns a disposable resource as a field (a file handle, a socket, a `DbConnection`
it created itself, etc.), it should implement `IDisposable` (and `IAsyncDisposable` if async
cleanup is meaningful) and dispose owned resources in `Dispose()`. Follow the standard
dispose pattern if the class is also unsealed and might be subclassed; a simple, sealed class
can implement the minimal single-method form.

**Flag:** a class holding a disposable field with no `IDisposable` implementation at all; a
`Dispose()` method that doesn't actually dispose the fields it owns.

## 4. Avoid finalizers unless directly wrapping unmanaged (native) resources

Finalizers add GC overhead and are only necessary when a type directly owns an unmanaged
handle that has no other managed wrapper. If you're only holding other `IDisposable` managed
objects (streams, contexts, HTTP clients), you do not need a finalizer - just dispose them in
`Dispose()`.

**Flag:** a finalizer (`~ClassName()`) added to a class whose only "resources" are other
managed `IDisposable` objects.

## 5. `IAsyncDisposable` for resources with meaningful async cleanup

If disposal genuinely involves I/O (flushing a stream, closing a network connection), prefer
implementing `IAsyncDisposable` and using `await using`, rather than forcing synchronous
disposal of something that's naturally asynchronous.

**Flag:** a class wrapping an inherently async resource (a network stream, a message queue
consumer) that only implements synchronous `IDisposable` and blocks internally to clean up.
