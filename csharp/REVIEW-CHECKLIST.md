# C# Code Review Checklist (agent-facing)

Paste this file (or point to it) as instructions for an AI code-review agent - GitHub
Copilot's PR review, or a custom bot. It is a condensed version
of the detailed standards in this directory; each item links to the file with full rationale
and examples. When reviewing a pull request, check the changed code against every relevant
item below and flag violations with a short explanation and, where useful, a suggested fix.

Only flag what's actually visible in the diff. Don't invent violations in unchanged code
outside the diff unless asked to review the whole file.

## Architecture & SOLID
See [01-solid-and-architecture.md](./01-solid-and-architecture.md)
- [ ] No business logic depending directly on `DbContext`, `HttpContext`, or `IConfiguration`.
- [ ] No "god classes" - flag classes with many unrelated responsibilities or constructors
      with 6+ injected dependencies.
- [ ] No business rules inside controllers/endpoints - they should delegate to a service.
- [ ] No service-locator pattern (`IServiceProvider.GetService<T>()` outside factories/composition root).

## Dependency Injection
See [02-dependency-injection.md](./02-dependency-injection.md)
- [ ] Constructor injection only - no property injection, no `new`-ing up collaborators that
      should be injected.
- [ ] Correct DI lifetime - flag a `Singleton` service depending on anything `Scoped`
      (captive dependency), especially `DbContext` or `IOptionsSnapshot<T>`.
- [ ] No `IServiceProvider`/`IServiceScopeFactory` injected into ordinary business logic.
- [ ] Constructors contain only field assignment - no I/O, no blocking calls.

## Configuration & Options
See [03-configuration-and-options.md](./03-configuration-and-options.md)
- [ ] No `IConfiguration` injected outside `Program.cs`/hosting extension methods.
- [ ] No string-keyed config lookups (`config["X:Y"]`) in business/service code - use bound
      options classes.
- [ ] Correct options interface: `IOptions<T>` for static config in singletons,
      `IOptionsSnapshot<T>` for per-request reload in scoped services,
      `IOptionsMonitor<T>` for live-reloading singletons.
- [ ] Options with required values have validation (`ValidateDataAnnotations`,
      `ValidateOnStart`, or `IValidateOptions<T>`).
- [ ] No secrets (connection strings, API keys, passwords) committed in `appsettings*.json` or
      anywhere else in the diff.

## Async & Concurrency
See [04-async-and-concurrency.md](./04-async-and-concurrency.md)
- [ ] No `.Result`, `.Wait()`, or `.GetAwaiter().GetResult()` on a `Task` outside justified
      low-level code.
- [ ] No `async void` except genuine UI event handlers.
- [ ] Async I/O methods accept and propagate a `CancellationToken`.
- [ ] No `Task.Run` wrapping an already-async I/O call just to "make it async."
- [ ] No unobserved fire-and-forget `Task`s with unhandled exceptions.

## Error Handling
See [05-error-handling.md](./05-error-handling.md)
- [ ] Specific exception types thrown, not bare `Exception`.
- [ ] No empty `catch` blocks; no `catch` that swallows an error silently.
- [ ] No `throw ex;` (resets stack trace) - use `throw;` or wrap as `InnerException`.
- [ ] Exceptions not used for ordinary expected control flow (e.g., "not found," validation).
- [ ] Guard clauses preferred over deeply nested `if` blocks.

## Logging & Observability
See [06-logging-and-observability.md](./06-logging-and-observability.md)
- [ ] `ILogger<T>` injected, not `Console.WriteLine`/static loggers.
- [ ] Structured message templates (`"{OrderId}"`), not string interpolation, in log calls.
- [ ] Correct log level for the situation (no routine success logged as `Error`; no real
      failures logged as `Information`).
- [ ] No secrets/PII (passwords, tokens, full card numbers) in log output.
- [ ] Exceptions logged with the exception object passed to the logger, not just `.Message`.

