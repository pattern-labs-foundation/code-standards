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
    uses: pattern-labs-foundation/code-standards/.github/workflows/standards-review.yml@main
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

## Pinning

Every merge into main is tagged automatically, so you can reference any point in time.

```yaml
uses: ...standards-review.yml@main     # always the latest rules
uses: ...standards-review.yml@v1       # latest v1.x, moves as rules are added
uses: ...standards-review.yml@v1.0.3   # frozen, never changes
```

Pin to `@v1.0.3` if you don't want new rules failing your builds until you're ready, then
bump when you are.

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
