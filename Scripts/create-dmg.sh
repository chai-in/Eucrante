#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
mode="${1:-development}"
app_path="${2:-$project_root/dist/Eucrante.app}"
volume_name="Eucrante"

fail() {
  echo "DMG creation failed: $1" >&2
  exit 1
}

[[ "$mode" == "development" || "$mode" == "release" ]] \
  || fail "mode must be development or release"
[[ -d "$app_path" ]] || fail "app bundle not found: $app_path"

"$project_root/Scripts/verify-app.sh" "$app_path"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")"
app_architectures="$(lipo -archs "$app_path/Contents/MacOS/Eucrante")"
architecture_tag="${app_architectures// /-}"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/eucrante-dmg.XXXXXX")"
mounted_device=""
cleanup() {
  if [[ -n "$mounted_device" ]]; then
    hdiutil detach "$mounted_device" -force >/dev/null 2>&1 || true
  fi
  find "$temporary_directory" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

staging_directory="$temporary_directory/staging"
read_write_image="$temporary_directory/Eucrante-rw.dmg"
mkdir -p "$staging_directory/.background"
ditto "$app_path" "$staging_directory/Eucrante.app"
ln -s /Applications "$staging_directory/Applications"
ditto "$app_path/Contents/Resources/Eucrante.icns" "$staging_directory/.VolumeIcon.icns"
swift "$project_root/Scripts/render-dmg-background.swift" \
  "$staging_directory/.background/background.png"
xcrun SetFile -a V "$staging_directory/.background" "$staging_directory/.VolumeIcon.icns"

hdiutil create \
  -volname "$volume_name" \
  -srcfolder "$staging_directory" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$read_write_image" >/dev/null
attach_result="$temporary_directory/attach.plist"
hdiutil attach "$read_write_image" \
  -plist \
  -readwrite \
  -noverify \
  -noautoopen > "$attach_result"
mount_directory=""
for index in {0..8}; do
  candidate_mount="$(
    /usr/libexec/PlistBuddy -c "Print :system-entities:$index:mount-point" \
      "$attach_result" 2>/dev/null || true
  )"
  if [[ -n "$candidate_mount" ]]; then
    mount_directory="$candidate_mount"
    mounted_device="$(
      /usr/libexec/PlistBuddy -c "Print :system-entities:$index:dev-entry" \
        "$attach_result" 2>/dev/null || true
    )"
    break
  fi
done
[[ -n "$mount_directory" && -n "$mounted_device" ]] \
  || fail "could not locate the mounted DMG volume"
xcrun SetFile -a C "$mount_directory"

osascript - "$mount_directory" "$volume_name" <<'APPLESCRIPT'
on run arguments
  set mountPath to item 1 of arguments
  set volumeName to item 2 of arguments
  set backgroundFile to POSIX file (mountPath & "/.background/background.png") as alias
  tell application "Finder"
    set diskWindow to container window of disk volumeName
    open diskWindow
    set current view of diskWindow to icon view
    set toolbar visible of diskWindow to false
    set statusbar visible of diskWindow to false
    set pathbar visible of diskWindow to false
    set bounds of diskWindow to {120, 120, 800, 540}
    set viewOptions to icon view options of diskWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 104
    set text size of viewOptions to 13
    set background picture of viewOptions to backgroundFile
    set position of item "Eucrante.app" of diskWindow to {170, 215}
    set position of item "Applications" of diskWindow to {510, 215}
    delay 2
    close diskWindow
  end tell
end run
APPLESCRIPT

sync
hdiutil detach "$mounted_device" >/dev/null
mounted_device=""

if [[ "$mode" == "development" ]]; then
  output_directory="$project_root/dist/development"
  output_name="Eucrante-$version-$build-macOS-$architecture_tag-development.dmg"
else
  output_directory="$project_root/dist"
  output_name="Eucrante-$version-$build-macOS-$architecture_tag.dmg"
fi
mkdir -p "$output_directory"
output_path="$output_directory/$output_name"
[[ ! -e "$output_path" && ! -e "$output_path.sha256" \
  && ! -e "$output_path.provenance.json" ]] \
  || fail "DMG release artifact already exists: $output_name"

final_output_path="$output_path"
if [[ "$mode" == "release" ]]; then
  output_path="$temporary_directory/$output_name"
fi

hdiutil convert "$read_write_image" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$output_path" >/dev/null

if [[ "$mode" == "development" ]]; then
  codesign --force --sign - "$output_path"
