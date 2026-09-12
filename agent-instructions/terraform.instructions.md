---
applyTo: "**/*.tf,**/*.tfvars"
---

# 🔐 Terraform (Azure) Standards

> **Source:** [pattern-labs-foundation/code-standards](https://github.com/pattern-labs-foundation/code-standards) · 📄 MIT licensed
> **File:** `agent-instructions/terraform.instructions.md`
> This file is the standard itself, not a summary of one. Re-copy it from the source
> repository to pick up changes, and raise issues or improvements there.

Apply these when reviewing or writing Terraform for Azure in this repository. The rule
running through all of them: prefer Azure RBAC and managed identity over static access
keys, SAS tokens, connection strings, and service principal secrets. Only flag what is
visible in the diff.

## State Management

### 1. Remote state in Azure Storage, never local state

Terraform state must live in a remote backend (an Azure Storage account container configured
via `azurerm` backend), never `terraform.tfstate` committed to source control or left as a
local file relied on by multiple people/pipelines.

```hcl
# Bad - no backend block; state defaults to a local file
# (missing entirely)

# Good
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-prod"
    storage_account_name = "sttfstateprod001"
    container_name       = "tfstate"
    key                  = "networking/prod.tfstate"
  }
}
```

**Flag:** no `backend` block at all; a `.tfstate` file present in the repository (should be
`.gitignore`d unconditionally); backend configuration pointing at a storage account with no
apparent access restrictions.

### 2. State storage account uses RBAC, not access keys, and has key access disabled where possible

The storage account holding state should authenticate via Azure AD (`use_azuread_auth = true`
in the backend block) with RBAC role assignments (e.g. `Storage Blob Data Contributor`)
granted to the identities/pipelines that need it, rather than distributing the storage
account's shared key.

```hcl
# Bad - relies on a shared access key to reach the state backend
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-prod"
    storage_account_name = "sttfstateprod001"
    container_name       = "tfstate"
    key                  = "networking/prod.tfstate"
    access_key           = var.tfstate_storage_key
  }
}

# Good - Azure AD / RBAC based auth, no key needed
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-prod"
    storage_account_name = "sttfstateprod001"
    container_name       = "tfstate"
    key                  = "networking/prod.tfstate"
    use_azuread_auth     = true
  }
}
```

**Flag:** `access_key`, `sas_token`, or a connection string used in a backend block; the
state storage account provisioned elsewhere in the codebase with `shared_access_key_enabled =
true` (should be `false` once all consumers use Azure AD auth) or `allow_nested_items_to_be_public
= true`.

### 3. State locking is enabled (default for `azurerm` backend, don't disable it)

Azure's `azurerm` backend handles locking automatically via blob leases - never run with
`-lock=false` outside a genuine, understood recovery scenario, and never script around lock
contention by disabling locking.

**Flag:** `-lock=false` in any checked-in script, pipeline step, or `Makefile`/task runner
target used for routine `plan`/`apply`.

### 4. State storage has versioning, soft delete, and restricted network access

The storage account backing state should have blob versioning and soft-delete enabled (state
corruption/accidental deletion is recoverable), and should not be reachable from the public
internet with no restriction - use a private endpoint or, at minimum, storage account network
rules restricting access to known networks/identities.

**Flag:** the state storage account resource with no `blob_properties` versioning/soft-delete
configuration, or `network_rules { default_action = "Allow" }` with no further restriction.

### 5. Never output or log sensitive values from state

Values marked `sensitive = true` are hidden from `terraform plan`/`apply` console output, but
they still exist in plaintext in the state file itself. Treat the state file as sensitive
data end-to-end (access-controlled storage, encrypted at rest, RBAC-restricted) rather than
relying on the `sensitive` flag as the only protection.

**Flag:** an output marked `sensitive = true` whose value is nonetheless echoed elsewhere
(written to a log file, piped to a non-secure artifact, printed via `terraform output -raw`
in a CI step that logs command output).

### 6. One state file per environment/blast-radius boundary

Don't put every environment (dev/staging/prod) or unrelated resource groups in a single state
file - split by environment and by logical boundary (networking vs. application vs. data), so
a bad `apply` in one area can't affect unrelated infrastructure and blast radius stays small.

**Flag:** a single root module/state file whose resources span multiple environments, or
mix unrelated systems that are typically deployed/changed independently.

## Authentication & Identity

### 1. CI/CD pipelines authenticate via OIDC/workload identity federation, not a stored client secret

For Terraform running in GitHub Actions, Azure DevOps, or any CI runner, use Azure AD
workload identity federation (OIDC) so the pipeline exchanges a short-lived, platform-issued
token for an Azure AD token - no long-lived client secret is stored anywhere.

```hcl
# Bad - the azurerm provider block or environment relies on a stored client secret
provider "azurerm" {
  features {}
  client_id       = var.client_id
  client_secret   = var.client_secret   # long-lived secret sitting in a variable/secret store
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
}
```

```yaml
# Good - GitHub Actions example: federated credential, no client secret
permissions:
  id-token: write
  contents: read
steps:
  - uses: azure/login@v2
    with:
      client-id: ${{ vars.AZURE_CLIENT_ID }}
      tenant-id: ${{ vars.AZURE_TENANT_ID }}
      subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      # no client-secret input - federated credential handles the exchange
```

**Flag:** `client_secret`/`ARM_CLIENT_SECRET` referenced anywhere in pipeline configuration or
Terraform code for a CI/CD identity; a service principal created in Terraform with a
`azuread_service_principal_password` resource for a pipeline that could instead use a
federated credential (`azuread_application_federated_identity_credential`).

### 2. Azure resources authenticate to each other via managed identity, not embedded credentials

When one Azure resource needs to call another (a Function App reading from Key Vault, an App
Service connecting to a database), use a system- or user-assigned managed identity plus an
RBAC role assignment, not a connection string/key embedded in app settings.

```hcl
# Bad - database connection string with an embedded username/password in app settings
resource "azurerm_linux_web_app" "app" {
  # ...
  app_settings = {
    "DB_CONNECTION_STRING" = "Server=...;User Id=admin;Password=${var.db_password};"
  }
}

# Good - managed identity, authorization via RBAC role assignment
resource "azurerm_linux_web_app" "app" {
  # ...
  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "app_to_sql" {
  scope                = azurerm_mssql_server.sql.id
  role_definition_name = "SQL DB Contributor" # or a scoped custom role
  principal_id         = azurerm_linux_web_app.app.identity[0].principal_id
}
```

**Flag:** a connection string, access key, or password embedded in `app_settings`,
`environment_variables`, or similar resource blocks when the target resource supports
managed-identity-based authentication instead.

### 3. Human/local Terraform runs use Azure CLI/`az login` context, not embedded credentials

For local development, rely on the `azurerm` provider's default Azure CLI authentication
(`az login`) rather than hardcoding a service principal's credentials into a `.tfvars` file
or shell profile.

**Flag:** `.tfvars`/`.env` files (even ones intended to be local-only) containing a
`client_secret`, and no corresponding `.gitignore` entry for them; documentation instructing
contributors to set `ARM_CLIENT_SECRET` as a plain environment variable for routine local use.

### 4. If a service principal secret is genuinely unavoidable, it is short-lived and stored in Key
Vault, not in Terraform variables or CI secrets directly

Some third-party integrations still require a client secret. When that's genuinely
unavoidable: set a short expiration, store it in Key Vault (see
[Secrets & Key Vault](#secrets--key-vault)), and reference it from there at
apply/runtime rather than passing it as a plain `-var` or CI secret with no rotation plan.

**Flag:** `azuread_service_principal_password` (or equivalent) with no `end_date`/expiration,
or expiration set far in the future (multi-year) with no rotation automation.

### 5. Don't disable Azure AD authentication on resources that support it

Where a resource offers both key-based and Azure AD-based authentication (Storage, Cosmos DB,
SQL, Key Vault), Azure AD auth should be enabled and, where the workload allows, key-based
auth should be explicitly disabled rather than left available "just in case."

```hcl
# Good - Azure AD auth required, local/key-based auth disabled
resource "azurerm_storage_account" "data" {
  # ...
  shared_access_key_enabled = false
}

resource "azurerm_mssql_server" "sql" {
  # ...
  azuread_administrator {
    login_username = "sql-admins"
    object_id       = data.azuread_group.sql_admins.object_id
  }
  # local auth disabled at the database/server level per resource's own setting
}
```

**Flag:** `shared_access_key_enabled` left at its default (`true`) or explicitly set to `true`
on a storage account with no documented reason a legacy consumer still needs key-based
access.

## RBAC & Access Control

### 1. Prefer Azure RBAC role assignments over resource-level access keys/tokens

This is the central rule this folder builds on: whenever a resource supports both a
static-token access path (storage account keys, SAS tokens, Cosmos DB primary/secondary
keys, Service Bus/Event Hub connection strings with embedded shared access signatures) and an
Azure AD RBAC path, provision access through RBAC role assignments and identities, not the
static token.

```hcl
# Bad - grants access via a generated SAS token embedded elsewhere
resource "azurerm_storage_account_sas" "app_access" {
  connection_string = azurerm_storage_account.data.primary_connection_string
  # ...
}

# Good - grants access via a scoped RBAC role assignment to an identity
resource "azurerm_role_assignment" "app_to_storage" {
  scope                = azurerm_storage_account.data.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_linux_web_app.app.identity[0].principal_id
}
```

**Flag:** `azurerm_storage_account_sas`, `list_keys()`/`primary_access_key`,
`primary_connection_string` outputs consumed by another resource's configuration instead of
an `azurerm_role_assignment` to that resource's managed identity.

### 2. Role assignments are scoped as narrowly as possible

Scope `azurerm_role_assignment` to the specific resource (or, failing that, the resource
group) that actually needs access - not the subscription or management group - unless the
role's purpose is genuinely subscription/management-group-wide (e.g., a policy remediation
identity).

```hcl
# Bad - grants Contributor over the entire subscription for one app's storage access
resource "azurerm_role_assignment" "too_broad" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_web_app.app.identity[0].principal_id
}

# Good - scoped to exactly the resource the identity needs to touch
resource "azurerm_role_assignment" "scoped" {
  scope                = azurerm_storage_account.data.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_web_app.app.identity[0].principal_id
}
```

**Flag:** `scope` set to a subscription or management group ID for a role assignment whose
purpose is a single application/resource's access needs; any role assignment scope wider than
the resource group containing the resources actually being accessed, without a stated reason.

### 3. Avoid `Owner`/`Contributor` as a default; use the least-privileged built-in or custom role

`Owner` and `Contributor` grant broad write access (including, for `Owner`, the ability to
grant further access to others). Prefer a purpose-built role (`Storage Blob Data Contributor`,
`Key Vault Secrets User`, `AcrPull`, etc.) or a custom role definition scoped to the exact
actions needed.

```hcl
# Bad
resource "azurerm_role_assignment" "app" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Owner"
  principal_id         = azurerm_linux_web_app.app.identity[0].principal_id
}

# Good
resource "azurerm_role_assignment" "app" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.app.identity[0].principal_id
}
```

**Flag:** `Owner` or `Contributor` assigned to an application/service identity (as opposed to
a human/break-glass admin identity, which is a separate, deliberate decision); a custom role
definition whose `actions` include a wildcard (`*`) covering far more than the role actually
needs to do.

### 4. Human access goes through Azure AD groups, not individually-assigned roles

Role assignments for people should target an Azure AD group (managed through your identity
provider/PIM process), not individual `principal_id`s hardcoded per person - this avoids
Terraform code churn every time someone joins/leaves a team and keeps access reviewable in one
place.

**Flag:** `azurerm_role_assignment` resources with a hardcoded individual user's object ID as
`principal_id`, especially multiple such resources granting the same role to different
individuals instead of one group.

### 5. Prefer time-bound/PIM-eligible access for privileged roles over standing assignments

For genuinely privileged roles (anything Owner-equivalent, or access to production secrets),
prefer Azure AD Privileged Identity Management (PIM)-eligible role assignments over permanent,
standing role assignments, where the organization's PIM setup supports managing this through
Terraform/`azurerm` resources (e.g. `azurerm_pim_eligible_role_assignment`).

**Flag:** a standing (non-eligible, non-time-bound) role assignment for a highly privileged
role granted to a human identity with no discussion of why standing access is required.

### 6. Deny-by-default network and data-plane access, grant explicitly

Resources should default to denying access (network rules `default_action = "Deny"`, Key
Vault/Storage firewall rules restricting to known networks) and grant specific
identities/networks access explicitly, rather than defaulting open and trying to restrict
later.

**Flag:** `default_action = "Allow"` on a storage account/Key Vault network ACL block with no
further restriction; a Key Vault access policy or RBAC role granting broad `Get/List/Set/Delete`
secret permissions to an identity that only needs to read one specific secret.

## Secrets & Key Vault

### 1. No secrets in `.tf`/`.tfvars` files or source control, ever

Passwords, API keys, connection strings, and certificates must never appear as literal values
in Terraform source, `.tfvars` files, or CI configuration checked into the repository -
including in comments or "temporary" placeholder values that look real.

```hcl
# Bad
resource "azurerm_mssql_server" "sql" {
  administrator_login_password = "SuperSecretP@ssw0rd123!"
}

# Good - sourced from Key Vault at apply time, never written into source
data "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "sql-admin-password"
  key_vault_id = data.azurerm_key_vault.kv.id
}

resource "azurerm_mssql_server" "sql" {
  administrator_login_password = data.azurerm_key_vault_secret.sql_admin_password.value
}
```

**Flag:** any credential-shaped string literal in a diff; a `.tfvars` file with a
`sensitive`-looking variable set to a literal value instead of being populated from a secret
store or left for the CI pipeline to inject from its own secret store.

### 2. Prefer not generating/storing long-lived secrets at all - use managed identity instead

Before reaching for a Key Vault secret, check whether the target resource supports managed
identity + RBAC instead (see
[Authentication & Identity](#authentication--identity) and
[RBAC & Access Control](#rbac--access-control)). Key Vault is for secrets
that genuinely must exist (third-party API keys, database admin passwords for engines with no
Azure AD auth option), not a way to make a static-credential design acceptable.

**Flag:** a new Key Vault secret introduced for a credential whose target resource actually
supports managed identity/Azure AD authentication as an alternative.

### 3. Mark sensitive variables and outputs

Any Terraform variable or output carrying a secret value must be declared `sensitive = true`,
so it's redacted from CLI output. This is a floor, not a ceiling - it does not encrypt the
state file (see [State Management](#state-management)) or prevent the value from
being read by anyone with state access.

```hcl
variable "sql_admin_password" {
  type      = string
  sensitive = true
}
```

**Flag:** a variable/output whose name or usage implies a secret (password, key, token,
connection string) with no `sensitive = true`.

### 4. Generate random secrets with `random_password`, not hardcoded defaults

Where Terraform itself needs to generate a secret (e.g., an initial admin password before
switching a resource to Azure AD-only auth), use the `random_password` resource with
sufficient length/complexity, store the result in Key Vault, and mark it sensitive - never
default to a fixed/predictable value.

```hcl
resource "random_password" "sql_admin" {
  length  = 32
  special = true
}

resource "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "sql-admin-password"
  value        = random_password.sql_admin.result
  key_vault_id = azurerm_key_vault.kv.id
}
```

**Flag:** a hardcoded default value on a password/secret variable
(`default = "changeme"` or similar); secrets generated with low entropy (short length, no
special characters) for anything beyond throwaway dev/test environments.

### 5. Key Vault itself has purge protection and soft delete enabled

The Key Vault resource holding secrets should not be deletable/purgeable without a recovery
window - `purge_protection_enabled = true` and the default soft-delete retention should be
enabled for any Key Vault holding production secrets.

```hcl
resource "azurerm_key_vault" "kv" {
  # ...
  purge_protection_enabled   = true
  soft_delete_retention_days = 90
}
```

**Flag:** `purge_protection_enabled = false` (or omitted, if the provider default in use is
`false`) on a production Key Vault.

### 6. Key Vault access is via RBAC role assignments, not the legacy access-policy model, where
the environment allows it

Prefer `enable_rbac_authorization = true` on the Key Vault plus `azurerm_role_assignment`
resources (e.g. `Key Vault Secrets User`) over the legacy `access_policy` blocks, for
consistency with the RBAC-first approach used everywhere else and easier auditing via Azure
AD.

**Flag:** new Key Vault access-policy blocks added to a Key Vault that already has
`enable_rbac_authorization = true`; a newly created Key Vault defaulting to the legacy
access-policy model with no stated reason.

## Networking & Private Access

### 1. Disable public network access on PaaS resources by default

Storage accounts, Key Vault, SQL/Cosmos DB, and similar managed services should have public
network access disabled and reached via Private Link/private endpoints, unless there's a
specific, stated reason a resource needs to be publicly reachable (e.g., a genuinely public
static website).

```hcl
# Bad - default public access left open
resource "azurerm_storage_account" "data" {
  # ... no network restriction at all
}

# Good
resource "azurerm_storage_account" "data" {
  # ...
  public_network_access_enabled = false
}

resource "azurerm_private_endpoint" "data_blob" {
  name                = "pe-st-data-blob"
  location            = azurerm_storage_account.data.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "st-data-blob"
    private_connection_resource_id = azurerm_storage_account.data.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
}
```

**Flag:** `public_network_access_enabled` left at its default (`true`) or explicitly `true`
on a resource holding non-public data, with no private endpoint and no documented reason.

### 2. No `0.0.0.0/0` (or equivalent "any") rules in NSGs or firewall rules

Network Security Group rules and resource-level firewall/network rules should specify actual
source ranges (specific CIDR blocks, an Azure service tag, or a specific subnet/VNet) rather
than allowing all sources.

```hcl
# Bad
resource "azurerm_network_security_rule" "allow_all" {
  source_address_prefix      = "*"
  destination_port_range     = "*"
  access                      = "Allow"
  direction                   = "Inbound"
  # ...
}

# Good
resource "azurerm_network_security_rule" "allow_https_from_gateway" {
  source_address_prefix      = azurerm_subnet.app_gateway.address_prefixes[0]
  destination_port_range     = "443"
  access                      = "Allow"
  direction                   = "Inbound"
  # ...
}
```

**Flag:** `source_address_prefix = "*"` or `"0.0.0.0/0"` combined with `access = "Allow"` on
an inbound rule, especially for management ports (22, 3389, 5985/5986) or database ports.

### 3. Management ports are never open to the internet

RDP (3389), SSH (22), and direct database ports should not be reachable from `Internet`/`*` in
any NSG rule. Use Azure Bastion, a jump box on a private network, VPN/ExpressRoute, or
just-in-time (JIT) VM access instead of opening these ports broadly.

**Flag:** an NSG rule allowing inbound traffic on 22/3389 (or a database's default port) from
any source broader than a specific known management network/Bastion subnet.

### 4. Segment networks by function/trust boundary

Use separate subnets (and, where appropriate, separate VNets with peering) for different
tiers/trust levels - e.g., a subnet for private endpoints, a subnet for application
compute, a subnet for data services - rather than placing everything in one flat address
space with no NSGs between tiers.

**Flag:** all resources placed in a single subnet with no NSG associated, especially when the
resources span clearly different trust levels (public-facing compute vs. data stores).

### 5. TLS/HTTPS enforced, minimum TLS version pinned

Resources exposing an endpoint (App Service, Storage, API Management, etc.) should require
HTTPS/TLS and pin a minimum TLS version (1.2 or higher) rather than accepting the platform
default, which may be older for backward compatibility.

```hcl
resource "azurerm_storage_account" "data" {
  # ...
  min_tls_version           = "TLS1_2"
  enable_https_traffic_only = true
}
```

**Flag:** `min_tls_version` omitted or set below `TLS1_2`; `enable_https_traffic_only`
(or the resource's equivalent HTTPS-only setting) explicitly disabled.

### 6. Diagnostic/flow logging enabled on network boundaries

NSGs and any resource acting as a network boundary should have flow logs / diagnostic
settings enabled and routed to a Log Analytics workspace, so network traffic is auditable
(see [Logging & Monitoring](#logging--monitoring)).

**Flag:** an NSG or VNet with no associated flow log / diagnostic setting resource anywhere in
the codebase.

### 7. VNet-integrate compute by default, don't wait to prove it calls out

A reviewing agent generally cannot tell from Terraform alone whether an App Service, Function
App, Container App, or similar compute resource's *application code* calls an external
(non-Azure, third-party) endpoint - that's a runtime behavior of code the agent isn't looking
at, not something the infrastructure declares. What the agent *can* mechanically check is the
resource's own configuration for signals that external calls are likely, and use those to
call the recommendation out more forcefully when found - without treating their absence as
proof there's nothing to worry about. Concretely, scan `app_settings`/`site_config`/
`environment_variables`/similar maps on the resource for:

- A value matching a URL (`https?://...`) whose host is not a first-party Azure domain
  (`*.azure.com`, `*.windows.net`, `*.database.windows.net`, `*.vault.azure.net`,
  `*.documents.azure.com`, `*.azurewebsites.net`, `*.azure-api.net`, `*.core.windows.net`, or
  the org's own internal/private domains) - this is a fairly strong signal of an external
  dependency.
- A setting *key* matching a recognizable third-party service naming pattern - a payment
  gateway, messaging/email provider, CRM, or similar SaaS product name as a prefix (e.g.
  `STRIPE_*`, `TWILIO_*`, `SENDGRID_*`, `PAYPAL_*`), or a generic `*_API_KEY`/`*_WEBHOOK_URL`/
  `*_CLIENT_SECRET` suffix where the prefix isn't one of the org's own internal services.
- An NSG/firewall rule already permitting outbound access broadly (`443` to `Internet`/`*`)
  is itself an admission the workload is expected to reach the public internet.
- Naming/tags on the resource like "integration," "webhook," "sync," or "gateway."

Treat a match as a reason to name the specific setting/rule found in the review comment (so
it's a concrete finding, not a generic nag), but treat the *absence* of a match only as "no
evidence found," not as "confirmed internal-only" - apply the default in the next paragraph
either way.

Because detection is unreliable and workloads change over time (an "internal only" app
commonly grows an external dependency later without anyone updating its network setup), the
practical default is to VNet-integrate compute resources unconditionally, rather than only
when external calls can be confirmed:

```hcl
resource "azurerm_linux_web_app" "app" {
  # ...
  virtual_network_subnet_id = azurerm_subnet.app_integration.id

  site_config {
    vnet_route_all_enabled = true # route ALL outbound traffic through the VNet, not just RFC1918 destinations
  }
}
```

Once outbound traffic actually flows through the VNet, egress can be controlled the same way
regardless of whether today's code happens to call out: a route table sending traffic through
Azure Firewall/an NVA (for logging and destination allow-listing), or a NAT Gateway for a
stable, allow-listable outbound IP - which is exactly what's needed if a partner integration
later requires IP allowlisting. Give the delegated integration subnet its own NSG per
[rule 4](#4-segment-networks-by-functiontrust-boundary) rather than leaving it unrestricted.

**Flag:** an App Service/Function App/Container App with no `virtual_network_subnet_id` (or
equivalent VNet integration) at all, especially one whose app settings reference a
third-party endpoint or API key; VNet integration present but `vnet_route_all_enabled`
(or equivalent "route all" setting) left off, so outbound traffic bypasses the VNet's egress
controls anyway; a compute resource's integration subnet with no NSG or UDR - VNet
integration with no egress control on top of it doesn't add anything.

## Module Design & Structure

### 1. Reusable infrastructure patterns become modules, not copy-pasted resource blocks

If the same combination of resources (e.g., "a web app with its managed identity, RBAC role
assignments, and diagnostic settings") is created more than once with only parameters
differing, extract it into a module rather than duplicating the HCL.

**Flag:** near-identical blocks of resources repeated across multiple root modules/files with
only names/parameters changed, and no shared module behind them.

### 2. Module inputs are typed and validated, not implicitly `any`

Module `variable` blocks should declare an explicit `type` (not the default `any`), and use
`validation` blocks for constraints that matter (allowed value sets, length/format
constraints) so misconfiguration is caught at `plan` time, not after `apply` fails against
Azure's API.

```hcl
# Bad
variable "environment" {}

# Good
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}
```

**Flag:** module variables with no `type`; a variable whose valid values are a known, small
set with no `validation` block enforcing it.

### 3. Module versions are pinned when sourced from a registry/remote source

When consuming a module from the Terraform Registry, a private registry, or a git source,
pin an explicit version (`version = "~> 3.1"`) or a specific tag/commit for a git source -
never leave a module source unpinned so it can silently change under you.

```hcl
# Bad
module "vnet" {
  source = "git::https://github.com/org/terraform-azure-vnet.git"
}

# Good
module "vnet" {
  source  = "app.terraform.io/org/vnet/azurerm"
  version = "~> 3.1"
}
```

**Flag:** a git-sourced module reference with no `ref`/tag pinning a specific version;
a registry module source with no `version` constraint.

### 4. Provider versions are pinned in `required_providers`

Every root module should declare `required_providers` with a version constraint for
`azurerm` (and any other provider in use), so `terraform init` doesn't silently pick up a new
major version with breaking changes.

```hcl
terraform {
  required_version = ">= 1.7"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}
```

**Flag:** a root module with no `required_providers` block, or a provider version constraint
wide enough to span a major version boundary (e.g. `>= 3.0` with no upper bound).

### 5. Outputs expose only what consumers need, not entire resource objects

Module outputs should be specific values (an ID, a name, a connection endpoint), not the
entire resource block dumped as an output "just in case," which leaks internal implementation
details and can inadvertently expose sensitive attributes.

**Flag:** an output like `output "storage_account" { value = azurerm_storage_account.this }`
exposing the whole resource object instead of the specific attributes callers need.

### 6. Root modules are organized predictably

A consistent file layout (`main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`/`versions.tf`,
and per-concern files as a module grows) makes review and navigation predictable across a
team's repos. Don't put everything in a single sprawling `main.tf` once a module grows past a
handful of resources.

**Flag:** a `main.tf` exceeding a few hundred lines with clearly separable concerns (e.g.
networking, compute, and data resources all interleaved in one file) and no split into
logical files or child modules.

## Naming & Tagging

### 1. Follow a consistent resource naming convention

Adopt (or adapt) the Azure Cloud Adoption Framework naming convention -
`<resource-type-abbreviation>-<workload>-<environment>-<region>-<instance>` (e.g.
`rg-payments-prod-eastus-001`, `st` + workload for storage accounts respecting the
alphanumeric-only, lowercase, 3-24 character constraint) - and apply it consistently across
all resources rather than ad hoc naming per module/author.

```hcl
# Bad - inconsistent, unclear naming
resource "azurerm_resource_group" "rg1" {
  name = "myrg"
}

# Good
resource "azurerm_resource_group" "this" {
  name = "rg-payments-prod-eastus"
}
```

**Flag:** resource names with no discernible convention, ambiguous abbreviations, or that
don't encode workload/environment where the rest of the codebase does; storage
account/Key Vault names that will fail Azure's naming constraints (e.g., uppercase letters or
hyphens in a storage account name).

### 2. Use a shared naming module/locals rather than hand-typing names per resource

Compute names from shared `locals` (or a naming module such as `Azure/naming/azurerm`) fed by
workload/environment/region variables, rather than typing out the full name string at every
resource - this keeps naming consistent automatically as the convention evolves.

```hcl
locals {
  name_prefix = "${var.workload}-${var.environment}-${var.region_short}"
}

resource "azurerm_resource_group" "this" {
  name = "rg-${local.name_prefix}"
}
```

**Flag:** the same workload/environment/region string literals repeated and hand-typed across
many resource names instead of derived from shared locals/variables.

### 3. Every resource is tagged consistently

Apply a common tag set (at minimum: `environment`, `owner`/`team`, `cost-center` or
equivalent, and the source repo/module that manages it) to every resource, via a shared
`default_tags`-style local merged into each resource's `tags` argument, not manually retyped
per resource.

```hcl
locals {
  default_tags = {
    environment = var.environment
    owner       = var.team
    managed_by  = "terraform"
    repo        = "github.com/org/infra-payments"
  }
}

resource "azurerm_resource_group" "this" {
  # ...
  tags = local.default_tags
}
```

**Flag:** resources with no `tags` argument at all; tags present but inconsistent in key
naming/casing across resources in the same codebase (`Environment` vs `environment` vs `env`).

### 4. Tags don't carry secrets or sensitive data

Tags are visible to anyone with read access to the resource (often more broadly than the
resource's actual data-plane permissions) and appear in cost/billing exports - never put a
credential, connection detail, or PII into a tag value.

**Flag:** a tag value containing anything that looks like a secret, key, or personal data.

## Resource Protection & Lifecycle

### 1. Protect stateful/critical resources with `prevent_destroy`

Resources holding data that would be catastrophic to lose (production databases, storage
accounts, Key Vaults) should use a `lifecycle { prevent_destroy = true }` block so a mistaken
`terraform destroy` or a plan that unintentionally recreates the resource fails safely instead
of silently deleting data.

```hcl
resource "azurerm_mssql_database" "prod" {
  # ...
  lifecycle {
    prevent_destroy = true
  }
}
```

**Flag:** a production database, storage account, or Key Vault resource with no
`prevent_destroy` lifecycle protection.

### 2. Also apply an Azure Resource Lock so it can't be deleted outside Terraform either

`prevent_destroy` only stops *Terraform* from destroying the resource - it does nothing to
stop someone deleting the same resource by hand in the Azure Portal, via the Azure CLI, or
through the REST API directly. Anything that might hold real business data - SQL
servers/databases, Cosmos DB accounts, storage accounts and the blob containers on them, Key
Vaults - should also get an Azure Resource Lock with `CanNotDelete`, so deletion is blocked
platform-wide - through the GUI included - regardless of who's doing it or which tool they're
using, until the lock is explicitly removed first (itself a separate, auditable,
permission-gated action).

```hcl
resource "azurerm_management_lock" "prod_db" {
  name       = "prevent-delete"
  scope      = azurerm_mssql_database.prod.id
  lock_level = "CanNotDelete"
  notes      = "Production database - remove this lock deliberately before any planned deletion."
}

resource "azurerm_management_lock" "prod_cosmos" {
  name       = "prevent-delete"
  scope      = azurerm_cosmosdb_account.prod.id
  lock_level = "CanNotDelete"
  notes      = "Holds production data - remove this lock deliberately before any planned deletion."
}

resource "azurerm_management_lock" "prod_storage" {
  name       = "prevent-delete"
  scope      = azurerm_storage_account.data.id
  lock_level = "CanNotDelete"
  notes      = "Holds production blob data - remove this lock deliberately before any planned deletion."
}
```

A lock can be applied at the resource group level to cover everything underneath it in one
place, or per-resource for finer control over which specific resources are protected - either
is fine as long as every business-data-bearing resource ends up covered by one. Use
`CanNotDelete` (blocks delete, still allows configuration updates) rather than `ReadOnly`
(blocks updates too) unless the resource's configuration should be frozen as well. Removing a
lock should itself be a deliberate, reviewed change (a Terraform PR, or a break-glass
procedure), not something routinely done to work around it.

**Flag:** a SQL server/database, Cosmos DB account, storage account/blob container, or Key
Vault holding business data with `prevent_destroy` in Terraform but no corresponding
`azurerm_management_lock` (directly on it or inherited from its resource group) -
`prevent_destroy` alone leaves manual deletion through the Portal, CLI, or API completely
unguarded.

### 3. Understand `create_before_destroy` implications before relying on it

When using `create_before_destroy` to avoid downtime during a replace, verify the resource
doesn't have naming/uniqueness constraints that would make the "create" side fail while the
old resource still exists (e.g., a globally-unique storage account name). Don't add it
reflexively to every resource without checking whether it can actually succeed.

**Flag:** `create_before_destroy = true` on a resource whose name/identifier must be globally
or account-unique, with no accompanying strategy (e.g., a name suffix/random ID) for how two
copies can coexist momentarily.

### 4. Enable backups/recovery features on data-bearing resources

Databases, storage accounts, and similar resources should have their platform's backup/
recovery feature enabled (automated backups with a defined retention, geo-redundant storage
where the data's importance warrants it, point-in-time restore where available) rather than
relying solely on `prevent_destroy` to prevent data loss - that guards against Terraform
deleting the resource, not against data loss from other causes.

```hcl
resource "azurerm_mssql_database" "prod" {
  # ...
  short_term_retention_policy {
    retention_days = 35
  }
}

resource "azurerm_storage_account" "data" {
  # ...
  account_replication_type = "GRS"
}
```

**Flag:** a production data-bearing resource with no backup/retention configuration at all,
or replication set to locally-redundant (`LRS`) with no stated reason for a workload whose
data loss would be significant.

### 5. Soft delete/purge protection enabled wherever the resource type offers it

Key Vault (see [Secrets & Key Vault](#secrets--key-vault)), storage blobs,
and other resources offering soft-delete should have it enabled, so accidental deletion has a
recovery window before data is permanently gone.

**Flag:** soft-delete/purge-protection settings left disabled or omitted (defaulting to
disabled) on a resource type that offers them, for any environment beyond throwaway
dev/sandbox.

### 6. Don't use `ignore_changes = all` or broad ignore-changes as a shortcut

`lifecycle { ignore_changes = [...] }` should list the specific attributes that are
legitimately managed outside Terraform (e.g., an attribute set by an autoscaler), not `all` or
a broad list used to silence drift the team hasn't actually investigated.

```hcl
# Bad - hides all drift, including changes that matter
lifecycle {
  ignore_changes = all
}

# Good - only ignores the one attribute genuinely managed elsewhere
lifecycle {
  ignore_changes = [tags["last_scaled_at"]]
}
```

**Flag:** `ignore_changes = all` anywhere; an `ignore_changes` list broad enough to plausibly
hide security-relevant attribute drift (network rules, auth settings, role assignments).

### 7. Destructive operations require explicit review, not blanket auto-approve

`terraform apply -auto-approve` (or CI equivalents that skip a plan-review gate) should not be
used for environments where an unreviewed destructive change would be costly - require a
human-reviewed plan output before apply in shared/production environments (see
[CI/CD & Workflow](#cicd--workflow)).

**Flag:** `-auto-approve` used in a CI pipeline step that applies to a shared or production
environment with no preceding plan-approval gate.

## Logging & Monitoring

### 1. Diagnostic settings enabled on resources that support them

Resources should ship platform logs/metrics to a Log Analytics workspace (or Storage/Event
Hub, depending on the org's log-routing strategy) via an `azurerm_monitor_diagnostic_setting`
resource, rather than leaving diagnostics unconfigured and unobservable.

```hcl
resource "azurerm_monitor_diagnostic_setting" "kv_diagnostics" {
  name                       = "kv-diagnostics"
  target_resource_id         = azurerm_key_vault.kv.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "AuditEvent"
  }
  metric {
    category = "AllMetrics"
  }
}
```

**Flag:** a Key Vault, storage account, SQL server/database, App Service, or NSG with no
corresponding `azurerm_monitor_diagnostic_setting` anywhere in the codebase.

### 2. Audit-relevant resources specifically capture audit logs

Key Vault (`AuditEvent`), SQL (auditing/`extended_auditing_policy`), and storage (blob/queue
read-write-delete logging) should have their audit-specific log categories enabled - not just
generic metrics - since these are what let you answer "who accessed this secret/data and
when."

**Flag:** a diagnostic setting on an audit-relevant resource that only forwards `AllMetrics`
and omits the resource's audit/access log category.

### 3. Log retention is set deliberately, not left at a default that doesn't match policy

Log Analytics workspace retention (and any Storage-based log archival) should be set to match
the organization's actual compliance/retention requirements, rather than left at whatever the
provider's default happens to be.

```hcl
resource "azurerm_log_analytics_workspace" "this" {
  # ...
  retention_in_days = 90
}
```

**Flag:** `retention_in_days` omitted (relying on an unexamined default) on a workspace backing
production audit logs, when the organization has a stated retention requirement.

### 4. Alerting exists for security-relevant conditions, not just resource health

Beyond basic health/performance alerts, consider (and where the org has a defined policy,
require) alert rules for security-relevant signals available through Azure Monitor/Defender
for Cloud - e.g., a role assignment change at a sensitive scope, a Key Vault access policy
change, unusual sign-in activity - rather than only alerting on CPU/memory/availability.

**Flag:** an environment with `azurerm_monitor_metric_alert`/`azurerm_monitor_activity_log_alert`
resources covering only infrastructure health, with no alerting on access/permission changes
for resources holding secrets or sensitive data, where the org has stated this is required.

### 5. Diagnostic/log data itself is access-controlled

The Log Analytics workspace and any storage account used for log archival should follow the
same RBAC-over-keys and private-access principles as any other resource
(see [RBAC & Access Control](#rbac--access-control) and
[Networking & Private Access](#networking--private-access)) - logs often
contain sensitive operational detail and shouldn't be more loosely protected than the
resources they're logging.

**Flag:** a Log Analytics workspace or log-archival storage account with broader network/
access-key exposure than the resources whose logs it stores.

## CI/CD & Workflow

### 1. `plan` on pull request, `apply` only after merge/approval

Every change should produce a `terraform plan` output visible on the pull request before
anything is applied, and `apply` should run only after the PR is approved and merged (or via
an explicit, gated approval step) - never `apply` directly from an unreviewed branch against
a shared environment.

**Flag:** a workflow that runs `terraform apply` on every push to a feature branch, or on a
pull request event, rather than gating apply behind merge/approval.

### 2. Separate credentials/identities per environment

Dev, staging, and production should use distinct Azure AD app registrations/federated
identities for pipeline authentication, each scoped (via RBAC) only to its own environment's
resources - not one shared pipeline identity with access to every environment.

**Flag:** a single `AZURE_CLIENT_ID`/service connection used across dev, staging, and
production pipeline jobs; a pipeline identity with role assignments spanning multiple
environments' resource groups or subscriptions.

### 3. `plan` output is reviewed for unexpected destroys/replacements

A reviewer (human or a policy-as-code gate) should look at the actual plan diff before
approving, specifically checking for unexpected `-`/`destroy` or `-/+`/`replace` actions on
resources that shouldn't be affected by the change - not just rubber-stamp approving because
CI is green.

**Flag:** a merged PR whose plan output included an unexplained destroy/replace of a resource
unrelated to the stated purpose of the change, with no comment addressing it.

### 4. Drift detection runs on a schedule, not only on demand

A scheduled pipeline (e.g., nightly) should run `terraform plan` against each environment and
alert if it detects drift (manual changes made outside Terraform), so drift is caught
proactively rather than discovered the next time someone happens to run a plan.

**Flag:** no scheduled drift-detection job anywhere in the repository's CI configuration for
environments Terraform is meant to be the source of truth for.

### 5. `terraform fmt` and `terraform validate` are enforced in CI

Every pipeline run should fail if code isn't formatted (`terraform fmt -check`) or doesn't
pass `terraform validate`, so basic issues are caught before a human reviewer's time is spent
on them.

**Flag:** a CI workflow with no `terraform fmt -check`/`terraform validate` step ahead of
`plan`.

### 6. Pipeline logs don't leak secrets

CI steps should not `echo`/print variables that may contain secrets, and step outputs that
could contain sensitive plan/apply data should be handled with the CI platform's secret
masking rather than assumed safe by default.

**Flag:** a pipeline step that echoes an environment variable, `terraform output`, or command
result that could contain a secret value without going through the platform's secret-masking
mechanism.

## Code Style & Structure

### 1. Run `terraform fmt`

All committed HCL should be formatted with `terraform fmt`. This is mechanical and should
never be a manual nitpick in review - enforce it in CI (see
[CI/CD & Workflow](#cicd--workflow)) instead.

**Flag:** obviously unformatted HCL (inconsistent indentation/alignment) in a diff, as a
signal `terraform fmt` isn't being enforced.

### 2. No hardcoded values that should be variables

Values that differ by environment (region, SKU/size, replica count, IP ranges) should be
variables or locals derived from variables, not hardcoded literals duplicated across
environment-specific files/workspaces.

```hcl
# Bad
resource "azurerm_mssql_database" "db" {
  sku_name = "S3"
}

# Good
resource "azurerm_mssql_database" "db" {
  sku_name = var.sql_sku
}
```

**Flag:** the same literal value that clearly varies by environment (a SKU, an instance
count, a region) hardcoded directly in a resource block rather than parameterized.

### 3. `count`/`for_each` used deliberately, with stable keys

Prefer `for_each` over `count` when creating multiple similar resources from a map/set, since
`for_each` keys resources by a stable identifier rather than a numeric index - `count` can
cause unrelated resources to be destroyed/recreated when an item is removed from the middle of
a list.

```hcl
# Bad - removing the first item shifts every subsequent index, forcing replacements
resource "azurerm_subnet" "this" {
  count = length(var.subnet_names)
  name  = var.subnet_names[count.index]
}

# Good - stable per-key identity
resource "azurerm_subnet" "this" {
  for_each = toset(var.subnet_names)
  name     = each.value
}
```

**Flag:** `count` used to iterate over a list of named items (rather than a genuinely
numeric "create N of these") where removing/reordering an item would cause unrelated
resources to be destroyed and recreated.

### 4. `locals` for derived/computed values, not repeated expressions

If the same expression (a computed name, a merged tag map, a conditional value) is used more
than once, compute it once in `locals` and reference it, rather than repeating the expression.

**Flag:** the same non-trivial expression (string interpolation, a ternary, a `merge()` call)
duplicated verbatim across multiple resource blocks.

### 5. Data sources over hardcoded IDs for existing resources

Reference existing resources Terraform doesn't manage (an existing resource group, an
existing VNet, a shared Log Analytics workspace) via a `data` source, not a hardcoded resource
ID string, so the reference stays correct if the underlying resource's ID components change.

```hcl
# Bad
resource "azurerm_subnet" "this" {
  virtual_network_name = "vnet-shared-prod-eastus"
  # resource group hardcoded elsewhere too
}

# Good
data "azurerm_virtual_network" "shared" {
  name                = "vnet-shared-prod-eastus"
  resource_group_name = "rg-network-prod-eastus"
}
```

**Flag:** a hardcoded Azure resource ID string (`/subscriptions/.../resourceGroups/...`) used
directly in a resource argument instead of a `data` source reference.

### 6. Comments explain why, not what

A comment on a non-obvious `lifecycle` block, an `ignore_changes` entry, or a workaround for a
provider quirk should explain the reason, since that's what a future reader (or reviewing
agent) can't infer from the code itself. Don't add comments that just restate what the HCL
already says.

**Flag:** a comment that only repeats the resource/argument name with no added reasoning;
conversely, a non-obvious `ignore_changes`, `depends_on`, or workaround with no comment at
all explaining why it's there.

## Policy & Compliance Scanning

### 1. Static analysis (`tfsec`/`checkov`/`terrascan` or equivalent) runs in CI

A policy-as-code scanner should run against every plan/PR, catching common Azure
misconfigurations (public network access left open, missing encryption, overly permissive
RBAC, disabled soft-delete) automatically rather than relying entirely on human reviewers to
notice them.

**Flag:** no static-analysis/policy-scanning step present in the CI pipeline for a repository
managing production Azure infrastructure.

### 2. Scanner findings are triaged, not blanket-suppressed

Suppressing a scanner finding (an inline ignore comment, an exception file) should be a
deliberate, reviewed decision with a stated reason, not a default response to make CI pass.

```hcl
# Bad - suppressed with no reasoning
#tfsec:ignore:azure-storage-default-action-deny

# Good - suppressed with a stated, reviewable reason
#tfsec:ignore:azure-storage-default-action-deny -- public read access is required for this
# static asset container; see ADR-0042.
```

**Flag:** a scanner-suppression comment/exception with no explanation; a large or growing
suppression list that isn't periodically reviewed.

### 3. Azure Policy complements, but doesn't replace, Terraform-level controls

Where the organization uses Azure Policy for guardrails (e.g., denying public storage
accounts at the subscription level), Terraform code should still be written to comply
proactively rather than relying on Policy to reject a non-compliant `apply` after the fact -
policy is a safety net, not the primary control.

**Flag:** infrastructure code that would be rejected by the organization's known Azure Policy
assignments, submitted with the expectation that Policy enforcement will catch it at apply
time.

### 4. Compliance-relevant resource properties are tested, not just eyeballed

For resources where a compliance requirement is well-defined (encryption at rest, minimum TLS
version, public access disabled), prefer an automated check (a static-analysis rule, a
Terraform test using the `terraform test` framework, or an Open Policy Agent/Conftest policy
run against plan JSON) over relying solely on manual review to catch a regression later.

**Flag:** a compliance requirement that has been violated and caught in review before, with
no corresponding automated check added afterward to prevent a recurrence.

