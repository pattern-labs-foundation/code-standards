# Agent Instructions

Starting points for wiring standards from [`/csharp`](../csharp) and
[`/terraform-azure`](../terraform-azure) into a consuming repository's PR review process.

## Recommended: a GitHub Actions workflow (any repo, personal included, no copy-paste)

Use [`pr-review-agent-workflow.yml`](./pr-review-agent-workflow.yml). Copy this one file to
`.github/workflows/pr-review.yml` in the consuming repo - it needs no GitHub Copilot
subscription and no org/enterprise policy, just Actions (free on public repos, a generous
free quota on private ones) and an API key for an LLM of your choice.

Nothing else gets copied: the workflow checks out this standards repo fresh into a temp path
on every run, reads whichever `REVIEW-CHECKLIST.md` matches the changed files (C# and/or
Terraform), reviews the diff against it, and posts the findings as a PR comment. The
checkout disappears when the job ends - the consuming repo's history only ever has the one
workflow file, never a copy of any `csharp/`/`terraform-azure/` content.

## Alternative: GitHub Copilot's PR code review

Copilot's automatic PR review (and Copilot Chat/coding agent in the same repo) reads custom
instructions straight out of the repository - no workflow needed, but it does require a
Copilot subscription (personal Individual/Pro is fine, not just org/Enterprise) and, unlike
the option above, means copying a couple of files into the repo.

1. **Repo-wide instructions:** copy [`copilot-instructions.md`](./copilot-instructions.md) to
   `.github/copilot-instructions.md` in the consuming repo. Fill in the "Project context"
   section and trim whichever language section(s) don't apply.
2. **Path-scoped instructions (recommended for multi-language repos):** copy whichever of the
   following apply into `.github/instructions/`:
   - [`csharp.instructions.md`](./csharp.instructions.md) - `applyTo: "**/*.cs"`
   - [`terraform.instructions.md`](./terraform.instructions.md) - `applyTo: "**/*.tf"`
3. Keep the standards in sync by either:
   - vendoring this repo's `csharp/`/`terraform-azure/` folders into the consuming repo (e.g.
     as a git submodule under `standards/`) and referencing individual files from the
     instructions, or
   - periodically copying the condensed `REVIEW-CHECKLIST.md` content into the instructions
     files directly (simplest, but drifts over time - the workflow option above has no such
     drift problem, since it references the standards live on every run instead).
