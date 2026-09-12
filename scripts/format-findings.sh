#!/usr/bin/env bash

set -uo pipefail

FINDINGS="${1:?usage: format-findings.sh <findings-tsv> <output-md> <standards-url>}"
OUTPUT="${2:?missing output path}"
STANDARDS_URL="${3:-}"

block_count=0
warn_count=0
if [ -s "$FINDINGS" ]; then
    block_count=$(awk -F'\t' '$3 == "BLOCK"' "$FINDINGS" | wc -l | tr -d ' ')
    warn_count=$(awk -F'\t' '$3 == "WARN"' "$FINDINGS" | wc -l | tr -d ' ')
fi

table() {
    echo "| File | Line | Rule | Issue |"
    echo "|---|---|---|---|"
    awk -F'\t' -v sev="$1" '$3 == sev { printf "| `%s` | %s | `%s` | %s |\n", $1, $2, $4, $5 }' "$FINDINGS"
    echo
}

{
    echo "## Coding standards review"
    echo

    if [ "$block_count" -eq 0 ] && [ "$warn_count" -eq 0 ]; then
        echo "No standards violations found in the changed files."
        echo
    else
        echo "Found **${block_count} blocking** and **${warn_count} advisory** findings in the changed files."
        echo

        if [ "$block_count" -gt 0 ]; then
            echo "### Blocking"
            echo
            table BLOCK
        fi

        if [ "$warn_count" -gt 0 ]; then
            echo "### Advisory"
            echo
            table WARN
        fi
    fi

    echo "<sub>Checked against [the coding standards](${STANDARDS_URL}). Advisory findings do not fail the build. If a finding is a deliberate, documented exception, note why in the PR discussion.</sub>"
} > "$OUTPUT"

if [ "$block_count" -gt 0 ]; then
    exit 1
fi
exit 0
