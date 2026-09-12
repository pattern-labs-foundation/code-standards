# Security

## 1. Never build SQL with string concatenation

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

## 2. Validate and sanitize all external input

Treat query parameters, route values, request bodies, headers, and file uploads as untrusted.
Validate shape, length, and range; encode output appropriately for its destination (HTML, a
URL, a shell argument, a log line).

**Flag:** user-controlled input passed directly into a file path (path traversal risk), a
shell command (`Process.Start` with unsanitized arguments), a redirect URL (open redirect), or
rendered into HTML without encoding.

## 3. Use the framework's authentication/authorization, don't hand-roll checks

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

## 4. Secrets never live in source control

See [03-configuration-and-options.md](./03-configuration-and-options.md#5-secrets-never-live-in-appsettingsjson-or-source-control).
No API keys, connection strings, certificates, or credentials committed to the repository,
including in test fixtures or commented-out code.

**Flag:** any credential-shaped literal in a diff; `.env` files committed instead of
`.gitignore`d.

## 5. Enforce HTTPS and secure headers

`UseHttpsRedirection()` and HSTS should be enabled for production. Cookies carrying auth state
must be `HttpOnly`, `Secure`, and `SameSite` appropriately scoped.

**Flag:** cookies used for authentication without `HttpOnly`/`Secure` flags; HTTPS redirection
disabled outside of local development.

## 6. Configure CORS with the minimum necessary scope

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

## 7. Don't roll your own cryptography

Use the platform's vetted APIs (`System.Security.Cryptography`, ASP.NET Core Identity's
password hasher) for hashing, encryption, and token generation. Never implement a custom
hashing/encryption scheme, and never use `MD5`/`SHA1` for password hashing.

**Flag:** custom XOR/rotation-based "encryption"; `MD5`/`SHA1` used for password hashes instead
of a purpose-built password hasher (e.g., PBKDF2/BCrypt/Argon2 as wrapped by Identity or a
vetted library); a fixed/hardcoded encryption key or IV.

## 8. Deserialize untrusted data safely

Prefer `System.Text.Json` with explicit types over `BinaryFormatter` (obsolete and unsafe for
untrusted input) or unrestricted polymorphic deserialization. Set reasonable limits on request
body size and array/collection sizes to avoid resource-exhaustion via oversized payloads.

**Flag:** `BinaryFormatter`, `NetDataContractSerializer`, or similarly unsafe legacy
serializers used on any data that could originate from a client; unrestricted polymorphic
JSON deserialization (`TypeNameHandling`-equivalent) accepting attacker-controlled type names.

## 9. Least privilege for credentials and connections

Database users, service accounts, and API keys used by the application should have only the
permissions the application actually needs, not broad admin-equivalent access, and different
environments (dev/staging/prod) should use separate credentials.

**Flag:** a connection string using a database admin/superuser account for routine application
queries; a single shared API key/secret reused across all environments.