else
  notary_profile="${APPLE_NOTARY_PROFILE:-}"
  [[ -n "$notary_profile" ]] \
    || fail "APPLE_NOTARY_PROFILE must name a notarytool Keychain profile"
  signature="$(codesign --display --verbose=4 "$app_path" 2>&1)"
  [[ "$signature" == *"Authority=Developer ID Application:"* ]] \
    || fail "the app is not signed with a Developer ID Application identity"
  signing_identity="$(
    print -r -- "$signature" \
      | sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p' \
      | head -n 1
  )"
  [[ -n "$signing_identity" ]] \
    || fail "could not read the app's Developer ID Application identity"
  xcrun stapler validate "$app_path"
  spctl --assess --type execute --verbose=2 "$app_path"
  codesign --force --timestamp --sign "$signing_identity" "$output_path"
  codesign --verify --strict --verbose=2 "$output_path"

  notary_result="$temporary_directory/dmg-notary-result.json"
  xcrun notarytool submit "$output_path" \
    --keychain-profile "$notary_profile" \
    --wait \
    --output-format json > "$notary_result"
  notary_status="$(plutil -extract status raw "$notary_result")"
  notary_request_id="$(plutil -extract id raw "$notary_result")"
  [[ "$notary_status" == "Accepted" ]] || fail "Apple did not accept the DMG"
  xcrun stapler staple "$output_path"
  xcrun stapler validate "$output_path"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$output_path"

  checksum_path="$output_path.sha256"
  output_sha256="$(shasum -a 256 "$output_path" | awk '{print $1}')"
  printf '%s  %s\n' "$output_sha256" "$output_name" > "$checksum_path"

  provenance_path="$output_path.provenance.json"
  plutil -create xml1 "$provenance_path"
  plutil -insert schemaVersion -integer 1 "$provenance_path"
  plutil -insert appVersion -string "$version" "$provenance_path"
  plutil -insert bundleVersion -string "$build" "$provenance_path"
  plutil -insert gitTag -string "$(git -C "$project_root" describe --exact-match --tags HEAD)" "$provenance_path"
  plutil -insert gitCommit -string "$(git -C "$project_root" rev-parse HEAD)" "$provenance_path"
  plutil -insert architectures -string "$app_architectures" "$provenance_path"
  plutil -insert minimumMacOS -string \
    "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app_path/Contents/Info.plist")" \
    "$provenance_path"
  plutil -insert archive -dictionary "$provenance_path"
  plutil -insert archive.name -string "$output_name" "$provenance_path"
  plutil -insert archive.sha256 -string "$output_sha256" "$provenance_path"
  plutil -insert archive.bytes -integer "$(stat -f '%z' "$output_path")" "$provenance_path"
  plutil -insert notarization -dictionary "$provenance_path"
  plutil -insert notarization.status -string "accepted-and-stapled" "$provenance_path"
  plutil -insert notarization.requestID -string "$notary_request_id" "$provenance_path"
  plutil -insert tools -dictionary "$provenance_path"
  for tool in yt-dlp deno ffmpeg; do
    digest="$(shasum -a 256 "$app_path/Contents/Resources/Tools/$tool" | awk '{print $1}')"
    plutil -insert "tools.$tool" -string "$digest" "$provenance_path"
  done
  plutil -convert json "$provenance_path"

  mv "$output_path" "$final_output_path"
  mv "$checksum_path" "$final_output_path.sha256"
  mv "$provenance_path" "$final_output_path.provenance.json"
  output_path="$final_output_path"
fi

codesign --verify --strict --verbose=2 "$output_path"
hdiutil imageinfo "$output_path" >/dev/null

verification_mount="$temporary_directory/verification-mount"
mkdir -p "$verification_mount"
verification_attach="$(
  hdiutil attach "$output_path" \
    -readonly \
    -nobrowse \
    -noverify \
    -mountpoint "$verification_mount"
)"
mounted_device="$(print -r -- "$verification_attach" | awk 'NR == 1 {print $1}')"
[[ -n "$mounted_device" ]] || fail "could not attach the finished DMG"
[[ -d "$verification_mount/Eucrante.app" ]] || fail "DMG does not contain Eucrante.app"
[[ -L "$verification_mount/Applications" ]] \
  || fail "DMG does not contain the Applications shortcut"
[[ "$(readlink "$verification_mount/Applications")" == "/Applications" ]] \
  || fail "DMG Applications shortcut has the wrong destination"
codesign --verify --deep --strict --verbose=2 "$verification_mount/Eucrante.app"
hdiutil detach "$mounted_device" >/dev/null
mounted_device=""
echo "Created DMG: $output_path"
