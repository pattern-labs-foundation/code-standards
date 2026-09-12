---
applyTo: "**/*.tf,**/*.tfvars"
---

> [!IMPORTANT]
> ## 🔐 Source: [pattern-labs-foundation/code-standards](https://github.com/pattern-labs-foundation/code-standards)
>
> This file **is** the standard, not a summary of one.
>
> | | |
> |---|---|
> | 📦 **Origin** | `agent-instructions/terraform.instructions.md` |
> | 🔄 **Updates** | Sync from code-standards |
> | 💡 **Improvements** | Contributions welcome, [open a PR](https://github.com/pattern-labs-foundation/code-standards/pulls) |
> | 📄 **Licence** | MIT |

# 🔐 Terraform (Azure) Standards

Apply these when reviewing or writing Terraform for Azure in this repository. The rule
running through all of them: prefer Azure RBAC and managed identity over static access
keys, SAS tokens, connection strings, and service principal secrets. Only flag what is
visible in the diff.

## State Management

### 1. Remote state in Azure Storage, never local state

State must live in a remote `azurerm` backend, never `terraform.tfstate` committed to source
control or left as a local file relied on by multiple people/pipelines.

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-prod"
    storage_account_name = "sttfstateprod001"
    container_name       = "tfstate"
    key                  = "networking/prod.tfstate"
  }
}
```

**Flag:** no `backend` block; a `.tfstate` file in the repository; backend configuration
pointing at a storage account with no apparent access restrictions.

### 2. State storage uses RBAC, not access keys

Authenticate via Azure AD (`use_azuread_auth = true`) with RBAC role assignments (e.g.
`Storage Blob Data Contributor`), not the storage account's shared key.

```hcl
# Bad
backend "azurerm" { ... access_key = var.tfstate_storage_key }

# Good
backend "azurerm" { ... use_azuread_auth = true }
```

**Flag:** `access_key`, `sas_token`, or a connection string in a backend block; the state
storage account with `shared_access_key_enabled = true` or
`allow_nested_items_to_be_public = true`.

### 3. State locking stays enabled

The `azurerm` backend locks automatically via blob leases - never run with `-lock=false`
outside a genuine, understood recovery scenario.

**Flag:** `-lock=false` in any checked-in script, pipeline step, or task-runner target used
for routine `plan`/`apply`.

### 4. State storage has versioning, soft delete, and restricted network access

State corruption/deletion should be recoverable, and the storage account shouldn't be
reachable from the public internet with no restriction.

**Flag:** the state storage account with no `blob_properties` versioning/soft-delete
configuration, or `network_rules { default_action = "Allow" }` with no further restriction.

### 5. Never output or log sensitive values from state

`sensitive = true` hides a value from console output, but it still exists in plaintext in the
state file - treat the state file itself as sensitive data end-to-end.

**Flag:** an output marked `sensitive = true` whose value is nonetheless echoed elsewhere (a
log file, a non-secure artifact, `terraform output -raw` in a CI step that logs output).

### 6. One state file per environment/blast-radius boundary

Split state by environment and by logical boundary (networking vs. application vs. data), so
a bad `apply` in one area can't affect unrelated infrastructure.

**Flag:** a single root module/state file whose resources span multiple environments, or mix
unrelated systems typically deployed independently.

## Authentication & Identity

### 1. CI/CD pipelines authenticate via OIDC, not a stored client secret

Use Azure AD workload identity federation so the pipeline exchanges a short-lived,
platform-issued token for an Azure AD token - no long-lived client secret stored anywhere.

```hcl
# Bad
provider "azurerm" { client_secret = var.client_secret }
```

```yaml
# Good - GitHub Actions federated credential, no client secret
permissions: { id-token: write, contents: read }
steps:
  - uses: azure/login@v2
    with: { client-id: ${{ vars.AZURE_CLIENT_ID }}, tenant-id: ${{ vars.AZURE_TENANT_ID }} }
