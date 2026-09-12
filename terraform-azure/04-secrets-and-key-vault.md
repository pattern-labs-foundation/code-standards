# Secrets & Key Vault

## 1. No secrets in `.tf`/`.tfvars` files or source control, ever

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

## 2. Prefer not generating/storing long-lived secrets at all - use managed identity instead

Before reaching for a Key Vault secret, check whether the target resource supports managed
identity + RBAC instead (see
[02-authentication-and-identity.md](./02-authentication-and-identity.md) and
[03-rbac-and-access-control.md](./03-rbac-and-access-control.md)). Key Vault is for secrets
that genuinely must exist (third-party API keys, database admin passwords for engines with no
Azure AD auth option), not a way to make a static-credential design acceptable.

**Flag:** a new Key Vault secret introduced for a credential whose target resource actually
supports managed identity/Azure AD authentication as an alternative.

## 3. Mark sensitive variables and outputs

Any Terraform variable or output carrying a secret value must be declared `sensitive = true`,
so it's redacted from CLI output. This is a floor, not a ceiling - it does not encrypt the
state file (see [01-state-management.md](./01-state-management.md)) or prevent the value from
being read by anyone with state access.

```hcl
variable "sql_admin_password" {
  type      = string
  sensitive = true
}
```

**Flag:** a variable/output whose name or usage implies a secret (password, key, token,
connection string) with no `sensitive = true`.

## 4. Generate random secrets with `random_password`, not hardcoded defaults

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

## 5. Key Vault itself has purge protection and soft delete enabled

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

## 6. Key Vault access is via RBAC role assignments, not the legacy access-policy model, where
the environment allows it

Prefer `enable_rbac_authorization = true` on the Key Vault plus `azurerm_role_assignment`
resources (e.g. `Key Vault Secrets User`) over the legacy `access_policy` blocks, for
consistency with the RBAC-first approach used everywhere else and easier auditing via Azure
AD.

**Flag:** new Key Vault access-policy blocks added to a Key Vault that already has
`enable_rbac_authorization = true`; a newly created Key Vault defaulting to the legacy
access-policy model with no stated reason.
