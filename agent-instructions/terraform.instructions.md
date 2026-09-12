---
applyTo: "**/*.tf"
---
<!--
  Copy this file to `.github/instructions/terraform.instructions.md` in the consuming
  repository. GitHub Copilot applies path-scoped instructions files (the `applyTo` glob
  above) only when reviewing/generating code for matching files.

  This mirrors terraform-azure/REVIEW-CHECKLIST.md in the standards repo. Update both
  together, or replace this file's body with a vendored copy of that checklist to avoid
  drift.
-->

# Terraform (Azure) Standards

Full detail and rationale: https://github.com/<org>/code-standards/tree/main/terraform-azure

## RBAC and identity over static tokens (highest priority)
- No storage account keys, SAS tokens, connection strings with embedded credentials, or
  service principal client secrets where Azure AD/managed identity + RBAC is available
  instead.
- CI/CD authenticates via OIDC/workload identity federation, not a stored client secret.
- Resource-to-resource access uses managed identity + `azurerm_role_assignment`, not an
  access key/connection string in app settings or variables.
- Disable `shared_access_key_enabled`/local auth where the resource supports Azure AD-only
  auth and nothing legitimate still needs the key.
- Role assignments scoped to the specific resource/resource group needed, never the
  subscription/management group by default; avoid `Owner`/`Contributor` for
  application/service identities - use the least-privileged role.

## State management
- Remote `azurerm` backend, never local state or committed `.tfstate`.
- Backend uses `use_azuread_auth = true`, not `access_key`/`sas_token`.
- No `-lock=false` in routine scripts/pipelines.

## Secrets
- No secret-shaped literal values in `.tf`/`.tfvars` files.
- Secret-carrying variables/outputs marked `sensitive = true`.
- Key Vault has `purge_protection_enabled = true` for production.

## Networking
- `public_network_access_enabled = false` (with a private endpoint) for PaaS resources
  holding non-public data, unless there's a stated reason for public access.
- No NSG/firewall rule allowing `*`/`0.0.0.0/0` inbound, especially on management or database
  ports.
- `min_tls_version`/HTTPS-only pinned to TLS 1.2+.
- App Service/Function App/Container App compute has VNet integration
  (`virtual_network_subnet_id`, `vnet_route_all_enabled`) by default - don't wait to confirm
  the app calls an external endpoint before recommending it, since that usually isn't visible
  from Terraform alone; app settings referencing a third-party URL/API key with no VNet
  integration is a stronger-than-usual signal to raise it.

## Resource protection
- `lifecycle { prevent_destroy = true }` on production databases/storage/Key Vaults.
- An `azurerm_management_lock` with `CanNotDelete` (directly or via the resource group) on
  anything holding business data - SQL, Cosmos DB, storage/blob, Key Vault -
  `prevent_destroy` alone doesn't stop deletion through the Portal, CLI, or API.
- No `ignore_changes = all`.
- No `-auto-approve` against shared/production environments without a plan-review gate.

## Module design and style
- Repeated resource patterns extracted into a module, not copy-pasted.
- Module variables typed and validated where a constrained value set exists.
- Module/provider sources version-pinned.
- `for_each` (not `count`) when iterating over named/keyed items.

## CI/CD
- `plan` visible on the PR before `apply`; `apply` gated behind merge/approval.
- Separate pipeline identities per environment, scoped to only that environment.
- `terraform fmt -check`/`terraform validate` enforced in CI.
