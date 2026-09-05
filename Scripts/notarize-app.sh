#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
app_path="${1:-$project_root/dist/Eucrante.app}"
notary_profile="${APPLE_NOTARY_PROFILE:-}"

fail() {
    echo "Release failed: $1" >&2
    exit 1
}

if [[ ! -d "$app_path" ]]; then
    fail "app bundle not found: $app_path"
fi

if [[ -z "$notary_profile" ]]; then
    echo "Set APPLE_NOTARY_PROFILE to a notarytool Keychain profile."
    echo "Create one with: xcrun notarytool store-credentials PROFILE_NAME"
    exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")"
expected_tag="v$version"
actual_tag="$(git -C "$project_root" describe --exact-match --tags HEAD 2>/dev/null || true)"
[[ -z "$(git -C "$project_root" status --porcelain)" ]] \
    || fail "the Git worktree must be clean"
[[ "$actual_tag" == "$expected_tag" ]] \
    || fail "HEAD must have the exact release tag $expected_tag"

signature="$(codesign --display --verbose=4 "$app_path" 2>&1)"
[[ "$signature" == *"Authority=Developer ID Application:"* ]] \
    || fail "the app is not signed with a Developer ID Application identity"
"$project_root/Scripts/verify-app.sh" "$app_path"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/eucrante-notarize.XXXXXX")"
trap 'find "$temporary_directory" -depth -delete 2>/dev/null || true' EXIT
archive_path="$temporary_directory/Eucrante-notarization.zip"
notary_result="$temporary_directory/notary-result.json"
ditto -c -k --keepParent "$app_path" "$archive_path"
xcrun notarytool submit "$archive_path" \
    --keychain-profile "$notary_profile" \
    --wait \
    --output-format json > "$notary_result"
notary_status="$(plutil -extract status raw "$notary_result")"
notary_request_id="$(plutil -extract id raw "$notary_result")"
[[ "$notary_status" == "Accepted" ]] || fail "Apple notarization was not accepted"
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"

app_architectures="$(lipo -archs "$app_path/Contents/MacOS/Eucrante")"
architecture_tag="${app_architectures// /-}"
release_name="Eucrante-$version-$build-macOS-$architecture_tag.zip"
release_path="$project_root/dist/$release_name"
[[ ! -e "$release_path" && ! -e "$release_path.sha256" \
    && ! -e "$release_path.provenance.json" ]] \
    || fail "release artifact already exists: $release_name"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$release_path"
release_sha256="$(shasum -a 256 "$release_path" | awk '{print $1}')"
printf '%s  %s\n' "$release_sha256" "$release_name" > "$release_path.sha256"

provenance_path="$release_path.provenance.json"
plutil -create xml1 "$provenance_path"
plutil -insert schemaVersion -integer 1 "$provenance_path"
plutil -insert appVersion -string "$version" "$provenance_path"
plutil -insert bundleVersion -string "$build" "$provenance_path"
plutil -insert gitTag -string "$actual_tag" "$provenance_path"
plutil -insert gitCommit -string "$(git -C "$project_root" rev-parse HEAD)" "$provenance_path"
plutil -insert architectures -string "$app_architectures" "$provenance_path"
plutil -insert minimumMacOS -string \
    "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app_path/Contents/Info.plist")" \
    "$provenance_path"
plutil -insert archive -dictionary "$provenance_path"
plutil -insert archive.name -string "$release_name" "$provenance_path"
plutil -insert archive.sha256 -string "$release_sha256" "$provenance_path"
plutil -insert archive.bytes -integer "$(stat -f '%z' "$release_path")" "$provenance_path"
plutil -insert notarization -dictionary "$provenance_path"
plutil -insert notarization.status -string "accepted-and-stapled" "$provenance_path"
plutil -insert notarization.requestID -string "$notary_request_id" "$provenance_path"
plutil -insert tools -dictionary "$provenance_path"
for tool in yt-dlp deno ffmpeg; do
    tool_path="$app_path/Contents/Resources/Tools/$tool"
    if [[ "$tool" == "yt-dlp" ]]; then tool_path="$app_path/Contents/Resources/Tools/downloader/yt-dlp"; fi
    digest="$(shasum -a 256 "$tool_path" | awk '{print $1}')"
    plutil -insert "tools.$tool" -string "$digest" "$provenance_path"
done
downloader_digest="$(python3 "$project_root/Scripts/prepare-downloader.py" fingerprint \
    "$app_path/Contents/Resources/Tools/downloader")"
plutil -insert tools.downloaderPayload -string "$downloader_digest" "$provenance_path"
plutil -convert json "$provenance_path"

"$project_root/Scripts/create-dmg.sh" release "$app_path"

echo "Notarized release: $release_path"
echo "Checksum: $release_path.sha256"
echo "Provenance: $provenance_path"
