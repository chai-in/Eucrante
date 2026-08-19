#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
mode="binary"
if [[ "${1:-}" == "--source-only" ]]; then
  mode="source"
  shift
fi
notes_file="${1:-}"

usage() {
  cat <<'USAGE'
Usage: ./Scripts/publish-release.sh [--source-only] PATH_TO_RELEASE_NOTES.md

Creates a draft GitHub release from the exact pushed version tag. With
--source-only, GitHub supplies its generated source archives and no binary is
attached. Binary mode validates and attaches every signed, notarized artifact
set in dist/. The script never publishes a release.
USAGE
}

fail() {
  echo "Publish failed: $1" >&2
  exit 1
}

if [[ "$notes_file" == "-h" || "$notes_file" == "--help" ]]; then
  usage
  exit 0
fi

[[ -n "$notes_file" ]] || {
  usage >&2
  exit 2
}
[[ -s "$notes_file" ]] || fail "release notes are missing or empty: $notes_file"
command -v gh >/dev/null 2>&1 || fail "GitHub CLI is required: https://cli.github.com/"
gh auth status --hostname github.com >/dev/null 2>&1 \
  || fail "GitHub CLI is not authenticated; run: gh auth login"

info_plist="$project_root/App/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
expected_tag="v$version"
actual_tag="$(git -C "$project_root" describe --exact-match --tags HEAD 2>/dev/null || true)"

[[ -z "$(git -C "$project_root" status --porcelain)" ]] \
  || fail "the Git worktree must be clean"
[[ "$actual_tag" == "$expected_tag" ]] \
  || fail "HEAD must have the exact release tag $expected_tag"
git -C "$project_root" ls-remote --exit-code --tags origin "refs/tags/$expected_tag" \
  >/dev/null 2>&1 || fail "push the exact tag $expected_tag to origin first"

setopt local_options null_glob
assets=()
if [[ "$mode" == "binary" ]]; then
  archives=("$project_root"/dist/Eucrante-"$version"-"$build"-macOS-*.zip(N))
  (( ${#archives} > 0 )) \
    || fail "no architecture-labelled release archives were found in dist/"

  head_commit="$(git -C "$project_root" rev-parse HEAD)"
  for archive in "${archives[@]}"; do
    checksum="$archive.sha256"
    provenance="${archive:r}.provenance.json"
    [[ -f "$checksum" ]] || fail "checksum is missing: ${checksum:t}"
    [[ -f "$provenance" ]] || fail "provenance is missing: ${provenance:t}"

    (
      cd "$project_root/dist"
      shasum -a 256 -c "${checksum:t}"
    )

    archive_hash="$(shasum -a 256 "$archive" | awk '{print $1}')"
    [[ "$(plutil -extract gitTag raw "$provenance")" == "$expected_tag" ]] \
      || fail "provenance tag does not match $expected_tag: ${provenance:t}"
    [[ "$(plutil -extract gitCommit raw "$provenance")" == "$head_commit" ]] \
      || fail "provenance commit does not match HEAD: ${provenance:t}"
    [[ "$(plutil -extract archive.name raw "$provenance")" == "${archive:t}" ]] \
      || fail "provenance archive name does not match: ${provenance:t}"
    [[ "$(plutil -extract archive.sha256 raw "$provenance")" == "$archive_hash" ]] \
      || fail "provenance archive hash does not match: ${provenance:t}"
    [[ "$(plutil -extract archive.bytes raw "$provenance")" == "$(stat -f '%z' "$archive")" ]] \
      || fail "provenance archive size does not match: ${provenance:t}"
    [[ "$(plutil -extract notarization.status raw "$provenance")" == "accepted-and-stapled" ]] \
      || fail "provenance does not confirm accepted and stapled notarization: ${provenance:t}"
    assets+=("$archive" "$checksum" "$provenance")
  done
fi

if gh release view "$expected_tag" >/dev/null 2>&1; then
  fail "a GitHub release already exists for $expected_tag"
fi

release_url="$(
  gh release create "$expected_tag" \
    "${assets[@]}" \
    --draft \
    --verify-tag \
    --title "Eucrante $version" \
    --notes-file "$notes_file"
)"

echo "Created draft release: $release_url"
if [[ "$mode" == "source" ]]; then
  echo "Review the generated source archives and rendered notes before publishing."
else
  echo "Review every asset and the rendered notes on GitHub before publishing."
fi
