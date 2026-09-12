---
applyTo: "**/*.cs,**/*.csproj,**/appsettings*.json"
---
<!--
  Copy this file to `.github/instructions/csharp.instructions.md` in the consuming repository.
  GitHub Copilot applies path-scoped instructions files (the `applyTo` glob above) only when
  reviewing/generating code for matching files - useful in multi-language repos so this
  doesn't leak into reviews of frontend/infra code.

  This mirrors csharp/REVIEW-CHECKLIST.md in this standards repo. Update both together, or
  replace this file's body with a vendored copy of that checklist to avoid drift.
-->

# C# Coding Standards

Full detail and rationale: https://github.com/<org>/code-standards/tree/main/csharp

## Architecture
- No business logic depending directly on `DbContext`, `HttpContext`, or `IConfiguration`.
- No god classes; no constructors with 6+ injected dependencies.
- Controllers/endpoints stay thin - delegate to a service, no embedded business rules.

## Dependency injection
- Constructor injection only.
- Correct DI lifetime: never inject a `Scoped` dependency (e.g. `DbContext`,
  `IOptionsSnapshot<T>`) into a `Singleton`.
- No `IServiceProvider` injected into ordinary business logic.

## Configuration
- No `IConfiguration` injected outside the composition root - use bound `IOptions<T>` /
  `IOptionsSnapshot<T>` / `IOptionsMonitor<T>` instead.
- Options with required values must be validated at startup
  (`ValidateDataAnnotations().ValidateOnStart()` or `IValidateOptions<T>`).
- No secrets in `appsettings*.json` or anywhere in source.

## Async
- No `.Result` / `.Wait()` / `.GetAwaiter().GetResult()`.
- No `async void` outside real event handlers.
- Async I/O methods accept and propagate `CancellationToken`.
- No `Task.Run` wrapping an already-async call.

## Error handling
- Specific exception types, not bare `Exception`.
- No empty/swallowing `catch` blocks; use `throw;` not `throw ex;`.
- No exceptions used for expected control flow.

## Logging
- `ILogger<T>` with structured message templates, not string interpolation.
- Correct log level; no secrets/PII in log output.
- Exceptions logged via the `ILogger` exception overload, not just `.Message`.

## Data access (EF Core)
- `DbContext` is scoped - never singleton/static.
- `AsNoTracking()` on read-only queries; no queries inside loops (N+1).
- No `IQueryable<T>` returned outside the data-access layer.
- Schema changes via migrations only.

## API design
- DTOs at the boundary, never EF Core entities bound/returned directly.
- Request DTOs validated; correct/specific HTTP status codes; `ProblemDetails` error shape.
- List endpoints paginated.

## Security
- Parameterized queries only, never string-built SQL.
- `[Authorize]`/policies, not manual role/claim checks.
- No custom cryptography; no `MD5`/`SHA1` password hashing.

## Testing
- New/changed logic has tests covering edge cases and failure paths, not only the happy path.
- Unit tests fake/mock dependencies rather than hitting real infrastructure.

## Nullable reference types
- `<Nullable>enable</Nullable>` on for new projects, paired with
  `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` once the project has no legacy warning
  backlog - otherwise a possible null is only a warning and the build still succeeds.
- Null-forgiving operator (`!`) used sparingly and only with a comment justifying why the
  invariant actually holds.
- Collection-returning methods return an empty collection, never `null`.

## Style
- `PascalCase` public members, `_camelCase` private fields, one public type per file.
- Defer to this repo's `.editorconfig` where it's more specific than this list.
