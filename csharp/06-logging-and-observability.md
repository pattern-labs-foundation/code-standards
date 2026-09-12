# Logging & Observability

## 1. Inject `ILogger<T>`, don't use static loggers or `Console.WriteLine`

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

## 2. Use structured logging message templates, not string interpolation

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

## 3. Use the correct log level

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

## 4. Never log sensitive data

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

## 5. Log exceptions with the exception object, not just its message

```csharp
// Bad - loses stack trace and inner exception detail
logger.LogError("Failed to process order: " + ex.Message);

// Good
logger.LogError(ex, "Failed to process order {OrderId}", order.Id);
```

**Flag:** `ex.Message`/`ex.ToString()` interpolated into the message template instead of the
exception passed as the first argument to `LogError`/`LogWarning`/`LogCritical`.

## 6. Correlate logs across a request/operation

Rely on the built-in trace/correlation identifiers (`Activity.Current`, `TraceIdentifier`, or
an OpenTelemetry-based trace ID) rather than inventing ad hoc request IDs, so a single user
request can be traced across services and log entries.

**Flag:** custom, hand-rolled "request ID" generation and threading when the framework/tracing
infrastructure already provides one.

## 7. Don't log in tight loops without a reason

Logging inside a loop that runs thousands of times per request will flood the log backend and
obscure genuinely useful signal. Aggregate and log a summary instead, or drop to `Trace` level
behind a check.

**Flag:** a `LogInformation`/`LogDebug` call inside a loop with no bound on iteration count.