```

**Flag:** `client_secret`/`ARM_CLIENT_SECRET` in pipeline configuration or Terraform for a
CI/CD identity; an `azuread_service_principal_password` for a pipeline that could use a
federated credential instead.

### 2. Azure resources authenticate to each other via managed identity

When one resource calls another, use a managed identity plus an RBAC role assignment, not a
connection string/key embedded in app settings.

```hcl
# Bad
app_settings = { "DB_CONNECTION_STRING" = "Server=...;Password=${var.db_password};" }

# Good
identity { type = "SystemAssigned" }
# + azurerm_role_assignment granting the identity access
```

**Flag:** a connection string, key, or password embedded in `app_settings`/
`environment_variables` when the target resource supports managed identity instead.

### 3. Human/local runs use Azure CLI context, not embedded credentials

Rely on the `azurerm` provider's default `az login` authentication rather than hardcoding a
service principal's credentials into a `.tfvars` file or shell profile.

**Flag:** `.tfvars`/`.env` files containing a `client_secret` with no `.gitignore` entry;
docs instructing contributors to set `ARM_CLIENT_SECRET` as a plain env var for routine use.

### 4. An unavoidable service principal secret is short-lived and in Key Vault

When a third-party integration genuinely requires a client secret, set a short expiration,
store it in Key Vault (see [Secrets & Key Vault](#secrets--key-vault)), and reference it from
there rather than passing it as a plain `-var` or CI secret with no rotation plan.

**Flag:** `azuread_service_principal_password` with no `end_date`, or an expiration set years
out with no rotation automation.

### 5. Don't disable Azure AD authentication on resources that support it

Where a resource offers both key-based and Azure AD auth, Azure AD should be enabled and
key-based auth explicitly disabled where the workload allows.

```hcl
resource "azurerm_storage_account" "data" { shared_access_key_enabled = false }
```

**Flag:** `shared_access_key_enabled` left `true` with no documented reason a legacy consumer
still needs key-based access.

## RBAC & Access Control

### 1. Prefer Azure RBAC role assignments over resource-level access keys/tokens

Whenever a resource supports both a static-token path (storage keys, SAS tokens, connection
strings) and an Azure AD RBAC path, use RBAC role assignments to identities, not the token.

```hcl
# Bad
resource "azurerm_storage_account_sas" "app_access" { ... }

# Good
resource "azurerm_role_assignment" "app_to_storage" {
  scope                = azurerm_storage_account.data.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_linux_web_app.app.identity[0].principal_id
}
```

**Flag:** `azurerm_storage_account_sas`, `list_keys()`/`primary_access_key`, or
`primary_connection_string` consumed by another resource instead of a role assignment.

### 2. Role assignments are scoped as narrowly as possible

Scope `azurerm_role_assignment` to the specific resource (or resource group) that needs
access, not the subscription or management group, unless the role is genuinely that broad.

**Flag:** `scope` set to a subscription/management group for a single app's access needs; any
scope wider than the resource group actually being accessed, with no stated reason.

### 3. Avoid `Owner`/`Contributor` as a default

Prefer a purpose-built role (`Storage Blob Data Contributor`, `Key Vault Secrets User`,
`AcrPull`) or a scoped custom role over broad write access.

**Flag:** `Owner` or `Contributor` assigned to an application/service identity; a custom role
whose `actions` include a wildcard (`*`) covering far more than needed.

### 4. Human access goes through Azure AD groups, not individually-assigned roles

Target an Azure AD group, not individual `principal_id`s hardcoded per person - avoids code
churn as people join/leave and keeps access reviewable in one place.

**Flag:** `azurerm_role_assignment` with a hardcoded individual user's object ID as
`principal_id`, especially multiple such resources granting the same role to different people.

### 5. Prefer time-bound/PIM-eligible access for privileged roles

For Owner-equivalent roles or access to production secrets, prefer PIM-eligible role
assignments over permanent standing assignments where the org's setup supports it.

**Flag:** a standing role assignment for a highly privileged role granted to a human identity
with no discussion of why standing access is required.

### 6. Deny-by-default network and data-plane access, grant explicitly

Resources should default to denying access and grant specific identities/networks access
explicitly, rather than defaulting open.

**Flag:** `default_action = "Allow"` on a storage/Key Vault network ACL with no further
restriction; a Key Vault policy or role granting broad `Get/List/Set/Delete` where read-one
would do.

## Secrets & Key Vault

### 1. No secrets in `.tf`/`.tfvars` files or source control, ever

Passwords, keys, connection strings, and certificates must never appear as literals in
Terraform source, `.tfvars`, or CI configuration - including in comments or placeholders that
look real.

```hcl
# Bad
administrator_login_password = "SuperSecretP@ssw0rd123!"