## API Design
See [07-api-design.md](./07-api-design.md)
- [ ] DTOs used at the API boundary, not EF Core entities returned/bound directly.
- [ ] Request DTOs validated (DataAnnotations/FluentValidation) before use.
- [ ] Correct, specific HTTP status codes (not everything `200` or `500`).
- [ ] Consistent error response shape (`ProblemDetails`), not ad hoc per-endpoint JSON.
- [ ] No stack traces/internal exception details returned to clients.
- [ ] List endpoints that can return unbounded results are paginated.

## Data Access / EF Core
See [08-data-access-ef-core.md](./08-data-access-ef-core.md)
- [ ] `DbContext` is `Scoped` - never `Singleton`, never a static field.
- [ ] Read-only queries use `AsNoTracking()`.
- [ ] No N+1 query patterns (a query inside a loop).
- [ ] No `IQueryable<T>` returned from a repository/service to outside callers.
- [ ] Schema changes go through migrations, not hand-edited SQL.
- [ ] Bulk updates/deletes use `ExecuteUpdate`/`ExecuteDelete` rather than load-all-then-loop.

## Security
See [09-security.md](./09-security.md)
- [ ] No string-concatenated/interpolated SQL - parameterized queries only.
- [ ] External input validated; no unsanitized input into file paths, shell commands, or
      redirect targets.
- [ ] `[Authorize]`/policy-based authorization used, not manual role/claim string checks.
- [ ] No hardcoded secrets/credentials anywhere in the diff.
- [ ] No custom-rolled cryptography; no `MD5`/`SHA1` for password hashing.
- [ ] CORS policy is scoped to specific origins, not `AllowAnyOrigin()` for authenticated APIs.

## Performance
See [10-performance.md](./10-performance.md)
- [ ] No obviously avoidable allocations in hot paths (string concatenation in loops, etc.).
- [ ] Filtering/paging pushed to the database query, not applied after loading everything
      into memory.
- [ ] Caching, if introduced, has a clear expiration/invalidation strategy.
- [ ] `IHttpClientFactory`/typed clients used, not `new HttpClient()` per call.

## Testing
See [11-testing.md](./11-testing.md)
- [ ] New/changed logic has corresponding tests, including edge cases and failure paths, not
      just the happy path.
- [ ] Tests follow Arrange/Act/Assert with a descriptive name indicating scenario and outcome.
- [ ] Unit tests mock/fake dependencies rather than hitting real infrastructure.
- [ ] No `Thread.Sleep` used to wait for async work in tests.

## Nullable Reference Types
See [12-nullable-reference-types.md](./12-nullable-reference-types.md)
- [ ] `<Nullable>enable</Nullable>` present for new projects.
- [ ] Null-forgiving operator (`!`) used sparingly and only with a justifying comment.
- [ ] Collection-returning methods return an empty collection, never `null`.

## Style & Naming
See [13-style-and-naming.md](./13-style-and-naming.md)
- [ ] Casing conventions followed (`PascalCase` public members, `_camelCase` private fields).
- [ ] One public type per file, filename matches the type.
- [ ] No unused `using` directives left after edits.
- [ ] Defer to the repo's own `.editorconfig` if it conflicts with anything above.

## Immutability & Records
See [14-immutability-and-records.md](./14-immutability-and-records.md)
- [ ] DTOs/value objects modeled as `record`/`record struct`, not mutable classes.
- [ ] No public mutable collection properties on classes that should own/protect their state.

## Resource Management
See [15-resource-management.md](./15-resource-management.md)
- [ ] Every locally-created `IDisposable`/`IAsyncDisposable` is wrapped in `using`.
- [ ] Injected dependencies are never manually disposed by the class that received them.

---

## How to weigh findings

- Treat this as a prioritized list, not a gate that blocks every PR on every nit. Distinguish
  correctness/security issues (should almost always be raised) from style preferences (raise,
  but don't insist a PR is blocked over them if the repo's own linting/`.editorconfig` doesn't
  already enforce it).
- If a rule here conflicts with an explicit, documented decision already in the repository
  (an ADR, a comment, an existing established pattern used consistently elsewhere), prefer
  consistency with the existing codebase and note the standards-repo item as a suggestion, not
  a hard requirement.
- These are defaults for teams that haven't decided otherwise, not universal law.
