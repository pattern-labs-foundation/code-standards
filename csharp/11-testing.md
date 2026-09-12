# Testing

## 1. Arrange, Act, Assert

Structure each test in three clear parts: set up state, perform the action under test, assert
the outcome. Avoid interleaving assertions with setup or mixing multiple unrelated actions
into one test.

```csharp
[Fact]
public async Task GetOrder_WhenOrderExists_ReturnsOrder()
{
    // Arrange
    var repo = new FakeOrderRepository();
    repo.Add(new Order { Id = 1, Total = 100 });
    var sut = new OrderService(repo);

    // Act
    var order = await sut.GetOrderAsync(1);

    // Assert
    Assert.Equal(100, order.Total);
}
```

**Flag:** tests with assertions scattered throughout setup logic; a single test asserting many
unrelated behaviors.

## 2. One behavior per test, descriptive names

Test names should describe the scenario and expected outcome (a common convention:
`MethodName_Scenario_ExpectedResult`), so a failing test's name alone tells you what broke.

**Flag:** test names like `Test1`, `OrderServiceTests`, or generic names that don't describe
the scenario; a single test method covering multiple unrelated scenarios with multiple
unrelated assertion blocks.

## 3. Mock/fake interfaces, not concrete infrastructure

Unit tests should substitute collaborators via their interfaces (using a mocking library or
hand-written fakes), not spin up real databases, real HTTP calls, or the real file system.
Tests that need real infrastructure belong in a separate integration test suite, clearly
distinguished from unit tests (by project, namespace, or trait/category).

**Flag:** a "unit test" that opens a real database connection, makes a real outbound HTTP
call, or depends on network/file-system state; integration tests mixed into the same project
and run indiscriminately alongside fast unit tests without a way to run them separately.

## 4. Don't test private implementation details

Test observable behavior through the public API, not private methods or internal state via
reflection. If a private method needs its own dedicated tests, it's usually a sign it should
be extracted into its own class with a public API.

**Flag:** tests using reflection to invoke private methods or read private fields directly;
tests that break when an implementation detail changes but the public behavior/contract has
not.

## 5. Deterministic tests

Tests must not depend on wall-clock time, machine locale, network availability, test
execution order, or shared mutable static state. Inject a clock abstraction (e.g.
`TimeProvider`) instead of calling `DateTime.Now` directly in code under test, and avoid
`Thread.Sleep` to "wait for" async work - await it, or use a proper test synchronization
mechanism.

```csharp
// Bad - flaky under load, and slow
Thread.Sleep(500);
Assert.True(handler.WasCalled);

// Good
await handler.Completion; // an awaitable signal, not a fixed delay
Assert.True(handler.WasCalled);
```

**Flag:** `Thread.Sleep` used to wait for asynchronous work in a test; direct calls to
`DateTime.Now`/`DateTime.UtcNow` inside code under test with no injectable clock, when the
test needs to control time; tests that pass or fail differently depending on run order.

## 6. Cover edge cases and failure paths, not just the happy path

For any given unit, tests should include: the typical/happy-path case, boundary conditions
(empty collections, zero, nulls where allowed), and failure/error paths (invalid input, a
dependency throwing).

**Flag:** a class with meaningful branching/error-handling logic that has tests only for its
success path.

## 7. Keep test setup readable - use builders/object mothers for complex objects

When a domain object requires many fields to construct, use a test data builder or factory
method with sensible defaults rather than repeating a large, mostly-irrelevant object literal
in every test.

**Flag:** the same large multi-field object construction duplicated near-identically across
many test methods, obscuring which field actually matters for each test's scenario.
