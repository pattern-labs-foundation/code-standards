# code-standards

A public, open (MIT-licensed) set of coding standards written to be consumed by AI
code-review agents - GitHub Copilot's PR review, or any custom LLM-based reviewer running on
a GitHub Actions runner - as well as by human contributors. Any developer, open-source
project, or company is welcome to use, copy, fork, or link to these standards in their own
repositories, whether that's a personal project or an entire organization's fleet of repos.

The point of this repo is not just to document good practice, but to make it something an
agent actually *enforces* automatically, every time a pull request or commit is opened:
instead of a human reviewer repeating "use `IOptions<T>`, not raw `IConfiguration`" for the
tenth time, the review agent checks it on every PR, consistently, using the rules here.

Currently covers:

- [`csharp/`](./csharp) - C#/.NET standards (architecture, dependency injection, the Options
  pattern, async/concurrency, error handling, logging, API design, EF Core, security,
  performance, testing, nullable reference types, style, immutability, resource management),
  plus [`csharp/REVIEW-CHECKLIST.md`](./csharp/REVIEW-CHECKLIST.md), the condensed,
  agent-facing version meant to be pasted directly into a reviewer's instructions.
- [`terraform-azure/`](./terraform-azure) - Terraform standards for Azure infrastructure
  (state management, authentication/identity, RBAC and access control, secrets and Key
  Vault, networking, module design, naming/tagging, resource protection, logging, CI/CD,
  code style, policy scanning), plus
  [`terraform-azure/REVIEW-CHECKLIST.md`](./terraform-azure/REVIEW-CHECKLIST.md). The
  through-line: prefer Azure RBAC and managed identity/OIDC over static access keys, SAS
  tokens, connection strings, and service principal secrets wherever both are available.
- [`agent-instructions/`](./agent-instructions) - ready-to-copy files for wiring these standards into a
  consuming repo's PR review process (`.github/copilot-instructions.md`, path-scoped Copilot
  instructions for both C# and Terraform, and a GitHub Actions workflow for a custom review
  agent).

## How to implement this in your own repo (or your org's repos)

These standards do nothing by themselves - they need to be wired into whichever agent
actually reviews your pull requests. Pick the path that matches your setup; you can combine
more than one.

### Option A: GitHub Copilot's built-in PR review (no workflow needed)

This is the lowest-effort path if your repo already uses GitHub Copilot.

1. In the repo you want to protect, create `.github/copilot-instructions.md` using
   [`agent-instructions/copilot-instructions.md`](./agent-instructions/copilot-instructions.md) as your
   starting point. Fill in the "Project context" section for that specific repo.
2. Add whichever path-scoped instructions files apply, so rules for one stack don't leak
   into reviews of another in a multi-language/multi-stack repo:
   - [`agent-instructions/csharp.instructions.md`](./agent-instructions/csharp.instructions.md) ->
     `.github/instructions/csharp.instructions.md` (`applyTo: "**/*.cs"`)
   - [`agent-instructions/terraform.instructions.md`](./agent-instructions/terraform.instructions.md) ->
     `.github/instructions/terraform.instructions.md` (`applyTo: "**/*.tf"`)
3. Commit the files to the repo's default branch.
4. Confirm Copilot code review is turned on for the repo (repo Settings -> Copilot, or your
   org's Copilot policy) - it needs to be enabled for these instructions to be read at all.
5. Open a PR to verify: Copilot's automatic review comment should now reference the rules
   (e.g., flagging a raw `IConfiguration` injection, a missing `AsNoTracking()`, a storage
   account key used where a managed identity + RBAC role assignment was available instead).

To roll this out across an entire organization rather than one repo at a time, commit the
same files into a template repository your org uses for new repos, or push them to every
existing repo via a script/Actions workflow that runs once across the org.

### Option B: A custom agent running on a GitHub Actions runner

Use this if you want a specific model/provider, a fully custom prompt, or want the review to
run as a distinct bot account rather than relying on Copilot's built-in review.

1. Copy [`agent-instructions/pr-review-agent-workflow.yml`](./agent-instructions/pr-review-agent-workflow.yml)
   to `.github/workflows/pr-review.yml` in the target repo.
2. Replace `<org>/code-standards` with wherever this repo actually lives (this repo itself,
   or your own fork of it if you've customized the rules).
3. Replace the placeholder "Run standards-based review" step with whichever review
   agent/action/CLI your organization already runs on its runners, and add whatever secret
   it needs under the repo's or org's Actions secrets.
4. Commit the workflow file. It runs automatically on every `pull_request` event
   (opened/synchronize/reopened) and checks out this standards repo alongside the PR's code
   so the agent has the rules in front of it when it reviews the diff.

### Keeping the rules in sync

Whichever option you use, the underlying rule content can drift from this source repo over
time. Two ways to manage that:

- **Link out** (simplest): keep the instructions files short, and have them reference the
  live URL of this repo's `csharp/`/`terraform-azure/` folders for full detail, as the
  agent-instructions files already do.
- **Vendor a copy** (more control, more upkeep): add this repo as a git submodule (e.g. at
  `standards/csharp`) or copy the relevant folder in directly, and point your instructions
  files at the local copy. Update it deliberately when you pull in changes, rather than
  inheriting changes automatically.

## Quick start (browsing the standards themselves)

1. Pick the topic set you need: [`csharp/`](./csharp) or [`terraform-azure/`](./terraform-azure).
2. Read that folder's `README.md` for the index, or jump straight to its
   `REVIEW-CHECKLIST.md` for the agent-facing summary.
3. Use [`agent-instructions/`](./agent-instructions) to wire it into your repo's PR review flow, per the
   implementation steps above - see also [`agent-instructions/README.md`](./agent-instructions/README.md).

## Contributing

Issues and pull requests proposing new standards, corrections, or additional language/topic
coverage are welcome. Each standard should include a short rationale and a concrete `// Bad` /
`// Good` example, and should be phrased so an LLM reviewer can act on it directly (a clear
rule plus a "flag when..." condition).

## License

MIT - see [LICENSE](./LICENSE).