# Good - sourced from Key Vault at apply time
data "azurerm_key_vault_secret" "sql_admin_password" { name = "sql-admin-password", key_vault_id = data.azurerm_key_vault.kv.id }
administrator_login_password = data.azurerm_key_vault_secret.sql_admin_password.value
```

**Flag:** any credential-shaped string literal in a diff; a `.tfvars` sensitive-looking
variable set to a literal instead of populated from a secret store or CI injection.

### 2. Prefer not generating/storing long-lived secrets at all

Before reaching for a Key Vault secret, check whether the target resource supports managed
identity + RBAC instead (see [Authentication & Identity](#authentication--identity)).

**Flag:** a new Key Vault secret for a credential whose target resource actually supports
managed identity/Azure AD authentication as an alternative.

### 3. Mark sensitive variables and outputs

Any variable/output carrying a secret must be declared `sensitive = true` - a floor, not a
ceiling, since it doesn't encrypt the state file or restrict who can read it there.

```hcl
variable "sql_admin_password" { type = string, sensitive = true }
```

**Flag:** a variable/output whose name or usage implies a secret with no `sensitive = true`.

### 4. Generate random secrets with `random_password`, not hardcoded defaults

Use `random_password` with sufficient length/complexity, store the result in Key Vault, mark
it sensitive - never default to a fixed/predictable value.

**Flag:** a hardcoded default on a password/secret variable (`default = "changeme"`); secrets
generated with low entropy beyond throwaway dev/test.

### 5. Key Vault itself has purge protection and soft delete enabled

```hcl
resource "azurerm_key_vault" "kv" { purge_protection_enabled = true, soft_delete_retention_days = 90 }
```

**Flag:** `purge_protection_enabled = false` (or omitted) on a production Key Vault.

### 6. Key Vault access is via RBAC role assignments, not legacy access policies

Prefer `enable_rbac_authorization = true` plus `azurerm_role_assignment` over `access_policy`
blocks, for consistency with the RBAC-first approach and easier auditing.

**Flag:** new access-policy blocks on a Key Vault that already has
`enable_rbac_authorization = true`; a new Key Vault defaulting to the legacy model with no
stated reason.

## Networking & Private Access

### 1. Disable public network access on PaaS resources by default

Storage, Key Vault, SQL/Cosmos DB, and similar services should have public network access
disabled and reached via private endpoints, unless there's a stated reason otherwise.

```hcl
resource "azurerm_storage_account" "data" { public_network_access_enabled = false }
resource "azurerm_private_endpoint" "data_blob" { ... }
```

**Flag:** `public_network_access_enabled` left `true` on a resource holding non-public data,
with no private endpoint and no documented reason.

### 2. No `0.0.0.0/0` (or equivalent "any") rules in NSGs or firewall rules

NSG and firewall rules should specify actual source ranges, not allow all sources.

```hcl
# Bad
source_address_prefix = "*"

