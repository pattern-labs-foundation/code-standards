# Repository Custom Instructions

This repo holds coding standards that other repos adopt by copying the files in
`agent-instructions/` into their own `.github/` directory.

## When reviewing pull requests

**Keep the three layers in sync.** A standard exists in three places, and a change to one
usually needs the others:

- `csharp/NN-*.md` or `terraform-azure/NN-*.md` is the full rule with rationale and examples
- the matching `REVIEW-CHECKLIST.md` is the condensed reviewer-facing version
- `agent-instructions/csharp.instructions.md` or `terraform.instructions.md` is what
  consumers actually copy

Flag a PR that adds or changes a rule in one of these without updating the others.

**Other things to flag:**

- Comments added to YAML or shell files. These stay comment-free, documentation belongs in
  the README.
- Em dashes anywhere. Use a plain hyphen, comma, or colon.
- A standard phrased so a reviewer cannot act on it. Each needs a rationale, a `Bad`/`Good`
  example, and a clear "flag when" condition.
- Setup instructions that tell people to copy the instruction files without also telling them
  to enable Copilot code review, since copying alone does nothing.
