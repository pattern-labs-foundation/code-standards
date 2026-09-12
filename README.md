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
