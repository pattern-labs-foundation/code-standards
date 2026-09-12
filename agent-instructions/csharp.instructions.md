---
applyTo: "**/*.cs,**/*.csproj,**/appsettings*.json"
---

# C# Coding Standards

Apply these when reviewing or writing C# in this repository. Flag violations with the
reason, not just the rule. Prioritise correctness and security over style. Only flag what
is visible in the diff.

## SOLID & Architecture

### 1. Depend on abstractions, not concretions

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

### 2. Single Responsibility

A class should have one reason to change. Watch for "god classes" / "manager" classes that
accumulate unrelated responsibilities (e.g., a `UserService` that also sends emails, builds
PDFs, and validates payment cards).

**Flag:** classes with many unrelated public methods, or constructors with 6+ injected
dependencies (usually a sign the class is doing too much - split it).

### 3. Layering

Keep a clear separation between:

- **Presentation** (controllers/endpoints) - parses requests, calls application layer,
  shapes responses. No business logic.
- **Application** (services/use cases) - orchestrates domain logic and infrastructure calls.
- **Domain** - entities, value objects, business rules. No framework dependencies.
- **Infrastructure** - EF Core, HTTP clients, file system, third-party SDKs.

**Flag:** business rules embedded in controllers or in EF Core entity configuration classes;
infrastructure types (`HttpClient`, `DbContext`) referenced from the domain layer.

### 4. Favor composition over inheritance

Prefer injecting collaborators over building deep inheritance hierarchies. Inheritance should
model a genuine "is-a" relationship, not be used purely to share code (use extension methods
or a shared helper/service for that instead).

**Flag:** inheritance chains deeper than 2 levels, or abstract base classes whose only purpose
is code reuse rather than polymorphism.

### 5. No service locator / ambient static access

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

### 6. Keep controllers/endpoints thin

A controller action or minimal API handler should: validate/bind input, call one
application-layer method, map the result to an HTTP response. It should not contain
conditionals implementing business rules, direct EF Core queries, or multi-step orchestration.

**Flag:** controller actions longer than ~15-20 lines, or containing `if`/`switch` on business
state rather than delegating to a service.

### 7. Interface segregation

Prefer small, focused interfaces over one large interface every consumer must implement in
full. If a consumer only needs 2 of 10 methods on an interface, split it.

**Flag:** interfaces with 8+ methods that no single implementation uses fully, or "fat"
repository interfaces mixing read and write concerns without need.

## Dependency Injection

### 1. Constructor injection only

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

### 2. Register the right lifetime

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

### 3. Avoid injecting `IServiceProvider` / `IServiceScopeFactory` directly into business logic

These are appropriate **only** in factories, background workers that need to create a scope
per unit of work, or the composition root (`Program.cs`). Injecting the raw provider into a
regular service is a service-locator anti-pattern in disguise.

**Flag:** `IServiceProvider` as a constructor parameter on anything other than a factory class
or a hosted/background service.

### 4. Register interfaces, not concrete types, for anything with more than one caller or that
needs to be mockable in tests

```csharp
services.AddScoped<IOrderRepository, SqlOrderRepository>();
```

**Flag:** application/domain services registered and consumed by their concrete type when a
test double would reasonably be needed (i.e., anything doing I/O).

### 5. Keep constructors free of logic

Constructors should only assign injected dependencies to fields. No I/O, no `async` work, no
validation beyond null checks.

```csharp
public OrderService(IOrderRepository orders)
{
    _orders = orders ?? throw new ArgumentNullException(nameof(orders));
}
```

**Flag:** database calls, HTTP calls, file I/O, or `.Result`/`.Wait()` inside a constructor.

### 6. Prefer factories/`Func<T>` for runtime-parameterized creation

When a component needs a fresh instance per operation with a value only known at call time
(not at DI-registration time), inject a factory delegate or `IFactory<T>` rather than passing
`IServiceProvider` around.

**Flag:** manual `Activator.CreateInstance` or reflection-based instantiation where DI could
be used instead.

## Configuration & the Options Pattern

This is one of the most commonly violated standards in .NET codebases - raw `IConfiguration`
access spreads magic strings and untyped lookups through business logic. Prefer the
**Options pattern** everywhere outside the composition root.

### 1. Never inject `IConfiguration` into domain/application services

`IConfiguration` should only be read from `Program.cs` / `Startup.cs` (the composition root),
where it is bound into strongly-typed options classes. Business logic should never call
`configuration["Some:Key"]` or `configuration.GetValue<T>(...)` directly.

```csharp
// Bad
public class EmailSender
{
    private readonly IConfiguration _config;
    public EmailSender(IConfiguration config) => _config = config;

    public void Send(string to, string body)
    {
        var host = _config["Smtp:Host"]; // magic string, no validation, no IntelliSense
        var port = int.Parse(_config["Smtp:Port"]); // throws at runtime if missing/invalid
    }
}

// Good
public class SmtpOptions
{
    public const string SectionName = "Smtp";
    public required string Host { get; init; }
    public int Port { get; init; } = 587;
}

public class EmailSender
{
    private readonly SmtpOptions _options;
    public EmailSender(IOptions<SmtpOptions> options) => _options = options.Value;
}
```

**Flag:** `IConfiguration` as a constructor parameter anywhere outside `Program.cs`/hosting
extension methods; string-keyed config lookups (`config["X:Y"]`) inside business/service code.

### 2. Choose the right options interface

| Interface | Lifetime | Reloads on config change? | Use when |
|---|---|---|---|
| `IOptions<T>` | Singleton-safe | No (captures value at first resolution) | Simple, rarely-changing config; safe to inject into singletons |
| `IOptionsSnapshot<T>` | Scoped | Yes, recomputed per scope/request | Per-request services that should see updated config on the next request |
| `IOptionsMonitor<T>` | Singleton-safe | Yes, live, with `OnChange` callback | Singletons/background services that need to react to config changes immediately |

