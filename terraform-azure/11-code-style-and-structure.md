# Code Style & Structure

## 1. Run `terraform fmt`

All committed HCL should be formatted with `terraform fmt`. This is mechanical and should
never be a manual nitpick in review - enforce it in CI (see
[10-ci-cd-and-workflow.md](./10-ci-cd-and-workflow.md)) instead.

**Flag:** obviously unformatted HCL (inconsistent indentation/alignment) in a diff, as a
signal `terraform fmt` isn't being enforced.

## 2. No hardcoded values that should be variables

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

## 3. `count`/`for_each` used deliberately, with stable keys

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

## 4. `locals` for derived/computed values, not repeated expressions

If the same expression (a computed name, a merged tag map, a conditional value) is used more
than once, compute it once in `locals` and reference it, rather than repeating the expression.

**Flag:** the same non-trivial expression (string interpolation, a ternary, a `merge()` call)
duplicated verbatim across multiple resource blocks.

## 5. Data sources over hardcoded IDs for existing resources

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

## 6. Comments explain why, not what

A comment on a non-obvious `lifecycle` block, an `ignore_changes` entry, or a workaround for a
provider quirk should explain the reason, since that's what a future reader (or reviewing
agent) can't infer from the code itself. Don't add comments that just restate what the HCL
already says.

**Flag:** a comment that only repeats the resource/argument name with no added reasoning;
conversely, a non-obvious `ignore_changes`, `depends_on`, or workaround with no comment at
all explaining why it's there.
