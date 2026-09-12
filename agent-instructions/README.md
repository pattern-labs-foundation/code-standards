# Setup

Add one file to your repo. It calls the workflow in this repo, so the rules stay here and you
get updates automatically.

Works on any repo including free personal accounts. No API key, no Copilot, no paid anything.

## Single repo

Copy [`caller-workflow.yml`](./caller-workflow.yml) to `.github/workflows/standards-review.yml`:

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
    uses: pattern-labs-foundation/code-standards/.github/workflows/standards-review.yml@2026-09-13-v1  # or main for latest
```

Done. Every PR into `main` gets checked, findings are posted as a PR comment, and blocking
violations fail the check.

To require it before merge, add it as a required status check in your branch protection rules.

## Options

Set under `with:` in the caller file.

| Input | Default | Effect |
|---|---|---|
| `standards_ref` | matches the version you called | Override which branch/tag/SHA of the rules to enforce. |
| `fail_on_violation` | `true` | `false` reports findings without failing the check. |
| `comment_on_pr` | `true` | `false` writes to the job summary only. |

## Which version to use

Every merge into main is tagged with the date, so you can pin any point in time. Tags look
like `2026-09-13-v1`, and a second merge the same day is `2026-09-13-v2`. Pick one from
[the tags page](https://github.com/pattern-labs-foundation/code-standards/tags).

| Ref | Behaviour | Use when |
|---|---|---|
| A dated tag | Frozen. Never changes. | Preferred. You control exactly when rules change |
| `main` | Latest rules. New rules can start failing your build. | You always want the newest |

Pinning is preferred, so a new rule cannot fail your build unannounced. Bump
it when you are ready to fix what it finds.

## Whole organisation

- **Workflow template:** put the caller file in your org's public `.github` repo at
  `workflow-templates/standards-review.yml`. It then shows up as a one-click add under the
  Actions tab of every repo in the org.
- **Repo template:** put the caller file in your org's repository template so new repos have
  it from the start.
- **Bulk add:** loop over `gh repo list YOUR-ORG` and open a PR adding the file to each repo.

Forcing it on every repo automatically needs GitHub Enterprise (repository rulesets with
required workflows). The options above are free.

## What gets checked

Deterministic pattern checks in [`/scripts`](../scripts). Findings are **blocking** (fails the
check) or **advisory** (reported only).

**C#:** `IConfiguration` outside the composition root, magic-string config lookups, `.Result`/
`.Wait()`, `async void`, `throw ex;`, empty catch, `Console.WriteLine`, interpolated log
messages, `new HttpClient()`, singleton `DbContext`, interpolated SQL, hardcoded credentials,
missing `<Nullable>enable</Nullable>` and `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`.

**Terraform/Azure:** SAS tokens and access keys where RBAC works, client secrets, `Owner`/
`Contributor` assignments, subscription-scoped assignments, shared key auth, backend access
keys, `-lock=false`, hardcoded secrets, Key Vault purge protection off, public network access
on, open NSG rules, TLS below 1.2, `default_action = "Allow"`, `ignore_changes = all`,
`-auto-approve`, data resources missing `prevent_destroy` or `azurerm_management_lock`.

Judgment-based rules (SOLID, class responsibilities, abstraction quality) stay in the
checklists for human reviewers.

## Optional: Copilot

If you have a paid Copilot plan, copy [`copilot-instructions.md`](./copilot-instructions.md)
to `.github/copilot-instructions.md`, and [`csharp.instructions.md`](./csharp.instructions.md)
and [`terraform.instructions.md`](./terraform.instructions.md) into `.github/instructions/`.
Copilot's free tier does not include PR review.
