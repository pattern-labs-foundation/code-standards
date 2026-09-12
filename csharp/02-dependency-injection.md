# Dependency Injection

## 1. Constructor injection only

Dependencies are provided through the constructor and stored in `readonly` fields. Avoid
property injection, method injection for required dependencies, or manual `new`-ing of
collaborators inside a class (which prevents substitution in tests).

```csharp
// Bad
public class InvoiceService
{
    public IPaymentGateway Gateway { get; set; } // property injection
    private readonly EmailSender _email = new(); // hard-coded dependency
}

// Good
public class InvoiceService
{
    private readonly IPaymentGateway _gateway;
    private readonly IEmailSender _email;

    public InvoiceService(IPaymentGateway gateway, IEmailSender email)
    {
        _gateway = gateway;
        _email = email;
    }
}
```

**Flag:** `new SomeConcreteDependency()` inside a class that could instead take an interface
via the constructor; public settable properties used to satisfy required dependencies.

## 2. Register the right lifetime

- **Singleton** - stateless or safely shared across all requests (e.g. `IHttpClientFactory`
  wrappers, caches, options-backed clients). Must be thread-safe.
- **Scoped** - one instance per request/unit of work (e.g. `DbContext`, most application
  services touching per-request state).
- **Transient** - cheap, stateless, created fresh every time it's requested.

**Flag:** a service registered as `Singleton` that holds a `DbContext`, `IOptionsSnapshot<T>`,
or any other scoped dependency - this is a **captive dependency** and will either throw or
silently use a stale/incorrect instance for the lifetime of the app.

```csharp
// Bad - captive dependency: DbContext is Scoped but injected into a Singleton
services.AddSingleton<ICacheWarmer, CacheWarmer>(); // CacheWarmer takes AppDbContext

// Good - resolve the scoped dependency per use via a factory
services.AddSingleton<ICacheWarmer, CacheWarmer>(); // CacheWarmer takes IServiceScopeFactory
```

## 3. Avoid injecting `IServiceProvider` / `IServiceScopeFactory` directly into business logic

These are appropriate **only** in factories, background workers that need to create a scope
per unit of work, or the composition root (`Program.cs`). Injecting the raw provider into a
regular service is a service-locator anti-pattern in disguise.

**Flag:** `IServiceProvider` as a constructor parameter on anything other than a factory class
or a hosted/background service.

## 4. Register interfaces, not concrete types, for anything with more than one caller or that
needs to be mockable in tests

```csharp
services.AddScoped<IOrderRepository, SqlOrderRepository>();
```

**Flag:** application/domain services registered and consumed by their concrete type when a
test double would reasonably be needed (i.e., anything doing I/O).

## 5. Keep constructors free of logic

Constructors should only assign injected dependencies to fields. No I/O, no `async` work, no
validation beyond null checks.

```csharp
public OrderService(IOrderRepository orders)
{
    _orders = orders ?? throw new ArgumentNullException(nameof(orders));
}
```

**Flag:** database calls, HTTP calls, file I/O, or `.Result`/`.Wait()` inside a constructor.

## 6. Prefer factories/`Func<T>` for runtime-parameterized creation

When a component needs a fresh instance per operation with a value only known at call time
(not at DI-registration time), inject a factory delegate or `IFactory<T>` rather than passing
`IServiceProvider` around.

**Flag:** manual `Activator.CreateInstance` or reflection-based instantiation where DI could
be used instead.
