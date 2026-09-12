# Error Handling

## 1. Throw specific exception types

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

## 2. Don't catch what you can't handle

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

## 3. Never lose the original exception

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

## 4. Don't use exceptions for expected control flow

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

## 5. Centralize translation of errors to HTTP responses

APIs should have one place (exception-handling middleware, an `IExceptionHandler`, or a
consistent exception filter) that maps domain/application exceptions to HTTP status codes and
a `ProblemDetails` body, rather than each controller action doing its own try/catch-and-map.

**Flag:** repeated try/catch-and-map-to-status-code blocks copy-pasted across multiple
controller actions instead of centralized handling.

## 6. Guard clauses over deep nesting

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
