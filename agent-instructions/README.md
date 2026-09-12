# Agent Instructions

Copy-paste starting points for wiring standards from [`/csharp`](../csharp) and
[`/terraform-azure`](../terraform-azure) into a consuming repository's PR review process.
Pick the one(s) that match how the team reviews PRs.

## If the team uses GitHub Copilot's PR code review

Copilot's automatic PR review (and Copilot Chat/coding agent in the same repo) reads custom
instructions straight out of the repository - no GitHub Actions workflow required.

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
     files directly (simplest, but drifts over time).

## If the team wants a custom agent running on a GitHub Actions runner

Use [`pr-review-agent-workflow.yml`](./pr-review-agent-workflow.yml) as a starting point. It
checks out this standards repo alongside the PR's code and runs an LLM-based review step
against the diff (using whichever checklist matches what changed), posting results back as a
PR comment/review. Swap in whichever agent/runner the team already uses; the important part
is that two things get checked out (the PR's code and this standards repo) and fed to one
prompt.
