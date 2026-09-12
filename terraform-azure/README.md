# Terraform (Azure) Standards

A modular set of Terraform standards for infrastructure targeting Azure, written to be
consumed by AI code-review agents (GitHub Copilot's PR review, or any custom LLM-based
reviewer) as well as human contributors. Each file covers one topic with a short
rationale, concrete `# Bad` / `# Good` HCL examples, and a list of things a reviewer should
flag.

If you only want the condensed, agent-facing rule list, start with
[`REVIEW-CHECKLIST.md`](./REVIEW-CHECKLIST.md) - it's the file meant to be pasted directly
into a review agent's prompt or instructions file.

## Index

| # | Topic | File |
|---|-------|------|
| 1 | State Management | [01-state-management.md](./01-state-management.md) |
| 2 | Authentication & Identity | [02-authentication-and-identity.md](./02-authentication-and-identity.md) |
| 3 | RBAC & Access Control | [03-rbac-and-access-control.md](./03-rbac-and-access-control.md) |
| 4 | Secrets & Key Vault | [04-secrets-and-key-vault.md](./04-secrets-and-key-vault.md) |
| 5 | Networking & Private Access | [05-networking-and-private-access.md](./05-networking-and-private-access.md) |
| 6 | Module Design & Structure | [06-module-design-and-structure.md](./06-module-design-and-structure.md) |
| 7 | Naming & Tagging | [07-naming-and-tagging.md](./07-naming-and-tagging.md) |
| 8 | Resource Protection & Lifecycle | [08-resource-protection-and-lifecycle.md](./08-resource-protection-and-lifecycle.md) |
| 9 | Logging & Monitoring | [09-logging-and-monitoring.md](./09-logging-and-monitoring.md) |
| 10 | CI/CD & Workflow | [10-ci-cd-and-workflow.md](./10-ci-cd-and-workflow.md) |
| 11 | Code Style & Structure | [11-code-style-and-structure.md](./11-code-style-and-structure.md) |
| 12 | Policy & Compliance Scanning | [12-policy-and-compliance-scanning.md](./12-policy-and-compliance-scanning.md) |
| - | **Consolidated agent checklist** | [REVIEW-CHECKLIST.md](./REVIEW-CHECKLIST.md) |

## Core principle

Azure gives most resources two ways to authenticate: a **static secret** (a storage account
key, a SAS token, a connection string, a service principal client secret) or **Azure AD
identity plus RBAC** (a managed identity or federated workload identity, authorized through a
role assignment). Nearly every standard in this folder is a variation on one theme: **prefer
the RBAC/identity path, and treat any static, long-lived, directly-usable token as something
that should be justified, not assumed.** A leaked key works for anyone, forever, until
manually rotated. A leaked/compromised identity is scoped, auditable, and can be revoked
through the same role-assignment mechanism that granted it.

## Enforcing these rules

Add one workflow file to your repo and every PR is checked against these standards
automatically. See [`/agent-instructions`](../agent-instructions) for setup.