**Flag:** `IOptionsSnapshot<T>` injected into a `Singleton`-registered service (this throws or
silently misbehaves at runtime - it's a captive-dependency variant); `IOptions<T>` used where
live reload is clearly expected by the feature (e.g., feature flags meant to take effect
without a restart).

### 3. Bind options explicitly and validate them at startup

```csharp
builder.Services
    .AddOptions<SmtpOptions>()
    .Bind(builder.Configuration.GetSection(SmtpOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart(); // fail at startup, not on first request
```

For validation beyond attributes (cross-field rules, e.g. "Port must be 587 or 465 when
UseSsl is true"), implement `IValidateOptions<T>`:

```csharp
public class SmtpOptionsValidator : IValidateOptions<SmtpOptions>
{
    public ValidateOptionsResult Validate(string? name, SmtpOptions options)
    {
        if (options.UseSsl && options.Port is not (587 or 465))
            return ValidateOptionsResult.Fail("Port must be 587 or 465 when UseSsl is true.");
        return ValidateOptionsResult.Success;
    }
}
```

**Flag:** an options class with no validation at all for values that are required for the app
to function (connection strings, API keys, required feature settings); missing
`.ValidateOnStart()` on options that gate startup-critical behavior.

### 4. Options classes are plain data, named consistently

- Suffix the class with `Options` (`SmtpOptions`, `JwtOptions`).
- Define the config section name as a `public const string SectionName` on the class itself,
  so it isn't duplicated as a string literal at every registration/consumption site.
- No behavior/methods beyond simple computed properties - options classes are data, not
  services.

**Flag:** the same section-name string literal (`"Smtp"`) repeated in multiple files instead
of referenced from a single constant.

### 5. Secrets never live in `appsettings.json` or source control

- Local development: `dotnet user-secrets`.
- Deployed environments: environment variables, Azure Key Vault, AWS Secrets Manager/Parameter
  Store, or an equivalent secret store - wired into configuration providers, then bound into
  the same strongly-typed options classes.
- `appsettings.json` may contain non-secret defaults and structure, never real credentials,
  connection strings with passwords, or API keys.

**Flag:** any connection string, API key, password, or token literal committed in
`appsettings*.json`, source files, or CI config; `.gitignore` missing entries for
`appsettings.*.local.json` or similar if that convention is used.

### 6. Reflect config schema through types, not `dynamic`/`JObject`

If a section has known shape, bind it to a class. Reach for `IConfiguration.GetSection(...)`
without binding, or dynamic/JSON-object access, only for genuinely dynamic/unknown-shape data.

**Flag:** `IConfigurationSection` passed around and indexed ad hoc instead of bound to a type.

## Async & Concurrency

### 1. Async all the way down - never block on async code

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

### 2. Never use `async void` except for true event handlers

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

### 3. Accept and honor `CancellationToken`

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

### 4. Don't use `Task.Run` to "make something async" on the server

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

### 5. `ConfigureAwait(false)` in library code

In reusable library code with no dependency on a `SynchronizationContext`, `ConfigureAwait(false)`
avoids unnecessary context-capture overhead. It is not required in typical ASP.NET Core app
code (no `SynchronizationContext` is present there), but is still good practice in shared
libraries consumed by contexts that do have one (e.g. WPF/WinForms/older ASP.NET).

**Flag:** inconsistent use within a single library (some awaits use it, others don't, with no
reason) rather than a project-wide "N/A for this app type" default.

### 6. Avoid unobserved fire-and-forget tasks

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

### 7. Use `IAsyncEnumerable<T>` for streaming, not materializing everything into memory

When producing a large or unbounded sequence asynchronously, prefer `IAsyncEnumerable<T>` +
`await foreach` over building a full `List<T>` first, especially for API endpoints or
processing pipelines over large datasets.

**Flag:** `.ToListAsync()`/`.ToList()` on a large/unbounded query purely to iterate once.

## Error Handling

### 1. Throw specific exception types

Throw the most specific built-in exception that fits (`ArgumentNullException`,
`ArgumentOutOfRangeException`, `InvalidOperationException`) or a custom domain exception that
carries meaning. Avoid throwing bare `Exception`.

```csharp
// Bad
throw new Exception("Order not found");

// Good
throw new OrderNotFoundException(orderId);
```

**Flag:** `throw new Exception(...)`; custom exceptions that don't add meaningful context
(e.g., no order id, no relevant state) over a built-in type.

### 2. Don't catch what you can't handle

Only catch an exception type if the code can meaningfully recover, add context, or needs to
translate it into a different error shape at a boundary (e.g., an API exception filter turning
a domain exception into a `ProblemDetails` response). Otherwise let it propagate.

```csharp
// Bad - swallows the error, caller has no idea anything went wrong
try { await _repo.SaveAsync(order); }
catch { }

// Good - only caught where there is something meaningful to do
try { await _repo.SaveAsync(order); }
catch (DbUpdateConcurrencyException ex)
{
    throw new OrderConflictException(order.Id, ex);
}
```

**Flag:** empty `catch` blocks; `catch (Exception)` (or bare `catch`) that only logs and
swallows without rethrowing, at any layer other than a top-level/global handler; `catch`
blocks that "handle" an error by returning `null`/`false` and hiding the real cause.

### 3. Never lose the original exception

If you need to add context and rethrow, wrap the original as `InnerException` rather than
throwing a new exception with only a string message, and never use `throw ex;` (which resets
the stack trace) - use `throw;` to rethrow the current exception, or wrap it.

```csharp
// Bad - stack trace is reset, and the original exception is discarded
catch (Exception ex)
{
    throw new ApplicationException("Something failed");
}

// Good
catch (SqlException ex)
{
    throw new OrderPersistenceException(order.Id, ex);
}
```

**Flag:** `throw ex;` inside a catch block; a caught exception that is not passed as
`innerException` to whatever is thrown/logged in its place.

### 4. Don't use exceptions for expected control flow

If a failure is a normal, expected outcome (e.g., "item not found," "validation failed," "user
already exists"), prefer a `Result`-style return value, a `TryGetX` pattern, or a well-defined
domain response over throwing/catching an exception for it. Reserve exceptions for genuinely
exceptional/unexpected conditions.

```csharp
// Bad - "not found" is an expected case, not exceptional
public Order GetOrder(int id)
{
    var order = _orders.Find(id) ?? throw new OrderNotFoundException(id);
    return order;
}

// Good, when "not found" is a normal branch the caller needs to handle
public bool TryGetOrder(int id, out Order? order)
{
    order = _orders.Find(id);
    return order is not null;
}
```

**Flag:** exceptions thrown and immediately caught within the same method purely to implement
branching logic; validation failures modeled as exceptions in hot paths where a large
percentage of calls are expected to fail validation.

### 5. Centralize translation of errors to HTTP responses

APIs should have one place (exception-handling middleware, an `IExceptionHandler`, or a
consistent exception filter) that maps domain/application exceptions to HTTP status codes and
a `ProblemDetails` body, rather than each controller action doing its own try/catch-and-map.

**Flag:** repeated try/catch-and-map-to-status-code blocks copy-pasted across multiple
controller actions instead of centralized handling.

### 6. Guard clauses over deep nesting

Validate preconditions early and return/throw, rather than nesting the "happy path" inside
multiple levels of `if`.

```csharp
// Bad
public void Process(Order order)
{
    if (order != null)
    {
        if (order.Items.Any())
        {
            // actual logic, 3 levels deep
        }
    }
}

// Good
public void Process(Order order)
{
    if (order is null) throw new ArgumentNullException(nameof(order));
    if (!order.Items.Any()) return;

    // actual logic, at the top level
}
```

**Flag:** nesting depth of 3+ purely from defensive `if` checks that could be guard clauses.

## Logging & Observability

### 1. Inject `ILogger<T>`, don't use static loggers or `Console.WriteLine`

```csharp
// Bad
Console.WriteLine("Order processed: " + orderId);

// Good
public class OrderService(ILogger<OrderService> logger)
{
    public void Process(Order order) =>
        logger.LogInformation("Processed order {OrderId}", order.Id);
}
```

**Flag:** `Console.WriteLine`/`Debug.WriteLine` used for application logging; static/global
logger instances instead of `ILogger<T>` injected per class.

### 2. Use structured logging message templates, not string interpolation

Message templates with named placeholders let log backends (Seq, Application Insights,
Elasticsearch, etc.) query and filter on individual field values. String interpolation bakes
the value into a flat string and loses that structure.

```csharp
// Bad - loses structure, can't query by OrderId in the log backend
logger.LogInformation($"Processed order {order.Id} for user {order.UserId}");

// Good - OrderId and UserId become queryable structured fields
logger.LogInformation("Processed order {OrderId} for user {UserId}", order.Id, order.UserId);
```

**Flag:** `$"..."` interpolated strings or string concatenation passed as the log message.

### 3. Use the correct log level

- **Trace** - extremely verbose, step-by-step diagnostic detail, disabled by default.
- **Debug** - useful for diagnosing issues in development, not needed in normal production.
- **Information** - normal application flow worth recording (request handled, order placed).
- **Warning** - unexpected but recoverable; something a human may want to look at.
- **Error** - a failure that affected the current operation.
- **Critical** - the application or a critical dependency is in a state that requires
  immediate attention.

**Flag:** `LogError`/`LogCritical` used for expected/handled conditions (e.g., validation
failures, "not found" results); routine successful operations logged at `Warning` or higher;
high-volume hot-path logging at `Information` that should be `Debug`/`Trace`.

### 4. Never log sensitive data

Passwords, tokens, API keys, connection strings, full credit card numbers, and other PII/secret
data must never appear in log output, including in exception messages that get logged.

```csharp
// Bad
logger.LogInformation("Authenticating user with password {Password}", password);

// Good
logger.LogInformation("Authenticating user {UserId}", userId);
```

**Flag:** any secret, token, password, or connection string interpolated into a log call or
exception message; full request/response bodies logged without redaction where they may
contain PII or credentials.

### 5. Log exceptions with the exception object, not just its message

```csharp
// Bad - loses stack trace and inner exception detail
logger.LogError("Failed to process order: " + ex.Message);

// Good
logger.LogError(ex, "Failed to process order {OrderId}", order.Id);
```

**Flag:** `ex.Message`/`ex.ToString()` interpolated into the message template instead of the
exception passed as the first argument to `LogError`/`LogWarning`/`LogCritical`.

### 6. Correlate logs across a request/operation

Rely on the built-in trace/correlation identifiers (`Activity.Current`, `TraceIdentifier`, or
an OpenTelemetry-based trace ID) rather than inventing ad hoc request IDs, so a single user
request can be traced across services and log entries.

**Flag:** custom, hand-rolled "request ID" generation and threading when the framework/tracing
infrastructure already provides one.

### 7. Don't log in tight loops without a reason

Logging inside a loop that runs thousands of times per request will flood the log backend and
obscure genuinely useful signal. Aggregate and log a summary instead, or drop to `Trace` level
behind a check.

**Flag:** a `LogInformation`/`LogDebug` call inside a loop with no bound on iteration count.

## API Design (ASP.NET Core)

### 1. Use DTOs at the boundary, never expose EF Core entities directly

Request/response models should be dedicated DTOs, not the EF Core entity classes. This avoids
over-posting vulnerabilities, accidental serialization of navigation properties/lazy-loading
proxies, and coupling the API contract to the database schema.

```csharp
// Bad - EF entity returned directly; adding a column changes the public API
[HttpGet("{id}")]
public async Task<Order> Get(int id) => await _db.Orders.FindAsync(id);

// Good
[HttpGet("{id}")]
public async Task<OrderResponse> Get(int id)
{
    var order = await _orderService.GetAsync(id);
    return order.ToResponse();
}
```

**Flag:** EF Core entity types (or types decorated with `[Table]`/navigation properties) as
controller action parameters or return types; a request DTO with more fields than the client
should be able to set (over-posting risk, e.g. accepting `IsAdmin` on a public signup DTO).

### 2. Validate all external input

Use DataAnnotations or FluentValidation on request DTOs, and ensure model validation is
actually enforced (`ApiController` attribute enables automatic 400 responses; for minimal
APIs, validate explicitly or via a validation filter).

**Flag:** request DTOs with no validation attributes on fields that have real constraints
(required strings, numeric ranges, string lengths); controller actions that read
`ModelState.IsValid` inconsistently or not at all.

### 3. Return correct, specific HTTP status codes

- `200 OK` for successful reads / updates that return content.
- `201 Created` for successful resource creation, with a `Location` header.
- `204 No Content` for successful actions with no body (e.g., delete).
- `400 Bad Request` for validation errors.
- `401`/`403` for authentication/authorization failures (not the same thing - 401 means "who
  are you," 403 means "I know who you are, you can't do this").
- `404 Not Found` for missing resources.
- `409 Conflict` for state conflicts (e.g., concurrency, duplicate resource).
- `422 Unprocessable Entity` (optional) for semantically invalid input that passes basic
  validation.
- `500` only for genuinely unexpected server errors, never as a catch-all for business
  failures.

**Flag:** every error path returning `400` or `500` regardless of actual cause; `200 OK`
returned with an error payload/flag inside the body instead of a real error status code.

### 4. Use `ProblemDetails` for error responses

ASP.NET Core's `ProblemDetails` (RFC 9457) gives clients a consistent error shape
(`type`, `title`, `status`, `detail`, `instance`, plus `errors` for validation problems).
Don't invent a bespoke error JSON shape per endpoint.

**Flag:** ad hoc `{ "error": "..." }` or `{ "message": "..." }` response shapes that differ
between endpoints instead of a single consistent error contract.

### 5. Never leak internal details to clients

Stack traces, exception messages containing internal file paths/SQL/connection strings, and
internal type names should never reach the client response body in production. Show detailed
errors only in development (`app.UseDeveloperExceptionPage()` gated by environment).

**Flag:** `ex.ToString()`/`ex.StackTrace` returned in a response body reachable in production;
`UseDeveloperExceptionPage` not gated behind an environment check.

### 6. Version your API deliberately

Pick one strategy (URL segment `/v1/...`, header, or query string) and apply it consistently;
don't silently break existing clients by changing a response shape on an existing endpoint.

**Flag:** a breaking change (removed field, changed field type, changed semantics) made to an
existing endpoint's contract without a version bump or explicit migration plan.

### 7. Paginate collection endpoints

Any endpoint that can return an unbounded number of items must support pagination
(page/pageSize or cursor-based) rather than returning the entire table.

**Flag:** a `GET` list endpoint with no pagination parameters querying a table that can grow
without bound.

### 8. Async all the way in controllers/handlers

Controller actions and minimal API handlers that do I/O should be `async Task<T>`, accept a
`CancellationToken` (minimal APIs get one injected automatically; controllers can bind one as a
parameter), and pass it through.

**Flag:** synchronous controller actions wrapping I/O calls with `.Result`/`.Wait()` (see
[Async & Concurrency](#async--concurrency)).

## Data Access & EF Core

### 1. `DbContext` is scoped, never singleton or static

`DbContext` is not thread-safe and is designed to be short-lived, one instance per unit of
work/request. Registering it as `Singleton`, storing it in a static field, or sharing one
instance across concurrent operations will cause data corruption or exceptions under load.

**Flag:** `AddDbContext` lifetime overridden to `Singleton`; a static field holding a
`DbContext`; a `DbContext` instance captured in a background task that outlives the request
scope it came from.

### 2. Use `AsNoTracking()` for read-only queries

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

### 3. Avoid N+1 queries

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

### 4. Project to DTOs instead of loading full entities when possible

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

### 5. Don't expose `IQueryable<T>` outside the data-access layer

Returning `IQueryable<T>` from a repository leaks the ability for callers to compose arbitrary,
untracked-by-the-team queries against the database from anywhere in the codebase, and makes it
hard to reason about what queries actually run. Repositories should return materialized
results (`IReadOnlyList<T>`, a single entity, etc.) or accept explicit query parameters.

**Flag:** a repository/service interface with a method returning `IQueryable<T>` consumed by
callers outside the data-access layer.

### 6. Keep entity classes focused on state and simple invariants

Entities may contain simple, self-contained business rules (e.g., a method that enforces an
invariant about their own state), but should not depend on external services, call the
database, or contain orchestration logic that belongs in an application service.

**Flag:** entity classes with injected dependencies, static service-locator calls, or methods
that perform I/O.

### 7. Use migrations, never hand-edit the schema

All schema changes go through EF Core migrations (or an equivalent versioned migration tool)
checked into source control. Don't apply ad hoc `ALTER TABLE` statements directly against a
shared database.

**Flag:** raw SQL DDL scripts outside the migrations folder; a migration that has been edited
after being applied to any shared environment instead of being superseded by a new migration.

### 8. Use `ExecuteUpdate`/`ExecuteDelete` for bulk operations

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

### 9. Wrap multi-step writes in a transaction

If a unit of work involves multiple `SaveChangesAsync` calls or multiple related writes that
must succeed or fail together, wrap them in an explicit transaction
(`_db.Database.BeginTransactionAsync()` or `IDbContextTransaction`), or restructure so a single
`SaveChangesAsync` covers all of them (EF Core already wraps one `SaveChangesAsync` call in an
implicit transaction).

**Flag:** multiple sequential `SaveChangesAsync()` calls representing one logical operation
with no surrounding transaction and no compensating rollback logic.

## Security

### 1. Never build SQL with string concatenation

Use EF Core's parameterized LINQ queries, or parameterized `FromSqlInterpolated`/command
parameters for raw SQL. Never concatenate or interpolate untrusted input directly into a SQL
string.

```csharp
// Bad - SQL injection
var sql = $"SELECT * FROM Orders WHERE UserId = '{userId}'";

// Good - parameterized
var orders = await _db.Orders
    .FromSqlInterpolated($"SELECT * FROM Orders WHERE UserId = {userId}")
    .ToListAsync();
```

**Flag:** any string concatenation or interpolation used to build a SQL query with a value
that originates from user input; `FromSqlRaw` with concatenated input instead of
`FromSqlInterpolated`/parameters.

### 2. Validate and sanitize all external input

Treat query parameters, route values, request bodies, headers, and file uploads as untrusted.
Validate shape, length, and range; encode output appropriately for its destination (HTML, a
URL, a shell argument, a log line).

**Flag:** user-controlled input passed directly into a file path (path traversal risk), a
shell command (`Process.Start` with unsanitized arguments), a redirect URL (open redirect), or
rendered into HTML without encoding.

### 3. Use the framework's authentication/authorization, don't hand-roll checks

Use `[Authorize]`, policy-based authorization, and ASP.NET Core Identity/your chosen auth
provider rather than scattering manual role/claim string checks through controllers.

```csharp
// Bad - manual, easy to get wrong or forget on a new endpoint
if (User.FindFirst("role")?.Value != "Admin") return Forbid();

// Good
[Authorize(Policy = "RequireAdmin")]
public class AdminController : ControllerBase { }
```

**Flag:** manual claim/role string comparisons instead of `[Authorize]`/policies; an endpoint
that mutates or exposes sensitive data with no `[Authorize]` attribute and no explicit
documented reason it's intentionally anonymous.

### 4. Secrets never live in source control

See [03-configuration-and-options.md].
No API keys, connection strings, certificates, or credentials committed to the repository,
including in test fixtures or commented-out code.

**Flag:** any credential-shaped literal in a diff; `.env` files committed instead of
`.gitignore`d.

### 5. Enforce HTTPS and secure headers

`UseHttpsRedirection()` and HSTS should be enabled for production. Cookies carrying auth state
must be `HttpOnly`, `Secure`, and `SameSite` appropriately scoped.

**Flag:** cookies used for authentication without `HttpOnly`/`Secure` flags; HTTPS redirection
disabled outside of local development.

### 6. Configure CORS with the minimum necessary scope

Avoid `AllowAnyOrigin()` combined with credentials, and avoid wildcard origins for any API that
handles authenticated requests.

```csharp
// Bad - wildcard origin, and dangerous if combined with AllowCredentials
policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod();

// Good
policy.WithOrigins("https://app.example.com").AllowAnyHeader().WithMethods("GET", "POST");
```

**Flag:** `AllowAnyOrigin()` on a CORS policy applied to authenticated endpoints;
`AllowCredentials()` combined with a wildcard origin (the framework will reject this, but
watch for workarounds that dynamically echo back any `Origin` header).

### 7. Don't roll your own cryptography

Use the platform's vetted APIs (`System.Security.Cryptography`, ASP.NET Core Identity's
password hasher) for hashing, encryption, and token generation. Never implement a custom
hashing/encryption scheme, and never use `MD5`/`SHA1` for password hashing.

**Flag:** custom XOR/rotation-based "encryption"; `MD5`/`SHA1` used for password hashes instead
of a purpose-built password hasher (e.g., PBKDF2/BCrypt/Argon2 as wrapped by Identity or a
vetted library); a fixed/hardcoded encryption key or IV.

### 8. Deserialize untrusted data safely

Prefer `System.Text.Json` with explicit types over `BinaryFormatter` (obsolete and unsafe for
untrusted input) or unrestricted polymorphic deserialization. Set reasonable limits on request
body size and array/collection sizes to avoid resource-exhaustion via oversized payloads.

**Flag:** `BinaryFormatter`, `NetDataContractSerializer`, or similarly unsafe legacy
serializers used on any data that could originate from a client; unrestricted polymorphic
JSON deserialization (`TypeNameHandling`-equivalent) accepting attacker-controlled type names.

### 9. Least privilege for credentials and connections

Database users, service accounts, and API keys used by the application should have only the
permissions the application actually needs, not broad admin-equivalent access, and different
environments (dev/staging/prod) should use separate credentials.

**Flag:** a connection string using a database admin/superuser account for routine application
queries; a single shared API key/secret reused across all environments.

## Performance

### 1. Measure before optimizing

Don't restructure clear, correct code for performance without a measured reason (a profiler
result, a benchmark, a known hot path). Premature micro-optimization that sacrifices
readability for an unmeasured gain is a net loss.

**Flag:** performance-motivated code changes (manual loops replacing LINQ, `Span<T>`
rewrites, caching) introduced without any stated measurement or clearly hot code path
justifying it.

### 2. Avoid unnecessary allocations in hot paths

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

### 3. Don't fetch more data than you need

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

### 4. Cache deliberately, with a clear invalidation story

Caching (in-memory, distributed, HTTP response caching) is appropriate for expensive,
frequently-requested, and either immutable or tolerant-of-staleness data. Every cache needs an
explicit expiration policy or invalidation trigger; a cache that never expires and never gets
invalidated on writes will silently serve stale data.

**Flag:** caching added with no expiration/invalidation strategy at all; a cache used for data
that must always be strictly current (e.g., account balances, permission checks) without a
justified staleness tolerance.

### 5. Avoid sync-over-async and thread-pool starvation

See [Async & Concurrency](#async--concurrency). Blocking on async I/O ties
up thread-pool threads and directly hurts throughput under load.

### 6. Use streaming APIs for large payloads

For large request/response bodies, file uploads/downloads, or large query results, stream
data (`IAsyncEnumerable<T>`, `Stream`-based APIs) rather than buffering the entire payload in
memory.

**Flag:** an endpoint reading an entire large file/upload into a `byte[]`/`MemoryStream`
before it needs to be fully materialized; large query results forced into a single in-memory
`List<T>` when the consumer only needs to iterate once.

### 7. Reuse `HttpClient` via `IHttpClientFactory`

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

### 8. Be cautious with reflection in hot paths

Reflection-heavy code (`Activator.CreateInstance`, `PropertyInfo.GetValue` in loops) is
significantly slower than direct calls. Cache reflection results (delegates, compiled
expressions) if reflection is unavoidable in a hot path, or avoid it entirely with a
source-generated or explicit alternative.

**Flag:** reflection calls repeated inside a loop or per-request instead of being computed
once and cached/reused.

## Testing

### 1. Arrange, Act, Assert

Structure each test in three clear parts: set up state, perform the action under test, assert
the outcome. Avoid interleaving assertions with setup or mixing multiple unrelated actions
into one test.

```csharp
[Fact]
public async Task GetOrder_WhenOrderExists_ReturnsOrder()
{
    // Arrange
    var repo = new FakeOrderRepository();
    repo.Add(new Order { Id = 1, Total = 100 });
    var sut = new OrderService(repo);

    // Act
    var order = await sut.GetOrderAsync(1);

    // Assert
    Assert.Equal(100, order.Total);
}
```

**Flag:** tests with assertions scattered throughout setup logic; a single test asserting many
unrelated behaviors.

### 2. One behavior per test, descriptive names

Test names should describe the scenario and expected outcome (a common convention:
`MethodName_Scenario_ExpectedResult`), so a failing test's name alone tells you what broke.

**Flag:** test names like `Test1`, `OrderServiceTests`, or generic names that don't describe
the scenario; a single test method covering multiple unrelated scenarios with multiple
unrelated assertion blocks.

### 3. Mock/fake interfaces, not concrete infrastructure

Unit tests should substitute collaborators via their interfaces (using a mocking library or
hand-written fakes), not spin up real databases, real HTTP calls, or the real file system.
Tests that need real infrastructure belong in a separate integration test suite, clearly
distinguished from unit tests (by project, namespace, or trait/category).

**Flag:** a "unit test" that opens a real database connection, makes a real outbound HTTP
call, or depends on network/file-system state; integration tests mixed into the same project
and run indiscriminately alongside fast unit tests without a way to run them separately.

### 4. Don't test private implementation details

Test observable behavior through the public API, not private methods or internal state via
reflection. If a private method needs its own dedicated tests, it's usually a sign it should
be extracted into its own class with a public API.

**Flag:** tests using reflection to invoke private methods or read private fields directly;
tests that break when an implementation detail changes but the public behavior/contract has
not.

### 5. Deterministic tests

Tests must not depend on wall-clock time, machine locale, network availability, test
execution order, or shared mutable static state. Inject a clock abstraction (e.g.
`TimeProvider`) instead of calling `DateTime.Now` directly in code under test, and avoid
`Thread.Sleep` to "wait for" async work - await it, or use a proper test synchronization
mechanism.

```csharp
// Bad - flaky under load, and slow
Thread.Sleep(500);
Assert.True(handler.WasCalled);

// Good
await handler.Completion; // an awaitable signal, not a fixed delay
Assert.True(handler.WasCalled);
```

**Flag:** `Thread.Sleep` used to wait for asynchronous work in a test; direct calls to
`DateTime.Now`/`DateTime.UtcNow` inside code under test with no injectable clock, when the
test needs to control time; tests that pass or fail differently depending on run order.

### 6. Cover edge cases and failure paths, not just the happy path

For any given unit, tests should include: the typical/happy-path case, boundary conditions
(empty collections, zero, nulls where allowed), and failure/error paths (invalid input, a
dependency throwing).

**Flag:** a class with meaningful branching/error-handling logic that has tests only for its
success path.

### 7. Keep test setup readable - use builders/object mothers for complex objects

When a domain object requires many fields to construct, use a test data builder or factory
method with sensible defaults rather than repeating a large, mostly-irrelevant object literal
in every test.

**Flag:** the same large multi-field object construction duplicated near-identically across
many test methods, obscuring which field actually matters for each test's scenario.

## Nullable Reference Types

### 1. Enable nullable reference types project-wide, and make violations build errors

`<Nullable>enable</Nullable>` alone only turns nullable-flow analysis into *warnings* - the
build still succeeds if a warning is ignored, so nothing actually forces anyone to handle a
possible null. To make it enforced rather than advisory, also turn on
`TreatWarningsAsErrors`:

```xml
<PropertyGroup>
  <Nullable>enable</Nullable>
  <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
</PropertyGroup>
```

New projects should have both settings on from the start. Existing projects migrating should
enable `<Nullable>enable</Nullable>` incrementally per-file (`#nullable enable` at the top of
a file) first, and only turn on `TreatWarningsAsErrors` once the codebase is actually clean of
warnings, rather than leaving nullable off indefinitely or flipping this switch before the
existing warning backlog is addressed. If a specific warning needs a temporary exception
while that cleanup is in progress, suppress it explicitly and narrowly (a `#pragma warning
disable` around the specific line, or a `<NoWarn>` entry for a specific code) rather than
leaving `TreatWarningsAsErrors` off for the whole project indefinitely.

```xml
<!-- Bad - analysis is on, but nothing stops a warning from being ignored -->
<PropertyGroup>
  <Nullable>enable</Nullable>
</PropertyGroup>

<!-- Good - a possible null that isn't handled fails the build -->
<PropertyGroup>
  <Nullable>enable</Nullable>
  <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
</PropertyGroup>
```

**Flag:** a `.csproj` with `<Nullable>disable</Nullable>` (or missing entirely) for a project
started recently with no migration plan noted; `<Nullable>enable</Nullable>` present with no
corresponding `TreatWarningsAsErrors` (or equivalent `.editorconfig` severity escalation on
the nullable warning codes) once the project has no legacy warning backlog left to migrate
through.

### 2. Avoid the null-forgiving operator (`!`) without justification

The `!` operator tells the compiler "trust me, this isn't null" - it suppresses a real warning
without adding a runtime check. Every use is a place a `NullReferenceException` can still
happen; it should be rare and, when used, accompanied by a comment explaining why the
invariant actually holds.

```csharp
// Bad - silences the warning, doesn't address why the compiler thinks this could be null
var name = user!.Name!;

// Good - the invariant is actually established and explained
// User is guaranteed non-null here because we just checked FindAsync's result above.
if (user is null) throw new UserNotFoundException(id);
var name = user.Name;
```

**Flag:** `!` used to silence a warning where a simple null check, guard clause, or pattern
match would resolve it properly instead; `!` with no comment on a non-obvious case.

### 3. Model required state with `required` members and constructors, not nullable-then-checked

If a property must always have a value by the time an object is used, express that in the
type (`required` modifier, or a constructor parameter) rather than making it nullable and
checking for null everywhere it's read.

```csharp
// Bad - nullable string that "should never actually be null," checked everywhere
public class Order { public string? CustomerName { get; set; } }

// Good
public class Order { public required string CustomerName { get; init; } }
```

**Flag:** a property declared nullable purely because it's set slightly after construction
(e.g., via object initializer) rather than because absence is a genuine valid state.

### 4. Don't return null for collections

A method returning a collection type should return an empty collection, never `null`, so
callers don't need a null check before enumerating.

```csharp
// Bad
public List<Order>? GetOrders(int userId) => _orders.Any() ? _orders : null;

// Good
public IReadOnlyList<Order> GetOrders(int userId) => _orders.Where(...).ToList();
```

**Flag:** a collection-returning method with a nullable return type, or that returns `null`
explicitly in any branch.

### 5. Prefer pattern matching over separate null checks plus casts

```csharp
// Bad
if (result != null && result is SuccessResult)
{
    var success = (SuccessResult)result;
}

// Good
if (result is SuccessResult success) { ... }
```

**Flag:** a null check immediately followed by a separate type cast that could be combined
into a single `is` pattern with a binding.

## Style & Naming

These follow the conventions in Microsoft's C# coding conventions and the .NET runtime's own
style guide. An agent reviewing style should treat these as defaults a repo's own `.editorconfig`
can override - if a repo has an `.editorconfig` with different rules, that file wins.

### 1. Casing

- `PascalCase` for types, public members, methods, properties, events, and namespaces.
- `camelCase` for local variables and method parameters.
- `_camelCase` (leading underscore) for private instance fields.
- `PascalCase` for constants (`public const int MaxRetries = 3;`), not `ALL_CAPS`.
- Interfaces are prefixed with `I` (`IOrderRepository`).

**Flag:** public members in `camelCase`; private fields with no leading underscore mixed
inconsistently with ones that have it in the same file; `ALL_CAPS` constants.

### 2. One public type per file, filename matches the type name

`OrderService.cs` contains `public class OrderService`. Small private/internal helper types
tightly coupled to the main type may live alongside it, but another unrelated public type
should not.

**Flag:** a file containing multiple unrelated public types; a filename that doesn't match the
primary public type it defines.

### 3. File-scoped namespaces

```csharp
// Good (C# 10+)
namespace MyApp.Orders;

public class OrderService { }
```

Prefer file-scoped namespace declarations over the older block-scoped form, for new code in
projects targeting C# 10 or later.

**Flag:** block-scoped namespace braces newly introduced in a codebase that otherwise
consistently uses file-scoped namespaces.

### 4. `var` when the type is obvious, explicit type when it isn't

```csharp
var order = new Order();          // obvious from the right-hand side
var id = GetOrderId();             // less obvious - consider an explicit type if it aids readability
IEnumerable<Order> orders = GetOrders(); // explicit type clarifies the returned abstraction
```

**Flag:** `var` used where the right-hand side gives no hint at all what the type is (e.g., a
method call returning a non-obvious type), especially in public API signatures where the
return type should be explicit in the method declaration regardless.

### 5. Expression-bodied members for simple one-liners only

```csharp
// Good
public int Total => Items.Sum(i => i.Price);

// Bad - multi-step logic crammed into an expression body hurts readability
public decimal Total => Items.Where(i => i.IsActive).Sum(i => i.Price * (1 - i.Discount)) + Shipping - Tax;
```

**Flag:** expression-bodied members whose logic spans multiple conceptual steps or would
benefit from intermediate named variables.

### 6. Avoid `#region` as a substitute for splitting a class

Regions are often used to hide the fact that a class has grown too large and covers too many
responsibilities. Prefer extracting cohesive groups of members into their own well-named
classes.

**Flag:** `#region` blocks used to organize a single class into what are effectively several
unrelated responsibilities, rather than genuinely improving navigation of a cohesive class.

### 7. Consistent `using` directive placement and ordering

`using` directives at the top of the file (or globally via `ImplicitUsings`/`GlobalUsings`
where the project convention establishes that), System namespaces first, then third-party,
then the project's own namespaces, each group separated by a blank line.

**Flag:** `using` statements scattered inside namespaces inconsistently with the rest of the
codebase's convention; unused `using` directives left in a file after refactoring.

### 8. Avoid unclear abbreviations

Prefer full, descriptive names over abbreviations that aren't immediately obvious
(`customer` not `cust`, `repository` not `repo` in public API surface, though `repo` as a
private field/local name is common and fine). Loop variables in short, obvious loops (`i`,
`j`) are fine; abbreviating a domain concept is not.

**Flag:** unclear abbreviations in public API member names, especially ones that could be
ambiguous (`qty` vs `quantity` is usually fine and common; `ordSvc` is not).

## Immutability & Records

### 1. Use `record`/`record struct` for DTOs and value objects

Records give value-based equality, a concise syntax, and (with positional or `init`-only
members) immutability by default - exactly the shape most DTOs, events, and value objects
want.

```csharp
// Bad - a mutable class doing a value object's job, with reference equality
public class Money
{
    public decimal Amount { get; set; }
    public string Currency { get; set; }
}

// Good
public record Money(decimal Amount, string Currency);
```

**Flag:** a plain mutable `class` used for a type whose entire purpose is to carry a fixed set
of values with value-based equality (DTOs, events, command/query objects, value objects).

### 2. Prefer immutable state by default

Default to `init`-only or `required init` properties and constructor-based construction.
Mutable public setters should be a deliberate choice for genuinely mutable domain state (e.g.,
an aggregate's evolving fields), not the default for everything.

```csharp
public class Order
{
    public required string CustomerName { get; init; }
    public OrderStatus Status { get; private set; } // deliberately mutable via a method, not a public setter
    public void MarkShipped() => Status = OrderStatus.Shipped;
}
```

**Flag:** public mutable setters (`{ get; set; }`) on properties that should only ever be set
once, or that should only change through a domain method that enforces invariants.

### 3. Don't expose mutable collections publicly

A class that owns a collection should expose it as `IReadOnlyList<T>`/`IReadOnlyCollection<T>`
(or an immutable collection type), not as a `List<T>`/`T[]` that callers can mutate directly
and bypass any invariant the owning class is meant to enforce.

```csharp
// Bad - callers can Add/Remove/Clear directly, bypassing any validation
public List<OrderItem> Items { get; } = new();

// Good
private readonly List<OrderItem> _items = new();
public IReadOnlyList<OrderItem> Items => _items;
public void AddItem(OrderItem item) { /* validate, then */ _items.Add(item); }
```

**Flag:** a public property exposing a mutable collection type (`List<T>`, `Dictionary<K,V>`,
arrays) that represents owned, invariant-bearing state rather than an intentionally free-form
bag of data.

### 4. Understand value equality with records

Records compare by value (all fields/properties equal), not by reference. This is usually
exactly what's wanted for DTOs and value objects, but be deliberate: if a type has identity
that matters independent of its field values (most entities with a database-generated `Id`),
a `class` with reference/identity-based equality (or equality overridden to compare only `Id`)
is more appropriate than a `record`.

**Flag:** a database entity with a mutable identity/lifecycle modeled as a `record` where
value equality on every field would be semantically wrong (e.g., two entities with the same
`Id` but different field values, mid-update, should probably still be "the same" entity).

### 5. `with`-expressions for producing modified copies

When a small change needs to be applied to an immutable value, use a `with` expression rather
than manually reconstructing every field.

```csharp
var discounted = money with { Amount = money.Amount * 0.9m };
```

**Flag:** manual reconstruction of every field of a record just to change one, when a `with`
expression would be clearer.

## Resource Management (`IDisposable`/`IAsyncDisposable`)

### 1. Use `using` for anything disposable

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

### 2. Don't dispose dependencies you don't own

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

### 3. Implement `IDisposable` correctly when a class directly owns unmanaged/scarce resources

If a class owns a disposable resource as a field (a file handle, a socket, a `DbConnection`
it created itself, etc.), it should implement `IDisposable` (and `IAsyncDisposable` if async
cleanup is meaningful) and dispose owned resources in `Dispose()`. Follow the standard
dispose pattern if the class is also unsealed and might be subclassed; a simple, sealed class
can implement the minimal single-method form.

**Flag:** a class holding a disposable field with no `IDisposable` implementation at all; a
`Dispose()` method that doesn't actually dispose the fields it owns.

### 4. Avoid finalizers unless directly wrapping unmanaged (native) resources

Finalizers add GC overhead and are only necessary when a type directly owns an unmanaged
handle that has no other managed wrapper. If you're only holding other `IDisposable` managed
objects (streams, contexts, HTTP clients), you do not need a finalizer - just dispose them in
`Dispose()`.

**Flag:** a finalizer (`~ClassName()`) added to a class whose only "resources" are other
managed `IDisposable` objects.

### 5. `IAsyncDisposable` for resources with meaningful async cleanup

If disposal genuinely involves I/O (flushing a stream, closing a network connection), prefer
implementing `IAsyncDisposable` and using `await using`, rather than forcing synchronous
disposal of something that's naturally asynchronous.

**Flag:** a class wrapping an inherently async resource (a network stream, a message queue
consumer) that only implements synchronous `IDisposable` and blocks internally to clean up.

