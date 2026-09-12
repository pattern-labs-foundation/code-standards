# Authentication & Identity

## 1. CI/CD pipelines authenticate via OIDC/workload identity federation, not a stored client secret

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

## 2. Azure resources authenticate to each other via managed identity, not embedded credentials

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

## 3. Human/local Terraform runs use Azure CLI/`az login` context, not embedded credentials

For local development, rely on the `azurerm` provider's default Azure CLI authentication
(`az login`) rather than hardcoding a service principal's credentials into a `.tfvars` file
or shell profile.

**Flag:** `.tfvars`/`.env` files (even ones intended to be local-only) containing a
`client_secret`, and no corresponding `.gitignore` entry for them; documentation instructing
contributors to set `ARM_CLIENT_SECRET` as a plain environment variable for routine local use.

## 4. If a service principal secret is genuinely unavoidable, it is short-lived and stored in Key
Vault, not in Terraform variables or CI secrets directly

Some third-party integrations still require a client secret. When that's genuinely
unavoidable: set a short expiration, store it in Key Vault (see
[04-secrets-and-key-vault.md](./04-secrets-and-key-vault.md)), and reference it from there at
apply/runtime rather than passing it as a plain `-var` or CI secret with no rotation plan.

**Flag:** `azuread_service_principal_password` (or equivalent) with no `end_date`/expiration,
or expiration set far in the future (multi-year) with no rotation automation.

## 5. Don't disable Azure AD authentication on resources that support it

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
