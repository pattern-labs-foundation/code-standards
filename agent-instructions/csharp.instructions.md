---
applyTo: "**/*.cs,**/*.csproj,**/appsettings*.json"
---

> [!IMPORTANT]
> ## 📐 Source: [pattern-labs-foundation/code-standards](https://github.com/pattern-labs-foundation/code-standards)
>
> This file **is** the standard, not a summary of one.
>
> | | |
> |---|---|
> | 📦 **Origin** | `agent-instructions/csharp.instructions.md` |
> | 🔄 **Updates** | Sync from code-standards |
> | 💡 **Improvements** | Contributions welcome, [open a PR](https://github.com/pattern-labs-foundation/code-standards/pulls) |
> | 📄 **Licence** | MIT |

# 📐 C# Coding Standards

Apply these when reviewing or writing C# in this repository. Flag violations with the reason, not just the rule. Prioritise correctness and security over style. Only flag what is visible in the diff.

## SOLID & Architecture

### 1. Depend on abstractions, not concretions

Business logic should depend on interfaces, not concrete framework types (`HttpContext`, `DbContext`, `IConfiguration`) or concrete collaborators.

```csharp
// Bad
public class OrderService(AppDbContext db) { }

// Good
public class OrderService(IOrderRepository orders) { }
```

**Flag:** a service/domain class taking `DbContext`, `HttpContext`, `IConfiguration`, or a
static class as a direct dependency.

### 2. Single Responsibility

Watch for "god classes" that accumulate unrelated responsibilities (a `UserService` that also sends emails, builds PDFs, and validates payment cards).

**Flag:** classes with many unrelated public methods, or constructors with 6+ injected
dependencies.

### 3. Layering

Keep **Presentation** (parses requests, calls application layer, shapes responses),
**Application** (orchestrates domain logic and infrastructure), **Domain** (entities, rules,
no framework dependencies), and **Infrastructure** (EF Core, HTTP, file system) separate.

**Flag:** business rules embedded in controllers or EF Core entity configuration; `HttpClient`
or `DbContext` referenced from the domain layer.

### 4. Favor composition over inheritance

Prefer injecting collaborators over deep inheritance. Inheritance should model a genuine "is-a" relationship, not share code (use extension methods or a shared service for that).

**Flag:** inheritance chains deeper than 2 levels, or abstract base classes that exist only
for code reuse.

### 5. No service locator / ambient static access

Take dependencies through the constructor. Don't resolve them from a static locator, `IServiceProvider.GetService<T>()` in business logic, or global mutable state.

**Flag:** `IServiceProvider` injected into anything other than a factory/composition root;
static fields holding mutable service instances; `HttpContext.Current`-style ambient access.

### 6. Keep controllers/endpoints thin

An action should validate/bind input, call one application-layer method, and map the result to a response. No embedded business rules, direct EF Core queries, or multi-step orchestration.

**Flag:** actions longer than ~15-20 lines, or `if`/`switch` on business state instead of
delegating to a service.

### 7. Interface segregation

Prefer small, focused interfaces over one large interface every consumer must implement in full.

**Flag:** interfaces with 8+ methods no single implementation fully uses; "fat" repository
interfaces mixing read and write without need.

## Dependency Injection

### 1. Constructor injection only

Dependencies are provided through the constructor and stored in `readonly` fields. Avoid property injection, method injection for required dependencies, or `new`-ing collaborators inside a class.

```csharp
// Bad
public class InvoiceService { public IPaymentGateway Gateway { get; set; } }

// Good
public class InvoiceService(IPaymentGateway gateway, IEmailSender email) { }
```

**Flag:** `new SomeConcreteDependency()` inside a class that could take an interface instead;
public settable properties used to satisfy required dependencies.

### 2. Register the right lifetime

- **Singleton** - stateless or safely shared across requests. Must be thread-safe.
- **Scoped** - one instance per request/unit of work (`DbContext`, most app services).
- **Transient** - cheap, stateless, created fresh every time.

**Flag:** a `Singleton` service holding a `DbContext`, `IOptionsSnapshot<T>`, or any other
scoped dependency - a **captive dependency** that throws or silently goes stale.

### 3. Avoid injecting `IServiceProvider`/`IServiceScopeFactory` into business logic

Appropriate only in factories, background workers creating a scope per unit of work, or the composition root.

**Flag:** `IServiceProvider` as a constructor parameter on anything other than a factory or a
hosted/background service.

### 4. Register interfaces, not concrete types, when a caller needs to mock it

Register `services.AddScoped<IOrderRepository, SqlOrderRepository>();`, not the concrete type.

**Flag:** application/domain services registered and consumed by their concrete type when a
test double would reasonably be needed (anything doing I/O).

### 5. Keep constructors free of logic

Constructors only assign injected dependencies to fields. No I/O, no async work, no validation beyond null checks.

**Flag:** database calls, HTTP calls, file I/O, or `.Result`/`.Wait()` inside a constructor.

### 6. Prefer factories/`Func<T>` for runtime-parameterized creation

When a component needs a fresh instance per operation with a value known only at call time, inject a factory delegate rather than passing `IServiceProvider` around.

**Flag:** manual `Activator.CreateInstance` or reflection-based instantiation where DI could be
used instead.

## Configuration & the Options Pattern

Raw `IConfiguration` access spreads magic strings and untyped lookups through business logic. Prefer the **Options pattern** everywhere outside the composition root.

### 1. Never inject `IConfiguration` into domain/application services

`IConfiguration` should only be read from `Program.cs`/`Startup.cs` (the composition root), where it's bound into strongly-typed options classes.

```csharp
// Bad
public class EmailSender(IConfiguration config)
{
    public void Send() => _ = int.Parse(config["Smtp:Port"]); // magic string, throws if missing
}

// Good
public class SmtpOptions
{
    public const string SectionName = "Smtp";
    public required string Host { get; init; }
    public int Port { get; init; } = 587;
}

public class EmailSender(IOptions<SmtpOptions> options)
{
    private readonly SmtpOptions _options = options.Value;
}
```

**Flag:** `IConfiguration` as a constructor parameter anywhere outside `Program.cs`/hosting
extension methods; string-keyed config lookups (`config["X:Y"]`) inside business/service code.

### 2. Choose the right options interface

| Interface | Lifetime | Reloads? | Use when |
|---|---|---|---|
| `IOptions<T>` | Singleton-safe | No | Simple, rarely-changing config |
| `IOptionsSnapshot<T>` | Scoped | Per scope/request | Per-request services needing fresh config |
| `IOptionsMonitor<T>` | Singleton-safe | Live, `OnChange` | Singletons reacting to config changes |

**Flag:** `IOptionsSnapshot<T>` injected into a `Singleton` service (throws or misbehaves -
a captive-dependency variant); `IOptions<T>` used where live reload is clearly expected (e.g. feature flags meant to take effect without a restart).

### 3. Bind options explicitly and validate them at startup

```csharp
builder.Services
    .AddOptions<SmtpOptions>()
    .Bind(builder.Configuration.GetSection(SmtpOptions.SectionName))
    .ValidateDataAnnotations()
    .ValidateOnStart();
```

For cross-field rules, implement `IValidateOptions<T>` (e.g. "Port must be 587 or 465 when UseSsl is true").

**Flag:** an options class with no validation for values required for the app to function
(connection strings, API keys); missing `.ValidateOnStart()` on startup-critical options.

### 4. Options classes are plain data, named consistently

Suffix with `Options` (`SmtpOptions`). Define the section name as a `public const string SectionName` on the class itself. No behavior beyond simple computed properties.

**Flag:** the same section-name string literal repeated in multiple files instead of
referenced from one constant.

### 5. Secrets never live in `appsettings.json` or source control

Local dev: `dotnet user-secrets`. Deployed: environment variables, Key Vault, or an equivalent secret store, wired into config providers and bound into the same options classes.

**Flag:** any connection string, API key, password, or token literal committed in
`appsettings*.json` or source files.

### 6. Reflect config schema through types, not `dynamic`/`JObject`

If a section has a known shape, bind it to a class.

**Flag:** `IConfigurationSection` passed around and indexed ad hoc instead of bound to a type.

## Async & Concurrency

### 1. Async all the way down - never block on async code

Never call `.Result`, `.Wait()`, or `.GetAwaiter().GetResult()` on a `Task` to "make it work" - a common source of deadlocks and thread-pool starvation.

```csharp
// Bad
var user = _userService.GetUserAsync(id).Result;

// Good
var user = await _userService.GetUserAsync(id);
```

**Flag:** any `.Result`, `.Wait()`, `.GetAwaiter().GetResult()` on a `Task` outside `Main` in a
console app or genuinely justified low-level interop.

### 2. Never use `async void` except for true event handlers

`async void` methods can't be awaited and their exceptions can't be caught - they crash the process or vanish instead.

**Flag:** `async void` on anything other than an event handler; missing `Async` suffix on
async method names.

### 3. Accept and honor `CancellationToken`

Any long-running async method (I/O, HTTP, DB) should accept a `CancellationToken` and pass it through to every awaited call.

**Flag:** async methods doing I/O with no `CancellationToken` parameter; a token accepted but
never passed to inner awaited calls.

### 4. Don't use `Task.Run` to "make something async" on the server

`Task.Run` offloads CPU-bound work - it doesn't speed up I/O-bound work and just wastes a thread-pool hop in ASP.NET Core request handling.

**Flag:** `Task.Run(() => someAsyncIoCall().Result)` or similar wrapping patterns.

### 5. `ConfigureAwait(false)` in library code

Avoids unnecessary context-capture overhead in reusable libraries. Not required in typical ASP.NET Core app code, but good practice in shared libraries.

**Flag:** inconsistent use within a single library rather than a project-wide default.

### 6. Avoid unobserved fire-and-forget tasks

If a task's result/exceptions genuinely don't need awaiting, don't just drop the `Task` - await it through a background queue, or wrap it with exception logging.

```csharp
// Bad
_ = SendAnalyticsEventAsync(evt); // exception silently swallowed

// Good
_ = Task.Run(async () =>
{
    try { await SendAnalyticsEventAsync(evt); }
    catch (Exception ex) { logger.LogError(ex, "Failed to send analytics event"); }
});
```

**Flag:** a discarded (`_ =`) or otherwise unawaited `Task` with no visible error handling.

### 7. Use `IAsyncEnumerable<T>` for streaming, not materializing everything into memory

Prefer `IAsyncEnumerable<T>` + `await foreach` over building a full `List<T>` first for large or unbounded sequences.

**Flag:** `.ToListAsync()`/`.ToList()` on a large/unbounded query purely to iterate once.

## Error Handling

### 1. Throw specific exception types

Throw the most specific built-in exception that fits, or a custom domain exception that carries meaning. Avoid throwing bare `Exception`.

**Flag:** `throw new Exception(...)`; custom exceptions with no meaningful context over a
built-in type.

### 2. Don't catch what you can't handle

Only catch an exception if the code can recover, add context, or translate it into a different error shape at a boundary. Otherwise let it propagate.

```csharp
// Bad
try { await _repo.SaveAsync(order); } catch { }

// Good
try { await _repo.SaveAsync(order); }
catch (DbUpdateConcurrencyException ex) { throw new OrderConflictException(order.Id, ex); }
```

**Flag:** empty `catch` blocks; `catch (Exception)` that only logs and swallows without
rethrowing outside a top-level handler; a `catch` that "handles" an error by returning `null`/`false` and hiding the cause.

### 3. Never lose the original exception

Wrap the original as `InnerException` rather than throwing a new exception with only a string message. Never use `throw ex;` (resets the stack trace) - use `throw;` or wrap it.

**Flag:** `throw ex;` inside a catch block; a caught exception not passed as `innerException`
to whatever replaces it.

### 4. Don't use exceptions for expected control flow

If a failure is a normal outcome ("not found", "validation failed"), prefer a `Result`-style return or a `TryGetX` pattern over throwing/catching.

```csharp
// Bad
public Order GetOrder(int id) => _orders.Find(id) ?? throw new OrderNotFoundException(id);

// Good
public bool TryGetOrder(int id, out Order? order)
{
    order = _orders.Find(id);
    return order is not null;
}
```

**Flag:** exceptions thrown and caught in the same method purely to implement branching;
validation modeled as exceptions in hot paths where many calls are expected to fail.

### 5. Centralize translation of errors to HTTP responses

One place (exception-handling middleware, `IExceptionHandler`, or a consistent filter) maps exceptions to status codes and a `ProblemDetails` body.

**Flag:** repeated try/catch-and-map-to-status-code blocks copy-pasted across controllers.

### 6. Guard clauses over deep nesting

Validate preconditions early and return/throw, rather than nesting the happy path.

**Flag:** nesting depth of 3+ purely from defensive `if` checks that could be guard clauses.

## Logging & Observability

### 1. Inject `ILogger<T>`, don't use static loggers or `Console.WriteLine`

**Flag:** `Console.WriteLine`/`Debug.WriteLine` for application logging; static/global logger
instances instead of `ILogger<T>` injected per class.

### 2. Use structured logging message templates, not string interpolation

```csharp
// Bad
logger.LogInformation($"Processed order {order.Id}");

// Good
logger.LogInformation("Processed order {OrderId}", order.Id);
```

**Flag:** `$"..."` interpolated strings or concatenation passed as the log message.

### 3. Use the correct log level

Trace (verbose diagnostics) < Debug (dev-only) < Information (normal flow) < Warning (recoverable, worth a look) < Error (failed operation) < Critical (needs immediate attention).

**Flag:** `LogError`/`LogCritical` for expected/handled conditions; routine success logged at
`Warning`+; high-volume hot-path logging at `Information` that should be `Debug`/`Trace`.

### 4. Never log sensitive data

Passwords, tokens, API keys, connection strings, and PII must never appear in log output, including exception messages.

**Flag:** any secret, token, password, or connection string interpolated into a log call or
exception message; unredacted full request/response bodies that may contain PII.

### 5. Log exceptions with the exception object, not just its message

```csharp
// Bad
logger.LogError("Failed: " + ex.Message);

// Good
logger.LogError(ex, "Failed to process order {OrderId}", order.Id);
```

**Flag:** `ex.Message`/`ex.ToString()` interpolated into the template instead of the exception
passed as the first argument.

### 6. Correlate logs across a request/operation

Rely on built-in trace/correlation identifiers (`Activity.Current`, `TraceIdentifier`) rather than inventing ad hoc request IDs.

**Flag:** custom, hand-rolled request-ID generation when tracing infrastructure already
provides one.

### 7. Don't log in tight loops without a reason

Aggregate and log a summary instead, or drop to `Trace` behind a check.

**Flag:** a `LogInformation`/`LogDebug` call inside a loop with no bound on iteration count.

## API Design (ASP.NET Core)

### 1. Use DTOs at the boundary, never expose EF Core entities directly

Avoids over-posting, accidental serialization of navigation properties, and coupling the API contract to the database schema.

```csharp
// Bad
[HttpGet("{id}")] public async Task<Order> Get(int id) => await _db.Orders.FindAsync(id);

// Good
[HttpGet("{id}")] public async Task<OrderResponse> Get(int id) =>
    (await _orderService.GetAsync(id)).ToResponse();
```

**Flag:** EF Core entity types as controller parameters or return types; a request DTO with
more fields than the client should be able to set (e.g. `IsAdmin` on a signup DTO).

### 2. Validate all external input

Use DataAnnotations or FluentValidation on request DTOs, and ensure model validation is actually enforced.

**Flag:** request DTOs with real constraints but no validation attributes; `ModelState.IsValid`
checked inconsistently or not at all.

### 3. Return correct, specific HTTP status codes

`200`/`201`/`204` for success, `400` for validation errors, `401`/`403` for authentication/authorization (who-are-you vs. you-can't-do-this), `404` for missing resources, `409` for conflicts, `500` only for genuinely unexpected errors.

**Flag:** every error path returning `400`/`500` regardless of cause; `200 OK` with an error
payload/flag inside the body instead of a real status code.

### 4. Use `ProblemDetails` for error responses

RFC 9457's `ProblemDetails` gives clients a consistent error shape. Don't invent a bespoke error JSON shape per endpoint.

**Flag:** ad hoc `{ "error": "..." }` shapes that differ between endpoints.

### 5. Never leak internal details to clients

Stack traces, internal file paths/SQL, and internal type names should never reach a production response body.

**Flag:** `ex.ToString()`/`ex.StackTrace` returned in a response reachable in production;
`UseDeveloperExceptionPage` not gated behind an environment check.

### 6. Version your API deliberately

Pick one strategy (URL segment, header, or query string) and apply it consistently.

**Flag:** a breaking change to an existing endpoint's contract with no version bump or
migration plan.

### 7. Paginate collection endpoints

Any endpoint that can return an unbounded number of items must support pagination.

**Flag:** a `GET` list endpoint with no pagination parameters querying an unbounded table.

### 8. Async all the way in controllers/handlers

Controller actions doing I/O should be `async Task<T>`, accept a `CancellationToken`, and pass it through.

**Flag:** synchronous actions wrapping I/O with `.Result`/`.Wait()`.

## Data Access & EF Core

### 1. `DbContext` is scoped, never singleton or static

Not thread-safe, designed to be short-lived. Registering it `Singleton`, storing it statically, or sharing one instance across concurrent operations causes corruption or exceptions.

**Flag:** `AddDbContext` lifetime overridden to `Singleton`; a static field holding a
`DbContext`; a `DbContext` captured in a background task that outlives its scope.

### 2. Use `AsNoTracking()` for read-only queries

Avoids change-tracker overhead for data that's never mutated: chain `.AsNoTracking()` onto queries whose results are only read, never saved back.

**Flag:** queries feeding read-only views/DTOs/API responses with no `AsNoTracking()`.

### 3. Avoid N+1 queries

Use `.Include()`/`.ThenInclude()` or projection to fetch related data in one query, not per item in a loop.

**Flag:** database queries inside a loop; lazy-loading proxies relied on implicitly in hot
paths.

### 4. Project to DTOs instead of loading full entities when possible

`.Select()` into a DTO when only a few fields are needed - reduces data transferred and avoids unnecessary tracking.

**Flag:** an endpoint loading full entities (all columns, included relations) to expose 2-3
fields.

### 5. Don't expose `IQueryable<T>` outside the data-access layer

Leaks the ability for callers to compose arbitrary queries from anywhere. Repositories should return materialized results or accept explicit query parameters.

**Flag:** a repository/service method returning `IQueryable<T>` consumed outside the
data-access layer.

### 6. Keep entity classes focused on state and simple invariants

Entities may enforce simple self-contained invariants, but shouldn't depend on external services, call the database, or contain orchestration logic.

**Flag:** entity classes with injected dependencies, static service-locator calls, or methods
that perform I/O.

### 7. Use migrations, never hand-edit the schema

All schema changes go through EF Core migrations checked into source control.

**Flag:** raw SQL DDL outside the migrations folder; a migration edited after being applied to
a shared environment instead of superseded by a new one.

### 8. Use `ExecuteUpdate`/`ExecuteDelete` for bulk operations

```csharp
// Bad
var orders = await _db.Orders.Where(o => o.Status == "Pending").ToListAsync();
foreach (var o in orders) o.Status = "Cancelled";
await _db.SaveChangesAsync();

// Good
await _db.Orders.Where(o => o.Status == "Pending")
    .ExecuteUpdateAsync(s => s.SetProperty(o => o.Status, "Cancelled"));
```

**Flag:** load-all-then-loop-and-save patterns for bulk updates/deletes with no per-row logic.

### 9. Wrap multi-step writes in a transaction

If a unit of work involves multiple `SaveChangesAsync` calls that must succeed or fail together, wrap them in an explicit transaction.

**Flag:** multiple sequential `SaveChangesAsync()` calls for one logical operation with no
surrounding transaction or rollback logic.

## Security

### 1. Never build SQL with string concatenation

```csharp
// Bad
var sql = $"SELECT * FROM Orders WHERE UserId = '{userId}'";

// Good
var orders = await _db.Orders
    .FromSqlInterpolated($"SELECT * FROM Orders WHERE UserId = {userId}").ToListAsync();
```

**Flag:** string concatenation/interpolation building SQL from user input; `FromSqlRaw` with
concatenated input instead of `FromSqlInterpolated`/parameters.

### 2. Validate and sanitize all external input

Treat query parameters, route values, bodies, headers, and file uploads as untrusted. Encode output for its destination (HTML, URL, shell argument, log line).

**Flag:** user input passed into a file path (path traversal), a shell command
(`Process.Start`), a redirect URL (open redirect), or rendered into HTML unencoded.

### 3. Use the framework's authentication/authorization, don't hand-roll checks

```csharp
// Bad
if (User.FindFirst("role")?.Value != "Admin") return Forbid();

// Good
[Authorize(Policy = "RequireAdmin")]
```

**Flag:** manual claim/role string comparisons instead of `[Authorize]`/policies; an endpoint
mutating or exposing sensitive data with no `[Authorize]` and no documented reason.

### 4. Secrets never live in source control

No API keys, connection strings, certificates, or credentials committed anywhere, including test fixtures or commented-out code.

**Flag:** any credential-shaped literal in a diff; `.env` files committed instead of
`.gitignore`d.

### 5. Enforce HTTPS and secure headers

`UseHttpsRedirection()` and HSTS enabled for production. Auth cookies must be `HttpOnly`, `Secure`, and `SameSite` appropriately scoped.

**Flag:** auth cookies without `HttpOnly`/`Secure`; HTTPS redirection disabled outside local
dev.

### 6. Configure CORS with the minimum necessary scope

Avoid `AllowAnyOrigin()` combined with credentials, and wildcard origins for authenticated APIs.

**Flag:** `AllowAnyOrigin()` on a policy applied to authenticated endpoints; workarounds that
dynamically echo back any `Origin` header alongside credentials.

### 7. Don't roll your own cryptography

Use `System.Security.Cryptography` or ASP.NET Core Identity's password hasher. Never implement a custom scheme, and never use `MD5`/`SHA1` for password hashing.

**Flag:** custom XOR/rotation "encryption"; `MD5`/`SHA1` for password hashes instead of a
purpose-built hasher; a fixed/hardcoded key or IV.

### 8. Deserialize untrusted data safely

Prefer `System.Text.Json` with explicit types over `BinaryFormatter` or unrestricted polymorphic deserialization. Limit request body and collection sizes.

**Flag:** `BinaryFormatter`/`NetDataContractSerializer` on client-originated data; unrestricted
polymorphic JSON deserialization accepting attacker-controlled type names.

### 9. Least privilege for credentials and connections

Database users, service accounts, and API keys should have only the permissions the app actually needs, with separate credentials per environment.

**Flag:** a connection string using an admin/superuser account for routine queries; a single
shared API key reused across environments.

## Performance

### 1. Measure before optimizing

Don't restructure clear, correct code for performance without a measured reason (a profiler result, benchmark, or known hot path).

**Flag:** performance-motivated changes (manual loops replacing LINQ, caching) with no stated
measurement or hot path justifying it.

### 2. Avoid unnecessary allocations in hot paths

```csharp
// Bad
var result = "";
foreach (var item in items) result += item.Name + ", ";

// Good
var sb = new StringBuilder();
foreach (var item in items) sb.Append(item.Name).Append(", ");
```

**Flag:** string concatenation (`+=`) inside a loop; repeated `.ToList()`/`.ToArray()` chained
purely to satisfy LINQ syntax rather than necessity.

### 3. Don't fetch more data than you need

Push filtering, projection, and pagination down to the database query rather than loading everything then filtering in code.

**Flag:** `.Where()`/`.Take()`/`.Skip()` applied to an already-materialized collection when it
could be part of the `IQueryable`.

### 4. Cache deliberately, with a clear invalidation story

Every cache needs an explicit expiration or invalidation trigger.

**Flag:** caching with no expiration/invalidation strategy; a cache used for data that must
always be current (account balances, permission checks) without justified staleness tolerance.

### 5. Use streaming APIs for large payloads

Stream large request/response bodies and query results rather than buffering the entire payload in memory.

**Flag:** an endpoint reading a full large upload into a `byte[]`/`MemoryStream` before it's
needed; large results forced into one in-memory `List<T>` when only iterated once.

### 6. Reuse `HttpClient` via `IHttpClientFactory`

Never `new HttpClient()` per call - can exhaust sockets under load. Use `IHttpClientFactory`.

**Flag:** `new HttpClient()` instantiated per method/request instead of a registered typed
client.

### 7. Be cautious with reflection in hot paths

Cache reflection results (delegates, compiled expressions) if reflection is unavoidable in a hot path.

**Flag:** reflection calls repeated inside a loop or per-request instead of computed once and
cached.

## Testing

### 1. Arrange, Act, Assert

Set up state, perform the action under test, assert the outcome - don't interleave assertions with setup.

**Flag:** tests with assertions scattered through setup; a single test asserting many unrelated
behaviors.

### 2. One behavior per test, descriptive names

`MethodName_Scenario_ExpectedResult` so a failing test's name alone tells you what broke.

**Flag:** test names like `Test1` that don't describe the scenario; one test method covering
multiple unrelated scenarios.

### 3. Mock/fake interfaces, not concrete infrastructure

Substitute collaborators via interfaces. Tests needing real infrastructure belong in a separate integration suite.

**Flag:** a "unit test" opening a real database connection or making a real HTTP call;
integration tests mixed indiscriminately into the unit test project.

### 4. Don't test private implementation details

Test observable behavior through the public API, not private methods or state via reflection.

**Flag:** tests invoking private methods or reading private fields via reflection; tests that
break on implementation changes with no change to public behavior.

### 5. Deterministic tests

Inject a clock abstraction (`TimeProvider`) instead of calling `DateTime.Now` directly. Avoid `Thread.Sleep` to wait for async work - await it instead.

**Flag:** `Thread.Sleep` waiting for async work; direct `DateTime.Now`/`UtcNow` in code under
test with no injectable clock; tests that pass/fail differently by run order.

### 6. Cover edge cases and failure paths, not just the happy path

Include the typical case, boundary conditions, and failure/error paths.

**Flag:** a class with meaningful branching/error handling tested only on its success path.

### 7. Keep test setup readable - use builders/object mothers for complex objects

Use a test data builder with sensible defaults rather than repeating a large object literal in every test.

**Flag:** the same large multi-field construction duplicated near-identically across many
tests.

## Nullable Reference Types

### 1. Enable nullable reference types project-wide, and make violations build errors

`<Nullable>enable</Nullable>` alone only warns. Add `TreatWarningsAsErrors` so a possible null that isn't handled fails the build.

```xml
<PropertyGroup>
  <Nullable>enable</Nullable>
  <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
</PropertyGroup>
```

Existing projects migrating should enable `#nullable enable` per-file first, and turn on `TreatWarningsAsErrors` once the codebase is clean of warnings - suppress a specific holdout narrowly (`#pragma warning disable`/`<NoWarn>`) rather than leaving the switch off indefinitely.

**Flag:** a `.csproj` with `<Nullable>disable</Nullable>` (or missing) for a recently started
project with no migration plan; `<Nullable>enable</Nullable>` with no `TreatWarningsAsErrors` once there's no legacy warning backlog left.

### 2. Avoid the null-forgiving operator (`!`) without justification

`!` suppresses a real warning without a runtime check - every use is a place a `NullReferenceException` can still happen.

**Flag:** `!` used where a null check, guard clause, or pattern match would resolve it
properly; `!` on a non-obvious case with no explanation of why the invariant holds.

### 3. Model required state with `required` members, not nullable-then-checked

```csharp
// Bad
public class Order { public string? CustomerName { get; set; } }

// Good
public class Order { public required string CustomerName { get; init; } }
```

**Flag:** a property made nullable purely because it's set slightly after construction, not
because absence is a genuine valid state.

### 4. Don't return null for collections

A method returning a collection type should return an empty collection, never `null`.

**Flag:** a collection-returning method with a nullable return type, or that returns `null` in
any branch.

### 5. Prefer pattern matching over separate null checks plus casts

```csharp
// Bad
if (result != null && result is SuccessResult) { var s = (SuccessResult)result; }

// Good
if (result is SuccessResult success) { }
```

**Flag:** a null check immediately followed by a separate cast that could be one `is` pattern.

## Style & Naming

Defaults, overridden by the repo's own `.editorconfig` where one exists.

### 1. Casing

`PascalCase` for types/public members/methods/namespaces; `camelCase` for locals/parameters; `_camelCase` for private fields; `PascalCase` for constants (not `ALL_CAPS`); interfaces prefixed `I`.

**Flag:** public members in `camelCase`; private fields inconsistently missing the leading
underscore; `ALL_CAPS` constants.

### 2. One public type per file, filename matches the type name

Small private/internal helpers tightly coupled to the main type may live alongside it.

**Flag:** a file with multiple unrelated public types; a filename that doesn't match its
primary public type.

### 3. File-scoped namespaces

Prefer file-scoped (`namespace MyApp.Orders;`) over block-scoped for C# 10+ projects.

**Flag:** block-scoped namespace braces newly introduced where the codebase otherwise uses
file-scoped consistently.

### 4. `var` when the type is obvious, explicit type when it isn't

**Flag:** `var` where the right-hand side gives no hint of the type, especially in public API
signatures.

### 5. Expression-bodied members for simple one-liners only

**Flag:** expression-bodied members whose logic spans multiple conceptual steps.

### 6. Avoid `#region` as a substitute for splitting a class

Regions often hide a class that's grown too large. Extract cohesive member groups into their own classes instead.

**Flag:** `#region` blocks organizing what are effectively several unrelated responsibilities.

### 7. Consistent `using` directive placement and ordering

System namespaces first, then third-party, then the project's own, each group blank-line separated.

**Flag:** `using` statements scattered inconsistently with the codebase's convention; unused
`using` directives left after refactoring.

### 8. Avoid unclear abbreviations

Prefer full names over unclear abbreviations (`customer` not `cust`). Loop variables in short loops (`i`, `j`) are fine.

**Flag:** unclear or ambiguous abbreviations in public API member names.

## Immutability & Records

### 1. Use `record`/`record struct` for DTOs and value objects

```csharp
// Bad
public class Money { public decimal Amount { get; set; } public string Currency { get; set; } }

// Good
public record Money(decimal Amount, string Currency);
```

**Flag:** a plain mutable `class` for a type whose entire purpose is carrying a fixed set of
values with value-based equality.

### 2. Prefer immutable state by default

Default to `init`-only/`required init` properties. Mutable public setters should be a deliberate choice for genuinely mutable domain state, not the default.

**Flag:** public mutable setters on properties that should only be set once, or should only
change through a domain method enforcing invariants.

### 3. Don't expose mutable collections publicly

```csharp
// Bad
public List<OrderItem> Items { get; } = new();

// Good
private readonly List<OrderItem> _items = new();
public IReadOnlyList<OrderItem> Items => _items;
```

**Flag:** a public property exposing a mutable collection representing owned, invariant-bearing
state.

### 4. Understand value equality with records

Records compare by value, not reference. If a type has identity independent of its field values (most entities with a database-generated `Id`), use a `class` instead.

**Flag:** a database entity with mutable identity modeled as a `record` where full-field value
equality would be semantically wrong.

### 5. `with`-expressions for producing modified copies

**Flag:** manual reconstruction of every field of a record just to change one.

## Resource Management (`IDisposable`/`IAsyncDisposable`)

### 1. Use `using` for anything disposable

```csharp
// Bad
var stream = File.OpenRead(path); // leaked if ReadAsync throws

// Good
using var stream = File.OpenRead(path);
```

**Flag:** a locally-created `IDisposable`/`IAsyncDisposable` with no `using` and no other clear
disposal path.

### 2. Don't dispose dependencies you don't own

If a disposable was injected via DI, don't dispose it yourself - the container owns its lifetime.

**Flag:** `.Dispose()`/`using` applied to a constructor-injected dependency.

### 3. Implement `IDisposable` correctly when a class directly owns scarce resources

A class owning a file handle, socket, or self-created `DbConnection` should implement `IDisposable` (and `IAsyncDisposable` if cleanup is meaningfully async) and dispose owned resources.

**Flag:** a class holding a disposable field with no `IDisposable` implementation; a
`Dispose()` that doesn't dispose the fields it owns.

### 4. Avoid finalizers unless directly wrapping unmanaged (native) resources

If you only hold other managed `IDisposable` objects, you don't need a finalizer.

**Flag:** a finalizer (`~ClassName()`) on a class whose only resources are other managed
`IDisposable` objects.

### 5. `IAsyncDisposable` for resources with meaningful async cleanup

Prefer `IAsyncDisposable` + `await using` when disposal genuinely involves I/O.

**Flag:** a class wrapping an inherently async resource that only implements synchronous
`IDisposable` and blocks internally to clean up.
