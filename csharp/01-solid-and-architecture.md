# SOLID & Architecture

## 1. Depend on abstractions, not concretions

Business logic should depend on interfaces, not on concrete framework types (`HttpContext`,
`DbContext`, `IConfiguration`) or concrete implementations of collaborators. This keeps the
domain testable and decoupled from infrastructure changes.

```csharp
// Bad - service is coupled to EF Core and can't be unit tested without a real DbContext
public class OrderService
{
    private readonly AppDbContext _db;
    public OrderService(AppDbContext db) => _db = db;
}

// Good - service depends on an abstraction
public class OrderService
{
    private readonly IOrderRepository _orders;
    public OrderService(IOrderRepository orders) => _orders = orders;
}
```

**Flag:** a service/domain class taking `DbContext`, `HttpContext`, `IConfiguration`, or a
static class as a direct dependency.

## 2. Single Responsibility

A class should have one reason to change. Watch for "god classes" / "manager" classes that
accumulate unrelated responsibilities (e.g., a `UserService` that also sends emails, builds
PDFs, and validates payment cards).

**Flag:** classes with many unrelated public methods, or constructors with 6+ injected
dependencies (usually a sign the class is doing too much - split it).

## 3. Layering

Keep a clear separation between:

- **Presentation** (controllers/endpoints) - parses requests, calls application layer,
  shapes responses. No business logic.
- **Application** (services/use cases) - orchestrates domain logic and infrastructure calls.
- **Domain** - entities, value objects, business rules. No framework dependencies.
- **Infrastructure** - EF Core, HTTP clients, file system, third-party SDKs.

**Flag:** business rules embedded in controllers or in EF Core entity configuration classes;
infrastructure types (`HttpClient`, `DbContext`) referenced from the domain layer.

## 4. Favor composition over inheritance

Prefer injecting collaborators over building deep inheritance hierarchies. Inheritance should
model a genuine "is-a" relationship, not be used purely to share code (use extension methods
or a shared helper/service for that instead).

**Flag:** inheritance chains deeper than 2 levels, or abstract base classes whose only purpose
is code reuse rather than polymorphism.

## 5. No service locator / ambient static access

Don't resolve dependencies from a static `ServiceLocator`, `IServiceProvider.GetService<T>()`
calls scattered through business logic, or global mutable static state. Take dependencies
through the constructor.

```csharp
// Bad
public class ReportGenerator
{
    public void Generate() => Program.Services.GetService<IEmailSender>().Send(...);
}
```

**Flag:** `IServiceProvider` injected into a class other than a factory/composition root;
static fields holding mutable service instances; `HttpContext.Current`-style ambient access.

## 6. Keep controllers/endpoints thin

A controller action or minimal API handler should: validate/bind input, call one
application-layer method, map the result to an HTTP response. It should not contain
conditionals implementing business rules, direct EF Core queries, or multi-step orchestration.

**Flag:** controller actions longer than ~15-20 lines, or containing `if`/`switch` on business
state rather than delegating to a service.

## 7. Interface segregation

Prefer small, focused interfaces over one large interface every consumer must implement in
full. If a consumer only needs 2 of 10 methods on an interface, split it.

**Flag:** interfaces with 8+ methods that no single implementation uses fully, or "fat"
repository interfaces mixing read and write concerns without need.
