# code-standards

Coding standards for C# and Terraform/Azure, enforced automatically on pull requests.

Add one file to your repo and every PR gets checked against these rules. Works on any repo
including free personal accounts. No API key, no Copilot, no paid anything.

MIT licensed. Anyone is welcome to use, fork, or point their repos at it.

## Quick start

Copy [`agent-instructions/caller-workflow.yml`](./agent-instructions/caller-workflow.yml) to
`.github/workflows/standards-review.yml` in your repo:

```yaml
name: Standards Review

on:
  pull_request:
    branches: [main]

permissions:
  contents: read
  pull-requests: write

jobs:
  standards:
    uses: pattern-labs-foundation/code-standards/.github/workflows/standards-review.yml@2026-09-12-v3  # or main for latest
```

That is the whole setup. The rules stay in this repo, so you get updates without re-copying
anything.

### Which version to use

Every merge into main is tagged, so you can pin any point in time. The tag
is the merge date plus a counter, so a second merge the same day ends `-v2`. Pick one from
[the tags page](https://github.com/pattern-labs-foundation/code-standards/tags).

| Ref | Behaviour | Use when |
|---|---|---|
| A dated tag | Frozen. Never changes. | Preferred. You control exactly when rules change |
| `main` | Latest rules. New rules can start failing your build. | You always want the newest |

Full setup docs, options, and org-wide rollout: [`agent-instructions/`](./agent-instructions).

## The standards

| | |
|---|---|
| [`csharp/`](./csharp) | Architecture, DI, the Options pattern, async, error handling, logging, API design, EF Core, security, performance, testing, nullable reference types, style, immutability, disposal |
| [`terraform-azure/`](./terraform-azure) | State, auth/identity, RBAC, secrets and Key Vault, networking, modules, naming/tagging, resource protection, logging, CI/CD, style, policy scanning |

Each folder has numbered topic files with rationale and `Bad`/`Good` examples, plus a
`REVIEW-CHECKLIST.md` condensing them into a reviewer-facing list.

The Terraform rules centre on one theme: prefer Azure RBAC and managed identity over static
access keys, SAS tokens, connection strings, and service principal secrets.

## How it works

The workflow lives in [`.github/workflows/standards-review.yml`](./.github/workflows/standards-review.yml)
and runs the checks in [`scripts/`](./scripts) against the files changed in a PR. Findings are
posted as a PR comment and job summary; blocking findings fail the check.

Checks are deterministic pattern matches, so they run on the free GitHub-hosted runner with no
external service. Judgment-based rules stay in the checklists for human reviewers.

## Contributing

PRs welcome. New standards need a short rationale, a `Bad`/`Good` example, and a "flag when"
condition. If a rule can be checked mechanically, add it to the relevant script in
[`scripts/`](./scripts).
