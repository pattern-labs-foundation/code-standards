# Terraform (Azure) Review Checklist (agent-facing)

Paste this file (or point to it) as instructions for an AI code-review agent - GitHub
Copilot's PR review, or a custom bot. It is a condensed version
of the detailed standards in this directory; each item links to the file with full rationale
and examples. When reviewing a pull request, check the changed Terraform against every
relevant item below and flag violations with a short explanation and, where useful, a
suggested fix.

Only flag what's actually visible in the diff. Don't invent violations in unchanged code
outside the diff unless asked to review the whole file.

## The one theme that matters most: RBAC/identity over static tokens
See [03-rbac-and-access-control.md](./03-rbac-and-access-control.md) and
[02-authentication-and-identity.md](./02-authentication-and-identity.md)
- [ ] No storage account keys, SAS tokens, connection strings with embedded credentials, or
      service principal client secrets used where Azure AD/managed identity + RBAC is
      available instead.
- [ ] CI/CD authenticates via OIDC/workload identity federation, not a stored client secret.
- [ ] Resource-to-resource access uses managed identity + `azurerm_role_assignment`, not an
      access key/connection string embedded in app settings or variables.
- [ ] `shared_access_key_enabled`/equivalent local/key-based auth is disabled where the
      resource supports Azure AD-only auth and nothing legitimate still needs the key.
- [ ] Role assignments are scoped to the specific resource/resource group needed, not the
      subscription or management group, and avoid `Owner`/`Contributor` for
      application/service identities.

## State Management
See [01-state-management.md](./01-state-management.md)
- [ ] Remote `azurerm` backend configured - no local state, no `.tfstate` committed.
- [ ] Backend uses `use_azuread_auth = true`, not `access_key`/`sas_token`.
- [ ] No `-lock=false` in routine plan/apply scripts or pipeline steps.
- [ ] State storage account has versioning/soft-delete and is not openly network-accessible.

## Secrets & Key Vault
See [04-secrets-and-key-vault.md](./04-secrets-and-key-vault.md)
- [ ] No secret-shaped literal values anywhere in `.tf`/`.tfvars` files.
- [ ] Secret-carrying variables/outputs are marked `sensitive = true`.
- [ ] Generated secrets use `random_password` with real entropy, not hardcoded defaults.
- [ ] Key Vault has `purge_protection_enabled = true` for production.

## Networking
See [05-networking-and-private-access.md](./05-networking-and-private-access.md)
- [ ] `public_network_access_enabled` is `false` (with a private endpoint) for PaaS resources
      holding non-public data, unless there's a stated reason for public access.
- [ ] No NSG/firewall rule allowing `*`/`0.0.0.0/0` inbound, especially on management ports
      (22, 3389) or database ports.
- [ ] `min_tls_version`/HTTPS-only settings are pinned to TLS 1.2+.

## Resource Protection
See [08-resource-protection-and-lifecycle.md](./08-resource-protection-and-lifecycle.md)
- [ ] Production databases/storage/Key Vaults have `lifecycle { prevent_destroy = true }`.
- [ ] Anything holding business data (SQL servers/databases, Cosmos DB, storage
      accounts/blob containers, Key Vaults) also has an `azurerm_management_lock` with
      `CanNotDelete` (directly or inherited from its resource group) - `prevent_destroy`
      alone doesn't stop deletion through the Portal, CLI, or API.
- [ ] Backup/retention configured on data-bearing resources.
- [ ] No `ignore_changes = all`; ignored attributes are specific and justified.
- [ ] No `-auto-approve` against shared/production environments without a plan-review gate.

## Module Design & Code Structure
See [06-module-design-and-structure.md](./06-module-design-and-structure.md) and
[11-code-style-and-structure.md](./11-code-style-and-structure.md)
- [ ] Repeated resource patterns are extracted into a module rather than copy-pasted.
- [ ] Module variables have explicit types and validation where a constrained value set
      exists.
- [ ] Module/provider sources are version-pinned (`required_providers`, module `version`).
- [ ] `for_each` used (not `count`) when iterating over named/keyed items, to avoid
      index-shift-induced replacements.
- [ ] No hardcoded Azure resource ID strings where a `data` source reference would be correct.

## Naming & Tagging
See [07-naming-and-tagging.md](./07-naming-and-tagging.md)
- [ ] Resource names follow the repo's established naming convention.
- [ ] Resources carry the standard tag set (environment, owner, managed_by, etc.).
- [ ] No secrets or PII embedded in tag values.

## Logging & Monitoring
See [09-logging-and-monitoring.md](./09-logging-and-monitoring.md)
- [ ] Diagnostic settings configured for resources that support them, especially audit-log
      categories on Key Vault/SQL/storage.
- [ ] Log Analytics workspace/log storage has retention set deliberately and is itself
      access-controlled at least as tightly as the resources it logs.

## CI/CD
See [10-ci-cd-and-workflow.md](./10-ci-cd-and-workflow.md)
- [ ] `plan` runs and is visible on the PR before any `apply`; `apply` is gated behind
      merge/approval.
- [ ] Separate pipeline identities per environment, each scoped to only that environment.
- [ ] `terraform fmt -check`/`terraform validate` enforced in CI.

## Policy & Compliance
See [12-policy-and-compliance-scanning.md](./12-policy-and-compliance-scanning.md)
- [ ] A static-analysis/policy scanner (tfsec/checkov/terrascan or equivalent) runs in CI.
- [ ] Any scanner-finding suppression has a stated, reviewable reason, not a blanket ignore.

---

## How to weigh findings

- Treat static-credential-over-RBAC and public-network-exposure findings as high priority -
  raise them clearly even for a small PR.
- Style/structure items (naming, module extraction, `locals` usage) are worth flagging but
  shouldn't block a PR the way a security/access-control finding should.
- If a rule here conflicts with an explicit, documented decision already in the repository (an
  ADR, a comment, an existing established pattern used consistently elsewhere), prefer
  consistency with the existing codebase and note the standards-repo item as a suggestion, not
  a hard requirement.
- These are defaults for teams that haven't decided otherwise, not universal law.
