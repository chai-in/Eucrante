#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
core_minimum_percent="${1:-58}"
app_minimum_percent="${2:-16}"

command -v jq >/dev/null 2>&1 || {
  echo "Coverage verification requires jq." >&2
  exit 1
}

cd "$project_root"
swift test --enable-code-coverage -Xswiftc -warnings-as-errors
coverage_path="$(swift test --show-codecov-path)"

verify_target() {
  local target="$1"
  local minimum="$2"
  local covered total percent
  read -r covered total percent <<<"$(
    jq -r --arg path "/Sources/$target/" '
      [.data[0].files[]
        | select(.filename | contains($path))
        | .summary.lines]
      | [(map(.covered) | add // 0), (map(.count) | add // 0)]
      | . + [if .[1] > 0 then ((.[0] * 10000 / .[1] | floor) / 100) else 0 end]
      | @tsv
    ' "$coverage_path"
  )"

  awk -v actual="$percent" -v required="$minimum" \
    'BEGIN { exit(actual + 0 < required + 0) }' || {
    echo "$target line coverage $percent% is below the $minimum% floor." >&2
    exit 1
  }
  echo "$target line coverage: $percent% ($covered/$total), floor: $minimum%"
}

verify_target "EucranteCore" "$core_minimum_percent"
verify_target "EucranteApp" "$app_minimum_percent"
