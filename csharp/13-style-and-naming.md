# Style & Naming

These follow the conventions in Microsoft's C# coding conventions and the .NET runtime's own
style guide. An agent reviewing style should treat these as defaults a repo's own `.editorconfig`
can override - if a repo has an `.editorconfig` with different rules, that file wins.

## 1. Casing

- `PascalCase` for types, public members, methods, properties, events, and namespaces.
- `camelCase` for local variables and method parameters.
- `_camelCase` (leading underscore) for private instance fields.
- `PascalCase` for constants (`public const int MaxRetries = 3;`), not `ALL_CAPS`.
- Interfaces are prefixed with `I` (`IOrderRepository`).

**Flag:** public members in `camelCase`; private fields with no leading underscore mixed
inconsistently with ones that have it in the same file; `ALL_CAPS` constants.

## 2. One public type per file, filename matches the type name

`OrderService.cs` contains `public class OrderService`. Small private/internal helper types
tightly coupled to the main type may live alongside it, but another unrelated public type
should not.

**Flag:** a file containing multiple unrelated public types; a filename that doesn't match the
primary public type it defines.

## 3. File-scoped namespaces

```csharp
// Good (C# 10+)
namespace MyApp.Orders;

public class OrderService { }
```

Prefer file-scoped namespace declarations over the older block-scoped form, for new code in
projects targeting C# 10 or later.

**Flag:** block-scoped namespace braces newly introduced in a codebase that otherwise
consistently uses file-scoped namespaces.

## 4. `var` when the type is obvious, explicit type when it isn't

```csharp
var order = new Order();          // obvious from the right-hand side
var id = GetOrderId();             // less obvious - consider an explicit type if it aids readability
IEnumerable<Order> orders = GetOrders(); // explicit type clarifies the returned abstraction
```

**Flag:** `var` used where the right-hand side gives no hint at all what the type is (e.g., a
method call returning a non-obvious type), especially in public API signatures where the
return type should be explicit in the method declaration regardless.

## 5. Expression-bodied members for simple one-liners only

```csharp
// Good
public int Total => Items.Sum(i => i.Price);

// Bad - multi-step logic crammed into an expression body hurts readability
public decimal Total => Items.Where(i => i.IsActive).Sum(i => i.Price * (1 - i.Discount)) + Shipping - Tax;
```

**Flag:** expression-bodied members whose logic spans multiple conceptual steps or would
benefit from intermediate named variables.

## 6. Avoid `#region` as a substitute for splitting a class

Regions are often used to hide the fact that a class has grown too large and covers too many
responsibilities. Prefer extracting cohesive groups of members into their own well-named
classes.

**Flag:** `#region` blocks used to organize a single class into what are effectively several
unrelated responsibilities, rather than genuinely improving navigation of a cohesive class.

## 7. Consistent `using` directive placement and ordering

`using` directives at the top of the file (or globally via `ImplicitUsings`/`GlobalUsings`
where the project convention establishes that), System namespaces first, then third-party,
then the project's own namespaces, each group separated by a blank line.

**Flag:** `using` statements scattered inside namespaces inconsistently with the rest of the
codebase's convention; unused `using` directives left in a file after refactoring.

## 8. Avoid unclear abbreviations

Prefer full, descriptive names over abbreviations that aren't immediately obvious
(`customer` not `cust`, `repository` not `repo` in public API surface, though `repo` as a
private field/local name is common and fine). Loop variables in short, obvious loops (`i`,
`j`) are fine; abbreviating a domain concept is not.

**Flag:** unclear abbreviations in public API member names, especially ones that could be
ambiguous (`qty` vs `quantity` is usually fine and common; `ordSvc` is not).
