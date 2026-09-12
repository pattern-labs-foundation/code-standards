#!/usr/bin/env bash
# Usage: post-review.sh <findings-tsv> <base-sha> <head-sha> <repo> <pr-number>
# Posts findings as inline review comments on the lines they occur on.

set -uo pipefail

FINDINGS="${1:?findings tsv}"
BASE="${2:?base sha}"
HEAD="${3:?head sha}"
REPO="${4:?owner/repo}"
PR="${5:?pr number}"

[ -s "$FINDINGS" ] || exit 0

git diff -U0 "$BASE" "$HEAD" |
  awk '
    /^\+\+\+ b\// { file = substr($0, 7); next }
    /^@@/ {
      match($0, /\+[0-9]+(,[0-9]+)?/)
      spec = substr($0, RSTART + 1, RLENGTH - 1)
      split(spec, a, ",")
      start = a[1]
      count = (a[2] == "" ? 1 : a[2])
      for (i = 0; i < count; i++) print file ":" (start + i)
    }
  ' | sort -u > diff-lines.txt

: > comments.json
: > leftover.tsv

while IFS=$'\t' read -r file line severity rule message fix; do
  [ -z "${file:-}" ] && continue

  if ! grep -qxF "${file}:${line}" diff-lines.txt; then
    printf '%s\t%s\t%s\t%s\t%s\n' "$file" "$line" "$severity" "$rule" "$message" >> leftover.tsv
    continue
  fi

  body="**${severity}** \`${rule}\`

${message}"

  if [ -n "${fix:-}" ]; then
    original=$(sed -n "${line}p" "$file")
    suggested=$(printf '%s' "$original" | sed -E "$fix")
    if [ -n "$suggested" ] && [ "$suggested" != "$original" ]; then
      body="${body}

\`\`\`suggestion
${suggested}
\`\`\`"
    fi
  fi

  jq -n --arg path "$file" --argjson line "$line" --arg body "$body" \
    '{path: $path, line: $line, side: "RIGHT", body: $body}' >> comments.json
done < "$FINDINGS"

if [ -s comments.json ]; then
  COUNT=$(jq -s 'length' comments.json)
  jq -s --arg event "COMMENT" \
    '{event: $event, comments: .}' comments.json > review.json

  gh api "repos/${REPO}/pulls/${PR}/reviews" --input review.json > /dev/null
  echo "Posted $COUNT inline comments"
fi

if [ -s leftover.tsv ]; then
  {
    echo "### Findings outside this diff"
    echo
    echo "| File | Line | Rule | Issue |"
    echo "|---|---|---|---|"
    awk -F'\t' '{ printf "| `%s` | %s | `%s` | %s |\n", $1, $2, $4, $5 }' leftover.tsv
  } > leftover.md
  gh pr comment "$PR" --repo "$REPO" --body-file leftover.md > /dev/null
  echo "Posted $(wc -l < leftover.tsv) findings outside the diff as a summary"
fi
