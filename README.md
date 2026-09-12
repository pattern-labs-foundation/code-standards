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
actually reviews your pull requests.

### Recommended: a GitHub Actions workflow (works on any repo, personal included)

This is the path to use if you don't have (or don't want to depend on) a GitHub Copilot
subscription, or you're on a personal account rather than an org with a Copilot policy. It
needs nothing but GitHub Actions (free on public repos, a generous free quota on private
ones) and an API key for an LLM of your choice. Nothing gets copied into your repo - the
workflow checks out this standards repo fresh on every run and reviews against it live, so
there's no vendored `.md` content to keep in sync by hand.

1. Copy [`agent-instructions/pr-review-agent-workflow.yml`](./agent-instructions/pr-review-agent-workflow.yml)
   to `.github/workflows/pr-review.yml` in the target repo.
2. Replace `<owner>/code-standards` with wherever this repo actually lives (this repo itself,
   or your own fork of it if you've customized the rules).
3. Add a repository secret `LLM_API_KEY` (Settings -> Secrets and variables -> Actions).
   Optionally add repository variables `LLM_API_BASE_URL`/`LLM_MODEL` to point at a different
   OpenAI-Chat-Completions-compatible endpoint (Azure OpenAI, a self-hosted server, etc.) -
   it defaults to OpenAI's API with a small, cheap model.
4. Commit the workflow file. It runs automatically on every `pull_request` event
   (opened/synchronize/reopened), builds the diff, picks whichever `REVIEW-CHECKLIST.md`
   matches the changed files (C# and/or Terraform), and posts the findings as a PR comment -
   nothing further to trigger by hand.

### Alternative: GitHub Copilot's built-in PR review

Use this instead if the repo already has a Copilot subscription (personal Individual/Pro
plans work, not just org/Enterprise) and you're fine with copying a couple of instruction
files into `.github/` rather than referencing this repo live.

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
4. Confirm Copilot code review is turned on for the repo (personal account: your own Copilot
   settings for that repo; org account: repo Settings -> Copilot, or the org's Copilot
   policy) - it needs to be enabled for these instructions to be read at all.
5. Open a PR to verify: Copilot's automatic review comment should now reference the rules.

Because this approach copies files into the consuming repo, keeping them in sync with this
source repo over time is a manual step - re-copy the instructions files (or the condensed
`REVIEW-CHECKLIST.md` content into them) when the standards here change. The Actions-workflow
approach above doesn't have this problem, since it references the standards repo live on
every run instead of copying anything.

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