# Good
source_address_prefix = azurerm_subnet.app_gateway.address_prefixes[0]
```

**Flag:** `source_address_prefix = "*"`/`"0.0.0.0/0"` with `access = "Allow"` on an inbound
rule, especially for management ports (22, 3389, 5985/5986) or database ports.

### 3. Management ports are never open to the internet

RDP/SSH/direct database ports shouldn't be reachable from `Internet`/`*`. Use Bastion, a
private jump box, VPN, or JIT access instead.

**Flag:** an NSG rule allowing inbound 22/3389 (or a database's port) from any source broader
than a specific known management network/Bastion subnet.

### 4. Segment networks by function/trust boundary

Use separate subnets (and VNets with peering where appropriate) for different tiers, rather
than one flat address space with no NSGs between tiers.

**Flag:** all resources in a single subnet with no NSG, especially spanning clearly different
trust levels.

### 5. TLS/HTTPS enforced, minimum TLS version pinned

```hcl
resource "azurerm_storage_account" "data" { min_tls_version = "TLS1_2", enable_https_traffic_only = true }
```

**Flag:** `min_tls_version` omitted or below `TLS1_2`; HTTPS-only explicitly disabled.

### 6. Diagnostic/flow logging enabled on network boundaries

NSGs and network-boundary resources should route flow logs/diagnostics to a Log Analytics
workspace (see [Logging & Monitoring](#logging--monitoring)).

**Flag:** an NSG or VNet with no associated flow log/diagnostic setting anywhere in the
codebase.

### 7. VNet-integrate compute by default

Terraform alone can't reliably prove a compute resource's application code calls an external
endpoint, so scan `app_settings`/`site_config`/`environment_variables` for signals it's
likely: a URL whose host isn't a first-party Azure domain; a setting key matching a
third-party service pattern (`STRIPE_*`, `*_API_KEY`, `*_WEBHOOK_URL`); an existing broad
outbound rule (`443` to `Internet`); naming like "integration" or "webhook." Name the specific
match found in the review comment when there is one, but treat its absence as "no evidence
found," not "confirmed internal-only" - an app can grow an external dependency later without
anyone updating its network setup.

Because detection is unreliable, VNet-integrate compute unconditionally rather than only when
external calls are confirmed:

```hcl
resource "azurerm_linux_web_app" "app" {
  virtual_network_subnet_id = azurerm_subnet.app_integration.id
  site_config { vnet_route_all_enabled = true }
}
```

Once outbound traffic flows through the VNet, egress can be controlled via a route table
through Azure Firewall/an NVA, or a NAT Gateway for a stable, allow-listable IP. Give the
integration subnet its own NSG per [rule 4](#4-segment-networks-by-functiontrust-boundary).

**Flag:** an App Service/Function App/Container App with no VNet integration, especially one
referencing a third-party endpoint or API key; integration present but
`vnet_route_all_enabled` left off; an integration subnet with no NSG or UDR.

## Module Design & Structure

### 1. Reusable infrastructure patterns become modules, not copy-pasted resource blocks

If the same combination of resources is created more than once with only parameters
differing, extract it into a module.

**Flag:** near-identical resource blocks repeated across root modules/files with only
names/parameters changed, and no shared module behind them.

### 2. Module inputs are typed and validated, not implicitly `any`

```hcl
# Bad
variable "environment" {}

# Good
variable "environment" {
  type = string
  validation { condition = contains(["dev", "staging", "prod"], var.environment), error_message = "..." }
}
```

**Flag:** module variables with no `type`; a variable with a known small valid set and no
`validation` block enforcing it.

### 3. Module versions are pinned when sourced from a registry/remote source

```hcl
# Bad
module "vnet" { source = "git::https://github.com/org/terraform-azure-vnet.git" }

