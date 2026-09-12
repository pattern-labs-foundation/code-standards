# Module Design & Structure

## 1. Reusable infrastructure patterns become modules, not copy-pasted resource blocks

If the same combination of resources (e.g., "a web app with its managed identity, RBAC role
assignments, and diagnostic settings") is created more than once with only parameters
differing, extract it into a module rather than duplicating the HCL.

**Flag:** near-identical blocks of resources repeated across multiple root modules/files with
only names/parameters changed, and no shared module behind them.

## 2. Module inputs are typed and validated, not implicitly `any`

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

## 3. Module versions are pinned when sourced from a registry/remote source

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

## 4. Provider versions are pinned in `required_providers`

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

## 5. Outputs expose only what consumers need, not entire resource objects

Module outputs should be specific values (an ID, a name, a connection endpoint), not the
entire resource block dumped as an output "just in case," which leaks internal implementation
details and can inadvertently expose sensitive attributes.

**Flag:** an output like `output "storage_account" { value = azurerm_storage_account.this }`
exposing the whole resource object instead of the specific attributes callers need.

## 6. Root modules are organized predictably

A consistent file layout (`main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`/`versions.tf`,
and per-concern files as a module grows) makes review and navigation predictable across a
team's repos. Don't put everything in a single sprawling `main.tf` once a module grows past a
handful of resources.

**Flag:** a `main.tf` exceeding a few hundred lines with clearly separable concerns (e.g.
networking, compute, and data resources all interleaved in one file) and no split into
logical files or child modules.
