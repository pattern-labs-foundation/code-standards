# Resource Protection & Lifecycle

## 1. Protect stateful/critical resources with `prevent_destroy`

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

## 2. Understand `create_before_destroy` implications before relying on it

When using `create_before_destroy` to avoid downtime during a replace, verify the resource
doesn't have naming/uniqueness constraints that would make the "create" side fail while the
old resource still exists (e.g., a globally-unique storage account name). Don't add it
reflexively to every resource without checking whether it can actually succeed.

**Flag:** `create_before_destroy = true` on a resource whose name/identifier must be globally
or account-unique, with no accompanying strategy (e.g., a name suffix/random ID) for how two
copies can coexist momentarily.

## 3. Enable backups/recovery features on data-bearing resources

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

## 4. Soft delete/purge protection enabled wherever the resource type offers it

Key Vault (see [04-secrets-and-key-vault.md](./04-secrets-and-key-vault.md)), storage blobs,
and other resources offering soft-delete should have it enabled, so accidental deletion has a
recovery window before data is permanently gone.

**Flag:** soft-delete/purge-protection settings left disabled or omitted (defaulting to
disabled) on a resource type that offers them, for any environment beyond throwaway
dev/sandbox.

## 5. Don't use `ignore_changes = all` or broad ignore-changes as a shortcut

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

## 6. Destructive operations require explicit review, not blanket auto-approve

`terraform apply -auto-approve` (or CI equivalents that skip a plan-review gate) should not be
used for environments where an unreviewed destructive change would be costly - require a
human-reviewed plan output before apply in shared/production environments (see
[10-ci-cd-and-workflow.md](./10-ci-cd-and-workflow.md)).

**Flag:** `-auto-approve` used in a CI pipeline step that applies to a shared or production
environment with no preceding plan-approval gate.
