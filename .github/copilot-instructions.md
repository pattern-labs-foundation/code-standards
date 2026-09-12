# Repository Custom Instructions

This repo holds coding standards that other repos enforce by calling
`.github/workflows/standards-review.yml` as a reusable workflow.

## When reviewing pull requests

**Check the documented tag is current.** Every merge into main creates a dated tag
(`YYYY-MM-DD-vN`, incrementing the suffix for repeat merges the same day). The docs show a
pinned tag in their setup examples, and it must match the tag this merge will create.

Check these three files:

- `README.md`
- `agent-instructions/README.md`
- `agent-instructions/caller-workflow.yml`

Flag the PR if:

- The tag in any of them is not today's date, since merging creates a tag dated today.
- The three files disagree with each other.
- A tag reference was changed in one file but not the others.
- Any example shows `@main` as the value rather than a pinned tag. `main` belongs only in the
  trailing `# or main for latest` comment, never as the thing people copy.

**Other things to flag:**

- Comments added to YAML or shell files. These stay comment-free; documentation belongs in
  the README.
- Em dashes anywhere. Use a plain hyphen, comma, or colon.
- A new rule added to `csharp/` or `terraform-azure/` with no matching check in `scripts/`,
  where the rule is mechanically checkable.
- A check added to `scripts/` that no standards file documents.
