# Setup

Copy the files you need into `.github/instructions/` in your repo:

- [`csharp.instructions.md`](./csharp.instructions.md) covers `**/*.cs`, `**/*.csproj`,
  `**/appsettings*.json`
- [`terraform.instructions.md`](./terraform.instructions.md) covers `**/*.tf`, `**/*.tfvars`

The `applyTo` front matter scopes each file, so C# rules never fire on Terraform and vice
versa.

Optionally copy [`copilot-instructions.md`](./copilot-instructions.md) to
`.github/copilot-instructions.md` for repo-wide guidance that applies to every file.

## Turn the review on

**Settings → Copilot → Code review →** tick **Automatically request Copilot code review**.

## Make findings block a merge

Copilot comments do not block on their own.

**Settings → Rules → Rulesets →** your `main` ruleset:

- Set **Enforcement status** to **Active**, or nothing applies
- Tick **Require a pull request before merging**
- Tick **Require conversation resolution before merging**

Unresolved Copilot comments then block the merge.

## Notes

Sync the files when the standards change here.

Reviews draw on the account's Copilot premium request quota. Each push to a PR costs another
request if **Review new pushes** is on.

Reduce every instructions file to under 1,000 lines. Copilot code review ignores rules past
that.

If a repo still calls the old reusable workflow
(`pattern-labs-foundation/code-standards/.github/workflows/standards-review.yml@main`), it has
been removed. Delete that workflow file and follow the setup above.
