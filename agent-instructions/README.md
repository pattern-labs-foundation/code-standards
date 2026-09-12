# Setup

Copy these into your repo. GitHub Copilot reads them automatically and applies the standards
when reviewing pull requests and when writing code.

| Copy this | To here |
|---|---|
| [`copilot-instructions.md`](./copilot-instructions.md) | `.github/copilot-instructions.md` |
| [`csharp.instructions.md`](./csharp.instructions.md) | `.github/instructions/csharp.instructions.md` |
| [`terraform.instructions.md`](./terraform.instructions.md) | `.github/instructions/terraform.instructions.md` |

Fill in the "Project context" section of `copilot-instructions.md` and drop whichever
language files don't apply.

The `.instructions.md` files are path-scoped through their `applyTo` front matter, so the C#
rules only fire on `**/*.cs` and the Terraform rules only on `**/*.tf`.

## Turn the review on

**Settings → Copilot → Code review →** tick **Automatically request Copilot code review**.

Copilot then reviews every new pull request against these standards and leaves inline
comments on the lines where it finds problems.

## Make it block merges

Copilot comments do not block a merge on their own. To require them to be dealt with:

**Settings → Rules → Rulesets →** your ruleset for `main`

- Set **Enforcement status** to **Active**, or none of the rules apply
- Tick **Require a pull request before merging**
- Tick **Require conversation resolution before merging**

Unresolved Copilot comments then block the merge.

## Migrating from the reusable workflow

Earlier versions shipped a reusable workflow that repos called with
`uses: pattern-labs-foundation/code-standards/.github/workflows/standards-review.yml@main`.
That workflow has been removed, so any repo still calling it will fail with a
"workflow not found" error.

To migrate, delete that caller workflow from your repo and follow the setup above instead.

## Keeping up to date

Re-copy the files when the standards here change. They are condensed checklists that change
rarely, so this is occasional rather than ongoing.

## Cost

Copilot code review draws on the account's premium request quota, including the free tier's
monthly allowance. Each push to a PR consumes another request if **Review new pushes** is on,
so turn that off if you hit the cap.
