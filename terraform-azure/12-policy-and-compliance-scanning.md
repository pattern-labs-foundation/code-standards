# Policy & Compliance Scanning

## 1. Static analysis (`tfsec`/`checkov`/`terrascan` or equivalent) runs in CI

A policy-as-code scanner should run against every plan/PR, catching common Azure
misconfigurations (public network access left open, missing encryption, overly permissive
RBAC, disabled soft-delete) automatically rather than relying entirely on human reviewers to
notice them.

**Flag:** no static-analysis/policy-scanning step present in the CI pipeline for a repository
managing production Azure infrastructure.

## 2. Scanner findings are triaged, not blanket-suppressed

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

## 3. Azure Policy complements, but doesn't replace, Terraform-level controls

Where the organization uses Azure Policy for guardrails (e.g., denying public storage
accounts at the subscription level), Terraform code should still be written to comply
proactively rather than relying on Policy to reject a non-compliant `apply` after the fact -
policy is a safety net, not the primary control.

**Flag:** infrastructure code that would be rejected by the organization's known Azure Policy
assignments, submitted with the expectation that Policy enforcement will catch it at apply
time.

## 4. Compliance-relevant resource properties are tested, not just eyeballed

For resources where a compliance requirement is well-defined (encryption at rest, minimum TLS
version, public access disabled), prefer an automated check (a static-analysis rule, a
Terraform test using the `terraform test` framework, or an Open Policy Agent/Conftest policy
run against plan JSON) over relying solely on manual review to catch a regression later.

**Flag:** a compliance requirement that has been violated and caught in review before, with
no corresponding automated check added afterward to prevent a recurrence.
