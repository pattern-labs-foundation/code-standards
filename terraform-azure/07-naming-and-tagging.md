# Naming & Tagging

## 1. Follow a consistent resource naming convention

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

## 2. Use a shared naming module/locals rather than hand-typing names per resource

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

## 3. Every resource is tagged consistently

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

## 4. Tags don't carry secrets or sensitive data

Tags are visible to anyone with read access to the resource (often more broadly than the
resource's actual data-plane permissions) and appear in cost/billing exports - never put a
credential, connection detail, or PII into a tag value.

**Flag:** a tag value containing anything that looks like a secret, key, or personal data.
