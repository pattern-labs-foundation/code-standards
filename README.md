# code-standards

Coding standards for C# and Terraform on Azure, written so an AI reviewer can apply them to
pull requests.

Copy the instruction files into your repo, turn on Copilot code review, and every PR gets
reviewed against these rules with inline comments where code breaks them.

MIT licensed. Anyone is welcome to use, fork, or adapt it.

## Quick start

**1. Copy three files** from [`agent-instructions/`](./agent-instructions) into your repo:

| Copy this | To here |
|---|---|
| `copilot-instructions.md` | `.github/copilot-instructions.md` |
| `csharp.instructions.md` | `.github/instructions/csharp.instructions.md` |
| `terraform.instructions.md` | `.github/instructions/terraform.instructions.md` |

**2. Turn Copilot code review on in your repo.** Copying the files does nothing on its own.

**Settings → Copilot → Code review →** tick **Automatically request Copilot code review**.

That's it. Open a PR and Copilot reviews it against these standards.

To make findings block a merge, and for the rest of the setup, see
[`agent-instructions/`](./agent-instructions).

## The standards

| | |
|---|---|
| [`csharp/`](./csharp) | Architecture, DI, the Options pattern, async, error handling, logging, API design, EF Core, security, performance, testing, nullable reference types, style, immutability, disposal |
| [`terraform-azure/`](./terraform-azure) | State, auth and identity, RBAC, secrets and Key Vault, networking, modules, naming and tagging, resource protection, logging, CI/CD, style, policy scanning |

Each folder has numbered topic files with rationale and `Bad`/`Good` examples, plus a
`REVIEW-CHECKLIST.md` condensing them into a reviewer-facing list. The instruction files are
the condensed version of those checklists.

The Terraform rules centre on one theme: prefer Azure RBAC and managed identity over static
access keys, SAS tokens, connection strings, and service principal secrets.

## Why instructions rather than a linter

These rules need judgment. Whether a class has too many responsibilities, whether an
abstraction earns its place, whether a config value belongs in an options class, none of that
is reliably decidable by pattern matching. A reviewer that reads the code does a better job
than regex, and there is nothing to maintain.

Rules that are purely mechanical can still be enforced the usual ways: analyzers and
`.editorconfig` for C#, `tfsec` or `checkov` for Terraform.

## Contributing

Pull requests welcome. New standards need a short rationale, a `Bad`/`Good` example, and a
"flag when" condition so a reviewer can act on it directly. Update the matching
`REVIEW-CHECKLIST.md` and the relevant file in `agent-instructions/` in the same change.
