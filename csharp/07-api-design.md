# API Design (ASP.NET Core)

## 1. Use DTOs at the boundary, never expose EF Core entities directly

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

## 2. Validate all external input

Use DataAnnotations or FluentValidation on request DTOs, and ensure model validation is
actually enforced (`ApiController` attribute enables automatic 400 responses; for minimal
APIs, validate explicitly or via a validation filter).

**Flag:** request DTOs with no validation attributes on fields that have real constraints
(required strings, numeric ranges, string lengths); controller actions that read
`ModelState.IsValid` inconsistently or not at all.

## 3. Return correct, specific HTTP status codes

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

## 4. Use `ProblemDetails` for error responses

ASP.NET Core's `ProblemDetails` (RFC 9457) gives clients a consistent error shape
(`type`, `title`, `status`, `detail`, `instance`, plus `errors` for validation problems).
Don't invent a bespoke error JSON shape per endpoint.

**Flag:** ad hoc `{ "error": "..." }` or `{ "message": "..." }` response shapes that differ
between endpoints instead of a single consistent error contract.

## 5. Never leak internal details to clients

Stack traces, exception messages containing internal file paths/SQL/connection strings, and
internal type names should never reach the client response body in production. Show detailed
errors only in development (`app.UseDeveloperExceptionPage()` gated by environment).

**Flag:** `ex.ToString()`/`ex.StackTrace` returned in a response body reachable in production;
`UseDeveloperExceptionPage` not gated behind an environment check.

## 6. Version your API deliberately

Pick one strategy (URL segment `/v1/...`, header, or query string) and apply it consistently;
don't silently break existing clients by changing a response shape on an existing endpoint.

**Flag:** a breaking change (removed field, changed field type, changed semantics) made to an
existing endpoint's contract without a version bump or explicit migration plan.

## 7. Paginate collection endpoints

Any endpoint that can return an unbounded number of items must support pagination
(page/pageSize or cursor-based) rather than returning the entire table.

**Flag:** a `GET` list endpoint with no pagination parameters querying a table that can grow
without bound.

## 8. Async all the way in controllers/handlers

Controller actions and minimal API handlers that do I/O should be `async Task<T>`, accept a
`CancellationToken` (minimal APIs get one injected automatically; controllers can bind one as a
parameter), and pass it through.

**Flag:** synchronous controller actions wrapping I/O calls with `.Result`/`.Wait()` (see
[04-async-and-concurrency.md](./04-async-and-concurrency.md)).
