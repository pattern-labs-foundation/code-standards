# Immutability & Records

## 1. Use `record`/`record struct` for DTOs and value objects

Records give value-based equality, a concise syntax, and (with positional or `init`-only
members) immutability by default - exactly the shape most DTOs, events, and value objects
want.

```csharp
// Bad - a mutable class doing a value object's job, with reference equality
public class Money
{
    public decimal Amount { get; set; }
    public string Currency { get; set; }
}

// Good
public record Money(decimal Amount, string Currency);
```

**Flag:** a plain mutable `class` used for a type whose entire purpose is to carry a fixed set
of values with value-based equality (DTOs, events, command/query objects, value objects).

## 2. Prefer immutable state by default

Default to `init`-only or `required init` properties and constructor-based construction.
Mutable public setters should be a deliberate choice for genuinely mutable domain state (e.g.,
an aggregate's evolving fields), not the default for everything.

```csharp
public class Order
{
    public required string CustomerName { get; init; }
    public OrderStatus Status { get; private set; } // deliberately mutable via a method, not a public setter
    public void MarkShipped() => Status = OrderStatus.Shipped;
}
```

**Flag:** public mutable setters (`{ get; set; }`) on properties that should only ever be set
once, or that should only change through a domain method that enforces invariants.

## 3. Don't expose mutable collections publicly

A class that owns a collection should expose it as `IReadOnlyList<T>`/`IReadOnlyCollection<T>`
(or an immutable collection type), not as a `List<T>`/`T[]` that callers can mutate directly
and bypass any invariant the owning class is meant to enforce.

```csharp
// Bad - callers can Add/Remove/Clear directly, bypassing any validation
public List<OrderItem> Items { get; } = new();

// Good
private readonly List<OrderItem> _items = new();
public IReadOnlyList<OrderItem> Items => _items;
public void AddItem(OrderItem item) { /* validate, then */ _items.Add(item); }
```

**Flag:** a public property exposing a mutable collection type (`List<T>`, `Dictionary<K,V>`,
arrays) that represents owned, invariant-bearing state rather than an intentionally free-form
bag of data.

## 4. Understand value equality with records

Records compare by value (all fields/properties equal), not by reference. This is usually
exactly what's wanted for DTOs and value objects, but be deliberate: if a type has identity
that matters independent of its field values (most entities with a database-generated `Id`),
a `class` with reference/identity-based equality (or equality overridden to compare only `Id`)
is more appropriate than a `record`.

**Flag:** a database entity with a mutable identity/lifecycle modeled as a `record` where
value equality on every field would be semantically wrong (e.g., two entities with the same
`Id` but different field values, mid-update, should probably still be "the same" entity).

## 5. `with`-expressions for producing modified copies

When a small change needs to be applied to an immutable value, use a `with` expression rather
than manually reconstructing every field.

```csharp
var discounted = money with { Amount = money.Amount * 0.9m };
```

**Flag:** manual reconstruction of every field of a record just to change one, when a `with`
expression would be clearer.
