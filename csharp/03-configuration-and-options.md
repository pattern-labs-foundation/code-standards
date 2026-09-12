# Configuration & the Options Pattern

This is one of the most commonly violated standards in .NET codebases - raw `IConfiguration`
access spreads magic strings and untyped lookups through business logic. Prefer the
**Options pattern** everywhere outside the composition root.

## 1. Never inject `IConfiguration` into domain/application services

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

## 2. Choose the right options interface

| Interface | Lifetime | Reloads on config change? | Use when |
|---|---|---|---|
| `IOptions<T>` | Singleton-safe | No (captures value at first resolution) | Simple, rarely-changing config; safe to inject into singletons |
| `IOptionsSnapshot<T>` | Scoped | Yes, recomputed per scope/request | Per-request services that should see updated config on the next request |
| `IOptionsMonitor<T>` | Singleton-safe | Yes, live, with `OnChange` callback | Singletons/background services that need to react to config changes immediately |

**Flag:** `IOptionsSnapshot<T>` injected into a `Singleton`-registered service (this throws or
silently misbehaves at runtime - it's a captive-dependency variant); `IOptions<T>` used where
live reload is clearly expected by the feature (e.g., feature flags meant to take effect
without a restart).

## 3. Bind options explicitly and validate them at startup

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

## 4. Options classes are plain data, named consistently

- Suffix the class with `Options` (`SmtpOptions`, `JwtOptions`).
- Define the config section name as a `public const string SectionName` on the class itself,
  so it isn't duplicated as a string literal at every registration/consumption site.
- No behavior/methods beyond simple computed properties - options classes are data, not
  services.

**Flag:** the same section-name string literal (`"Smtp"`) repeated in multiple files instead
of referenced from a single constant.

## 5. Secrets never live in `appsettings.json` or source control

- Local development: `dotnet user-secrets`.
- Deployed environments: environment variables, Azure Key Vault, AWS Secrets Manager/Parameter
  Store, or an equivalent secret store - wired into configuration providers, then bound into
  the same strongly-typed options classes.
- `appsettings.json` may contain non-secret defaults and structure, never real credentials,
  connection strings with passwords, or API keys.

**Flag:** any connection string, API key, password, or token literal committed in
`appsettings*.json`, source files, or CI config; `.gitignore` missing entries for
`appsettings.*.local.json` or similar if that convention is used.

## 6. Reflect config schema through types, not `dynamic`/`JObject`

If a section has known shape, bind it to a class. Reach for `IConfiguration.GetSection(...)`
without binding, or dynamic/JSON-object access, only for genuinely dynamic/unknown-shape data.

**Flag:** `IConfigurationSection` passed around and indexed ad hoc instead of bound to a type.
