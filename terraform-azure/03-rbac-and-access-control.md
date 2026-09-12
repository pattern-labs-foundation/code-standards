# RBAC & Access Control

## 1. Prefer Azure RBAC role assignments over resource-level access keys/tokens

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

## 2. Role assignments are scoped as narrowly as possible

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

## 3. Avoid `Owner`/`Contributor` as a default; use the least-privileged built-in or custom role

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

## 4. Human access goes through Azure AD groups, not individually-assigned roles

Role assignments for people should target an Azure AD group (managed through your identity
provider/PIM process), not individual `principal_id`s hardcoded per person - this avoids
Terraform code churn every time someone joins/leaves a team and keeps access reviewable in one
place.

**Flag:** `azurerm_role_assignment` resources with a hardcoded individual user's object ID as
`principal_id`, especially multiple such resources granting the same role to different
individuals instead of one group.

## 5. Prefer time-bound/PIM-eligible access for privileged roles over standing assignments

For genuinely privileged roles (anything Owner-equivalent, or access to production secrets),
prefer Azure AD Privileged Identity Management (PIM)-eligible role assignments over permanent,
standing role assignments, where the organization's PIM setup supports managing this through
Terraform/`azurerm` resources (e.g. `azurerm_pim_eligible_role_assignment`).

**Flag:** a standing (non-eligible, non-time-bound) role assignment for a highly privileged
role granted to a human identity with no discussion of why standing access is required.

## 6. Deny-by-default network and data-plane access, grant explicitly

Resources should default to denying access (network rules `default_action = "Deny"`, Key
Vault/Storage firewall rules restricting to known networks) and grant specific
identities/networks access explicitly, rather than defaulting open and trying to restrict
later.

**Flag:** `default_action = "Allow"` on a storage account/Key Vault network ACL block with no
further restriction; a Key Vault access policy or RBAC role granting broad `Get/List/Set/Delete`
secret permissions to an identity that only needs to read one specific secret.
