# 📐 code-standards

Coding standards for **C#** and **Terraform on Azure**, written for GitHub Copilot to enforce
on pull requests.

![MIT](https://img.shields.io/badge/license-MIT-green) ![Copilot](https://img.shields.io/badge/enforced%20by-GitHub%20Copilot-blue)

## 🚀 Setup

**1. Copy the files you need into `.github/instructions/` in your repo:**

- 🟦 [`csharp.instructions.md`](./agent-instructions/csharp.instructions.md)
- 🟪 [`terraform.instructions.md`](./agent-instructions/terraform.instructions.md)

**2. Turn on Copilot code review.** ⚠️ Copying does nothing without this.

> **Settings → Copilot → Code review →** ✅ **Automatically request Copilot code review**

Open a PR and Copilot reviews it against the standards, commenting on the lines that break
them. 🎉

To make findings block a merge, see [`agent-instructions/`](./agent-instructions).

## ⚙️ Run in a pipeline

Copilot code review only reads instructions inside the repo being reviewed, so it can't point
at this repo. A pipeline can, using Copilot CLI. Add this workflow to the repo:

```yaml
name: Standards review
on: pull_request

permissions:
  contents: read
  copilot-requests: write

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
      - uses: actions/checkout@v6
        with:
          repository: pattern-labs-foundation/code-standards
          path: code-standards
      - run: npm install -g @github/copilot
      - run: |
          git diff origin/${{ github.base_ref }}...HEAD > pr.diff
          copilot -s -p "Review this diff against these standards. List each violation with file, line and reason.
          STANDARDS:
          $(cat code-standards/agent-instructions/csharp.instructions.md)
          DIFF:
          $(cat pr.diff)"
        env:
          GITHUB_TOKEN: ${{ github.token }}
```

Swap in `terraform.instructions.md` for Terraform repos.

- The review appears in the job log, not as inline PR comments.
- An org owner must enable **Org Settings → Copilot → Policies → Allow use of Copilot CLI
  billed to the organization**.

## 🏢 Org-wide

**Turn review on for every repo:**

> **Org Settings → Repository → Rulesets → New branch ruleset →** target **All repositories**
> **→** ✅ **Automatically request Copilot code review**

**Apply standards to every repo:**

> **Org Settings → Copilot → Custom instructions**

This is a single text box with no `applyTo` scoping, so every rule applies to every file. Keep
it to cross-cutting rules and still copy the language files into each repo.

## 💳 What you need

| To | Plan or setting |
|---|---|
| Use Copilot code review | PR author has a Copilot licence, **or** the org enables **Premium request paid usage** and **Allow members without a Copilot license to use Copilot code review** (billed to the org) |
| Org ruleset on private repos | GitHub **Team** or **Enterprise Cloud** (Free covers public repos only) |
| Org custom instructions | Copilot **Business** or **Enterprise** |
| Pipeline | Copilot CLI policy above, billed to the org |

No separate Azure or GitHub subscription is needed beyond these.

## 📋 What's covered

| File | Covers |
|---|---|
| 🟦 [`csharp.instructions.md`](./agent-instructions/csharp.instructions.md) | Architecture, DI, the Options pattern, async, error handling, logging, API design, EF Core, security, performance, testing, nullable reference types, style, immutability, disposal |
| 🟪 [`terraform.instructions.md`](./agent-instructions/terraform.instructions.md) | State, auth and identity, RBAC, secrets and Key Vault, networking, modules, naming, resource protection, logging, CI/CD, style, policy scanning |

Every rule has:

- ✅ a rationale
- ✅ a `Bad` / `Good` example
- ✅ a clear "flag when" condition

The file you copy **is** the standard, so what you read is what gets enforced. No summaries,
no drift.

## 🔐 The Terraform through-line

> Prefer **Azure RBAC and managed identity** over static access keys, SAS tokens, connection
> strings, and service principal secrets.

## 🤝 Contributing

Pull requests welcome. New rules need a rationale, a `Bad`/`Good` example, and a "flag when"
condition.

📄 MIT licensed. Use, fork, or adapt it.
