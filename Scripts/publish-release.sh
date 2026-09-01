#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
mode="binary"
if [[ "${1:-}" == "--source-only" ]]; then
  mode="source"
  shift
elif [[ "${1:-}" == "--public-dmg" ]]; then
  mode="public-dmg"
  shift
fi
notes_file="${1:-}"

usage() {
  cat <<'USAGE'
Usage: ./Scripts/publish-release.sh [--source-only|--public-dmg] PATH_TO_RELEASE_NOTES.md

Creates a draft GitHub release from the exact pushed version tag. With
--source-only, GitHub supplies its generated source archives and no binary is
attached. With --public-dmg, it validates and attaches clearly labelled
unnotarized DMGs, checksums, and provenance to a prerelease draft. Binary mode
validates signed, notarized artifact sets in dist/. The script never publishes.
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
if [[ "$mode" == "public-dmg" ]]; then
  disk_images=("$project_root"/dist/Eucrante-"$version"-"$build"-macOS-*-unnotarized.dmg(N))
  (( ${#disk_images} > 0 )) \
    || fail "no architecture-labelled unnotarized public DMGs were found in dist/"
  archives=("${disk_images[@]}")
elif [[ "$mode" == "binary" ]]; then
  disk_images=("$project_root"/dist/Eucrante-"$version"-"$build"-macOS-*.dmg(N))
  disk_images=("${(@)disk_images:#*-unnotarized.dmg}")
  (( ${#disk_images} > 0 )) \
    || fail "no architecture-labelled release DMGs were found in dist/"

  archives=()
  for disk_image in "${disk_images[@]}"; do
    portable_archive="${disk_image:r}.zip"
    [[ -f "$portable_archive" ]] \
      || fail "portable ZIP is missing for ${disk_image:t}"
    archives+=("$disk_image" "$portable_archive")
  done

fi

if [[ "$mode" == "binary" || "$mode" == "public-dmg" ]]; then
  head_commit="$(git -C "$project_root" rev-parse HEAD)"
  for archive in "${archives[@]}"; do
    checksum="$archive.sha256"
    provenance="$archive.provenance.json"
    [[ -f "$checksum" ]] || fail "checksum is missing: ${checksum:t}"
    [[ -f "$provenance" ]] || fail "provenance is missing: ${provenance:t}"

    (
      cd "$project_root/dist"
      shasum -a 256 -c "${checksum:t}"
    )

    archive_hash="$(shasum -a 256 "$archive" | awk '{print $1}')"
    if [[ "$archive" == *.dmg ]]; then
      codesign --verify --strict --verbose=2 "$archive"
      hdiutil imageinfo "$archive" >/dev/null
    fi
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
    notarization_status="$(plutil -extract notarization.status raw "$provenance")"
    signing_status="$(plutil -extract signing.status raw "$provenance")"
    if [[ "$mode" == "public-dmg" ]]; then
      [[ "$notarization_status" == "not-notarized" && "$signing_status" == "ad-hoc" ]] \
        || fail "public DMG provenance must declare ad-hoc signing and no notarization: ${provenance:t}"
    else
      [[ "$notarization_status" == "accepted-and-stapled" && "$signing_status" == "developer-id" ]] \
        || fail "provenance does not confirm Developer ID signing and stapled notarization: ${provenance:t}"
    fi
    assets+=("$archive" "$checksum" "$provenance")
  done
fi

if gh release view "$expected_tag" >/dev/null 2>&1; then
  fail "a GitHub release already exists for $expected_tag"
fi

release_notes="$notes_file"
release_kind_args=()
release_title="Eucrante $version"
if [[ "$mode" == "public-dmg" ]]; then
  generated_notes="$(mktemp "${TMPDIR:-/tmp}/eucrante-release-notes.XXXXXX")"
  trap 'rm -f "$generated_notes"' EXIT
  {
    print '# Unnotarized macOS preview'
    print
    print 'This DMG is ad-hoc signed but not notarized because the maintainer currently uses a free Apple developer account. macOS will block the first launch.'
    print
    print 'Install: drag Eucrante to Applications, try to open it once, then open System Settings > Privacy & Security and click Open Anyway. Confirm Open when macOS asks. Never disable Gatekeeper and never run a command that removes quarantine attributes.'
    print
    print 'Verify the downloaded DMG with its attached `.sha256` file before opening it.'
    print
    print '---'
    print
    cat "$notes_file"
  } > "$generated_notes"
  release_notes="$generated_notes"
  release_kind_args+=(--prerelease)
  release_title="Eucrante $version Preview"
fi

release_url="$(
  gh release create "$expected_tag" \
    "${assets[@]}" \
    --draft \
    "${release_kind_args[@]}" \
    --verify-tag \
    --title "$release_title" \
    --notes-file "$release_notes"
)"

echo "Created draft release: $release_url"
if [[ "$mode" == "source" ]]; then
  echo "Review the generated source archives and rendered notes before publishing."
else
  echo "Review every asset and the rendered notes on GitHub before publishing."
fi
