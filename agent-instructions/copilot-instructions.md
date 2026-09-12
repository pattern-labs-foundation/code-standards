> [!IMPORTANT]
> ## 📐 Source: [pattern-labs-foundation/code-standards](https://github.com/pattern-labs-foundation/code-standards)
>
> A starting template. Fill in "Project context" and drop what does not apply.
> Language detail belongs in the path-scoped files under `.github/instructions/`, so keep
> this one cross-cutting.
>
> | | |
> |---|---|
> | 📦 **Origin** | `agent-instructions/copilot-instructions.md` |
> | 🔄 **Updates** | Sync from code-standards |
> | 💡 **Improvements** | Contributions welcome, [open a PR](https://github.com/pattern-labs-foundation/code-standards/pulls) |
> | 📄 **Licence** | MIT |

# 📐 Repository Custom Instructions

## Project context

<!-- Fill in: what this service/app or infrastructure does, its architecture, key
     frameworks/providers and versions. -->

Standards reference: https://github.com/<org>/code-standards
(vendor or copy the relevant folder into this repo if a local, versioned reference is
preferred over linking out.)

## When reviewing pull requests

Check changed code against the standards below, and explain *why* something is flagged, not
just that it violates a rule. Prioritize correctness and security issues over style
preferences. Only flag what's actually visible in the diff.

### Cross-cutting priorities (apply regardless of language/stack)
- Flag any hardcoded secret, API key, password, connection string, or access token anywhere
  in the diff.
- Prefer identity- and role-based access control (RBAC, managed identity, OIDC) over static,
  long-lived credentials or access keys wherever the platform offers both options.
- Flag missing input validation at any trust boundary (API request, user input, external
  data).
- Flag new logic/infrastructure with no corresponding tests, or tests/checks covering only
  the happy path.

### C# (`**/*.cs`, `**/*.csproj`, `**/appsettings*.json`)
See `.github/instructions/csharp.instructions.md` (copied from
`code-standards/agent-instructions/csharp.instructions.md`) for the full checklist: the Options
pattern over raw `IConfiguration`, constructor injection and DI lifetime correctness, no
blocking on async code, structured logging, EF Core query hygiene, DTOs at API boundaries,
parameterized queries.

### Terraform / Azure (`**/*.tf`, `**/*.tfvars`)
See `.github/instructions/terraform.instructions.md` (copied from
`code-standards/agent-instructions/terraform.instructions.md`) for the full checklist: RBAC/managed
identity over storage keys and SAS tokens, remote state with Azure AD-based backend auth, no
secrets in `.tf`/`.tfvars`, no public network access or `0.0.0.0/0` NSG rules by default,
`prevent_destroy` on stateful resources, plan review gated before apply.

For the full rationale and before/after examples behind any of the above, see the linked
standards repository.
