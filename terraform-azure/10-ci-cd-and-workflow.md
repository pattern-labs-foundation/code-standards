# CI/CD & Workflow

## 1. `plan` on pull request, `apply` only after merge/approval

Every change should produce a `terraform plan` output visible on the pull request before
anything is applied, and `apply` should run only after the PR is approved and merged (or via
an explicit, gated approval step) - never `apply` directly from an unreviewed branch against
a shared environment.

**Flag:** a workflow that runs `terraform apply` on every push to a feature branch, or on a
pull request event, rather than gating apply behind merge/approval.

## 2. Separate credentials/identities per environment

Dev, staging, and production should use distinct Azure AD app registrations/federated
identities for pipeline authentication, each scoped (via RBAC) only to its own environment's
resources - not one shared pipeline identity with access to every environment.

**Flag:** a single `AZURE_CLIENT_ID`/service connection used across dev, staging, and
production pipeline jobs; a pipeline identity with role assignments spanning multiple
environments' resource groups or subscriptions.

## 3. `plan` output is reviewed for unexpected destroys/replacements

A reviewer (human or a policy-as-code gate) should look at the actual plan diff before
approving, specifically checking for unexpected `-`/`destroy` or `-/+`/`replace` actions on
resources that shouldn't be affected by the change - not just rubber-stamp approving because
CI is green.

**Flag:** a merged PR whose plan output included an unexplained destroy/replace of a resource
unrelated to the stated purpose of the change, with no comment addressing it.

## 4. Drift detection runs on a schedule, not only on demand

A scheduled pipeline (e.g., nightly) should run `terraform plan` against each environment and
alert if it detects drift (manual changes made outside Terraform), so drift is caught
proactively rather than discovered the next time someone happens to run a plan.

**Flag:** no scheduled drift-detection job anywhere in the repository's CI configuration for
environments Terraform is meant to be the source of truth for.

## 5. `terraform fmt` and `terraform validate` are enforced in CI

Every pipeline run should fail if code isn't formatted (`terraform fmt -check`) or doesn't
pass `terraform validate`, so basic issues are caught before a human reviewer's time is spent
on them.

**Flag:** a CI workflow with no `terraform fmt -check`/`terraform validate` step ahead of
`plan`.

## 6. Pipeline logs don't leak secrets

CI steps should not `echo`/print variables that may contain secrets, and step outputs that
could contain sensitive plan/apply data should be handled with the CI platform's secret
masking rather than assumed safe by default.

**Flag:** a pipeline step that echoes an environment variable, `terraform output`, or command
result that could contain a secret value without going through the platform's secret-masking
mechanism.
