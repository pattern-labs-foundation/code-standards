# C# Coding Standards

This directory contains a modular set of C# / .NET coding standards written to be consumed
by **AI code-review agents** (GitHub Copilot's PR review, or any custom LLM-based reviewer)
as well as by human contributors. Anyone - an individual, an open-source project, or a
company - is free to adopt, copy, or link to these standards in their own repositories.

Each file below covers one topic in depth, with a short rationale, concrete `// Bad` /
`// Good` examples, and a list of things a reviewer should flag. If you only want the
condensed, agent-facing rule list, start with [`REVIEW-CHECKLIST.md`](./REVIEW-CHECKLIST.md) -
it's the file meant to be pasted directly into a review agent's prompt or instructions file.

## Index

| # | Topic | File |
|---|-------|------|
| 1 | SOLID & Architecture | [01-solid-and-architecture.md](./01-solid-and-architecture.md) |
| 2 | Dependency Injection | [02-dependency-injection.md](./02-dependency-injection.md) |
| 3 | Configuration & Options (`IOptions`) | [03-configuration-and-options.md](./03-configuration-and-options.md) |
| 4 | Async & Concurrency | [04-async-and-concurrency.md](./04-async-and-concurrency.md) |
| 5 | Error Handling | [05-error-handling.md](./05-error-handling.md) |
| 6 | Logging & Observability | [06-logging-and-observability.md](./06-logging-and-observability.md) |
| 7 | API Design | [07-api-design.md](./07-api-design.md) |
| 8 | Data Access & EF Core | [08-data-access-ef-core.md](./08-data-access-ef-core.md) |
| 9 | Security | [09-security.md](./09-security.md) |
| 10 | Performance | [10-performance.md](./10-performance.md) |
| 11 | Testing | [11-testing.md](./11-testing.md) |
| 12 | Nullable Reference Types | [12-nullable-reference-types.md](./12-nullable-reference-types.md) |
| 13 | Style & Naming | [13-style-and-naming.md](./13-style-and-naming.md) |
| 14 | Immutability & Records | [14-immutability-and-records.md](./14-immutability-and-records.md) |
| 15 | Resource Management (`IDisposable`) | [15-resource-management.md](./15-resource-management.md) |
| - | **Consolidated agent checklist** | [REVIEW-CHECKLIST.md](./REVIEW-CHECKLIST.md) |

## Enforcing these rules

Copy the instruction files into your repo and turn on Copilot code review, and every PR is
reviewed against these standards automatically. See
[`/agent-instructions`](../agent-instructions) for setup.

## Philosophy

- **Fail fast, fail loud.** Configuration and startup errors should surface immediately,
  not as a runtime `NullReferenceException` three layers deep.
- **Depend on abstractions, not frameworks leaking through.** Business logic shouldn't
  know about `IConfiguration`, `HttpContext`, or `DbContext` directly.
- **Explicit over implicit.** Strongly-typed options, explicit lifetimes, explicit
  cancellation, explicit nullability.
- **These are defaults, not laws.** A team may deviate with a documented reason; an
  agent reviewing code should flag deviations for human judgment, not auto-reject them.
