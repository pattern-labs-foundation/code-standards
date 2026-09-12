# State Management

## 1. Remote state in Azure Storage, never local state

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

## 2. State storage account uses RBAC, not access keys, and has key access disabled where possible

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

## 3. State locking is enabled (default for `azurerm` backend, don't disable it)

Azure's `azurerm` backend handles locking automatically via blob leases - never run with
`-lock=false` outside a genuine, understood recovery scenario, and never script around lock
contention by disabling locking.

**Flag:** `-lock=false` in any checked-in script, pipeline step, or `Makefile`/task runner
target used for routine `plan`/`apply`.

## 4. State storage has versioning, soft delete, and restricted network access

The storage account backing state should have blob versioning and soft-delete enabled (state
corruption/accidental deletion is recoverable), and should not be reachable from the public
internet with no restriction - use a private endpoint or, at minimum, storage account network
rules restricting access to known networks/identities.

**Flag:** the state storage account resource with no `blob_properties` versioning/soft-delete
configuration, or `network_rules { default_action = "Allow" }` with no further restriction.

## 5. Never output or log sensitive values from state

Values marked `sensitive = true` are hidden from `terraform plan`/`apply` console output, but
they still exist in plaintext in the state file itself. Treat the state file as sensitive
data end-to-end (access-controlled storage, encrypted at rest, RBAC-restricted) rather than
relying on the `sensitive` flag as the only protection.

**Flag:** an output marked `sensitive = true` whose value is nonetheless echoed elsewhere
(written to a log file, piped to a non-secure artifact, printed via `terraform output -raw`
in a CI step that logs command output).

## 6. One state file per environment/blast-radius boundary

Don't put every environment (dev/staging/prod) or unrelated resource groups in a single state
file - split by environment and by logical boundary (networking vs. application vs. data), so
a bad `apply` in one area can't affect unrelated infrastructure and blast radius stays small.

**Flag:** a single root module/state file whose resources span multiple environments, or
mix unrelated systems that are typically deployed/changed independently.