# Good
module "vnet" { source = "app.terraform.io/org/vnet/azurerm", version = "~> 3.1" }
```

**Flag:** a git-sourced module with no `ref`/tag; a registry module with no `version`
constraint.

### 4. Provider versions are pinned in `required_providers`

```hcl
terraform {
  required_providers { azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" } }
}
```

**Flag:** no `required_providers` block; a version constraint wide enough to span a major
version boundary (`>= 3.0` with no upper bound).

### 5. Outputs expose only what consumers need, not entire resource objects

**Flag:** an output like `value = azurerm_storage_account.this` exposing the whole resource
instead of the specific attributes callers need.

### 6. Root modules are organized predictably

A consistent file layout (`main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`) makes
review predictable. Don't put everything in one sprawling `main.tf`.

**Flag:** a `main.tf` exceeding a few hundred lines with clearly separable concerns
interleaved, and no split into logical files or child modules.

## Naming & Tagging

### 1. Follow a consistent resource naming convention

Adopt the Azure CAF convention (`<type-abbrev>-<workload>-<environment>-<region>-<instance>`)
and apply it consistently rather than ad hoc per module/author.

```hcl
# Bad
resource "azurerm_resource_group" "rg1" { name = "myrg" }

# Good
resource "azurerm_resource_group" "this" { name = "rg-payments-prod-eastus" }
```

**Flag:** resource names with no discernible convention or ambiguous abbreviations; storage
account/Key Vault names that will fail Azure's naming constraints.

### 2. Use a shared naming module/locals rather than hand-typing names per resource

```hcl
locals { name_prefix = "${var.workload}-${var.environment}-${var.region_short}" }
resource "azurerm_resource_group" "this" { name = "rg-${local.name_prefix}" }
```

**Flag:** the same workload/environment/region literals hand-typed across many resource names
instead of derived from shared locals/variables.

### 3. Every resource is tagged consistently

Apply a common tag set (`environment`, `owner`/`team`, cost center, managing repo) via a
shared `default_tags`-style local, not manually retyped per resource.

**Flag:** resources with no `tags` argument; tags present but inconsistent in key
naming/casing across the codebase (`Environment` vs `environment` vs `env`).

### 4. Tags don't carry secrets or sensitive data

Tags are visible to anyone with read access and appear in cost/billing exports.

**Flag:** a tag value containing anything that looks like a secret, key, or personal data.

## Resource Protection & Lifecycle

### 1. Protect stateful/critical resources with `prevent_destroy`

```hcl
resource "azurerm_mssql_database" "prod" { lifecycle { prevent_destroy = true } }
```

**Flag:** a production database, storage account, or Key Vault with no `prevent_destroy`
lifecycle protection.

### 2. Also apply an Azure Resource Lock

`prevent_destroy` only stops Terraform - it does nothing to stop someone deleting the
resource by hand in the Portal, CLI, or REST API. Business-data-bearing resources (SQL,
Cosmos DB, storage, Key Vault) should also get an `azurerm_management_lock` with
`CanNotDelete`, blocking deletion platform-wide until the lock is explicitly removed first.

```hcl
resource "azurerm_management_lock" "prod_db" {
  scope      = azurerm_mssql_database.prod.id
  lock_level = "CanNotDelete"
}
```

A lock can sit at the resource group level or per-resource - either is fine as long as every
business-data-bearing resource ends up covered. Use `CanNotDelete` (blocks delete, allows
config updates) rather than `ReadOnly` unless config should be frozen too.

**Flag:** a SQL server/database, Cosmos DB, storage account, or Key Vault with
`prevent_destroy` but no corresponding `azurerm_management_lock` (direct or inherited).

### 3. Understand `create_before_destroy` implications before relying on it

Verify the resource doesn't have naming/uniqueness constraints that would make "create" fail
while the old resource still exists (e.g. a globally-unique storage account name).

**Flag:** `create_before_destroy = true` on a resource whose identifier must be globally
unique, with no strategy for two copies to coexist momentarily.

### 4. Enable backups/recovery features on data-bearing resources

Automated backups, geo-redundancy where warranted, and point-in-time restore guard against
data loss that `prevent_destroy` doesn't cover.

```hcl
resource "azurerm_mssql_database" "prod" { short_term_retention_policy { retention_days = 35 } }
```

**Flag:** a production data-bearing resource with no backup/retention configuration, or
replication set to `LRS` with no stated reason for significant data.

### 5. Soft delete/purge protection enabled wherever the resource type offers it

**Flag:** soft-delete/purge-protection left disabled or omitted on a resource type that
offers it, beyond throwaway dev/sandbox.

### 6. Don't use `ignore_changes = all` or broad ignore-changes as a shortcut

List the specific attributes legitimately managed outside Terraform, not `all` or a broad
list silencing drift the team hasn't investigated.

```hcl
# Bad
lifecycle { ignore_changes = all }

# Good
lifecycle { ignore_changes = [tags["last_scaled_at"]] }
```

**Flag:** `ignore_changes = all` anywhere; a list broad enough to plausibly hide
security-relevant drift (network rules, auth settings, role assignments).

### 7. Destructive operations require explicit review, not blanket auto-approve

`-auto-approve` (or a CI equivalent skipping plan review) shouldn't be used where an
unreviewed destructive change would be costly.

**Flag:** `-auto-approve` in a CI step applying to a shared/production environment with no
preceding plan-approval gate.

## Logging & Monitoring

### 1. Diagnostic settings enabled on resources that support them

```hcl
resource "azurerm_monitor_diagnostic_setting" "kv_diagnostics" {
  target_resource_id         = azurerm_key_vault.kv.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  enabled_log { category = "AuditEvent" }
}
```

**Flag:** a Key Vault, storage account, SQL server, App Service, or NSG with no
`azurerm_monitor_diagnostic_setting` anywhere in the codebase.

### 2. Audit-relevant resources specifically capture audit logs

Key Vault (`AuditEvent`), SQL auditing, and storage read-write-delete logging should be
enabled, not just generic metrics - these answer "who accessed this and when."

**Flag:** a diagnostic setting on an audit-relevant resource that only forwards `AllMetrics`
and omits its audit/access log category.

### 3. Log retention is set deliberately, not left at a mismatched default

```hcl
resource "azurerm_log_analytics_workspace" "this" { retention_in_days = 90 }
```

**Flag:** `retention_in_days` omitted on a workspace backing production audit logs, when the
org has a stated retention requirement.

### 4. Alerting exists for security-relevant conditions, not just resource health

Consider alert rules for role-assignment changes, Key Vault policy changes, or unusual
sign-in activity, not only CPU/memory/availability.

**Flag:** an environment with alert resources covering only infrastructure health, with no
alerting on access/permission changes, where the org has stated this is required.

### 5. Diagnostic/log data itself is access-controlled

The Log Analytics workspace and log-archival storage should follow the same RBAC-over-keys
and private-access principles as any other resource - logs shouldn't be more loosely
protected than what they're logging.

**Flag:** a Log Analytics workspace or log-archival storage account with broader
network/access-key exposure than the resources whose logs it stores.

## CI/CD & Workflow

### 1. `plan` on pull request, `apply` only after merge/approval

Never `apply` directly from an unreviewed branch against a shared environment.

**Flag:** a workflow running `terraform apply` on every push to a feature branch or on a PR
event, rather than gating apply behind merge/approval.

### 2. Separate credentials/identities per environment

Dev, staging, and production should use distinct federated identities, each scoped to only
its own environment's resources - not one shared pipeline identity for everything.

**Flag:** a single service connection used across dev/staging/production jobs; a pipeline
identity with role assignments spanning multiple environments.

### 3. `plan` output is reviewed for unexpected destroys/replacements

A reviewer should check the plan diff for unexpected `-`/`destroy` or `-/+`/`replace` actions
on resources unrelated to the change, not just rubber-stamp because CI is green.

**Flag:** a merged PR whose plan included an unexplained destroy/replace unrelated to the
stated purpose, with no comment addressing it.

### 4. Drift detection runs on a schedule, not only on demand

A scheduled pipeline should run `terraform plan` against each environment and alert on drift.

**Flag:** no scheduled drift-detection job for environments Terraform is meant to own.

### 5. `terraform fmt` and `terraform validate` are enforced in CI

**Flag:** a CI workflow with no `terraform fmt -check`/`terraform validate` step ahead of
`plan`.

### 6. Pipeline logs don't leak secrets

CI steps shouldn't print variables that may contain secrets; sensitive step output should use
the platform's secret masking.

**Flag:** a pipeline step echoing an env variable, `terraform output`, or command result that
could contain a secret without going through secret masking.

## Code Style & Structure

### 1. Run `terraform fmt`

Enforce it in CI (see [CI/CD & Workflow](#cicd--workflow)); never a manual nitpick in review.

**Flag:** obviously unformatted HCL in a diff, as a signal `fmt` isn't enforced.

### 2. No hardcoded values that should be variables

```hcl
# Bad
sku_name = "S3"

# Good
sku_name = var.sql_sku
```

**Flag:** a literal that clearly varies by environment (SKU, instance count, region)
hardcoded in a resource block instead of parameterized.

### 3. `count`/`for_each` used deliberately, with stable keys

`for_each` keys resources by a stable identifier; `count` can destroy/recreate unrelated
resources when an item is removed from the middle of a list.

```hcl
# Bad
count = length(var.subnet_names)

# Good
for_each = toset(var.subnet_names)
```

**Flag:** `count` iterating over a list of named items where removing/reordering one would
force unrelated resources to be destroyed and recreated.

### 4. `locals` for derived/computed values, not repeated expressions

**Flag:** the same non-trivial expression (interpolation, a ternary, `merge()`) duplicated
verbatim across multiple resource blocks.

### 5. Data sources over hardcoded IDs for existing resources

Reference resources Terraform doesn't manage via a `data` source, not a hardcoded ID string.

```hcl
data "azurerm_virtual_network" "shared" { name = "vnet-shared-prod-eastus", resource_group_name = "rg-network-prod-eastus" }
```

**Flag:** a hardcoded Azure resource ID string used directly in a resource argument instead
of a `data` source reference.

### 6. Comments explain why, not what

A comment on a non-obvious `lifecycle` block or provider-quirk workaround should explain the
reason - that's what a reader can't infer from the code itself.

**Flag:** a comment only repeating the resource/argument name with no reasoning; a
non-obvious `ignore_changes`/`depends_on` with no comment explaining why it's there.

## Policy & Compliance Scanning

### 1. Static analysis (`tfsec`/`checkov`/`terrascan`) runs in CI

Catches common misconfigurations (open public access, missing encryption, overly permissive
RBAC) automatically rather than relying entirely on human reviewers.

**Flag:** no static-analysis/policy-scanning step in CI for a repository managing production
Azure infrastructure.

### 2. Scanner findings are triaged, not blanket-suppressed

```hcl
# Bad
#tfsec:ignore:azure-storage-default-action-deny

# Good
#tfsec:ignore:azure-storage-default-action-deny -- public read required for this static asset container; see ADR-0042.
```

**Flag:** a suppression comment/exception with no explanation; a large or growing suppression
list that isn't periodically reviewed.

### 3. Azure Policy complements, but doesn't replace, Terraform-level controls

Write code to comply proactively rather than relying on Policy to reject a non-compliant
`apply` after the fact.

**Flag:** code that would be rejected by the org's known Policy assignments, submitted
expecting Policy enforcement to catch it at apply time.

### 4. Compliance-relevant resource properties are tested, not just eyeballed

Prefer an automated check (a static-analysis rule, a `terraform test`, an OPA/Conftest policy
against plan JSON) over relying solely on manual review to catch a regression later.

**Flag:** a compliance requirement violated and caught in review before, with no automated
check added afterward to prevent a recurrence.
