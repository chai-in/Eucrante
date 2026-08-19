#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
minimum_percent="${1:-37}"

command -v jq >/dev/null 2>&1 || {
  echo "Coverage verification requires jq." >&2
  exit 1
}

cd "$project_root"
swift test --enable-code-coverage -Xswiftc -warnings-as-errors
coverage_path="$(swift test --show-codecov-path)"

read -r covered total percent <<<"$(
  jq -r '
    [.data[0].files[]
      | select(.filename | contains("/Sources/EucranteCore/"))
      | .summary.lines]
    | [(map(.covered) | add), (map(.count) | add)]
    | . + [((.[0] * 10000 / .[1] | floor) / 100)]
    | @tsv
  ' "$coverage_path"
)"

awk -v actual="$percent" -v minimum="$minimum_percent" 'BEGIN { exit(actual + 0 < minimum + 0) }' \
  || {
    echo "EucranteCore line coverage $percent% is below the $minimum_percent% floor." >&2
    exit 1
  }

echo "EucranteCore line coverage: $percent% ($covered/$total), floor: $minimum_percent%"
