# Repository Custom Instructions

This repo holds coding standards that other repos adopt by copying the files in
`agent-instructions/` into their own `.github/instructions/`.

Each `.instructions.md` file is the standard itself, so a rule lives in exactly one place.

## When reviewing pull requests

Flag:

- A rule without a rationale, a `Bad`/`Good` example, and a clear "flag when" condition.
- A change to a rule's `applyTo` scope that the setup docs still describe the old way.
- Comments added to YAML or shell files. Documentation belongs in the README.
- Em dashes anywhere. Use a plain hyphen, comma, or colon.
- Setup instructions that say to copy the files without also saying to enable Copilot code
  review, since copying alone does nothing.
- A README that has grown into an essay. Keep them short and instructional.
