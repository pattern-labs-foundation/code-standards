# Nullable Reference Types

## 1. Enable nullable reference types project-wide, and make violations build errors

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

## 2. Avoid the null-forgiving operator (`!`) without justification

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

## 3. Model required state with `required` members and constructors, not nullable-then-checked

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

## 4. Don't return null for collections

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

## 5. Prefer pattern matching over separate null checks plus casts

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
