#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
app_path="${1:-$project_root/dist/Eucrante.app}"
notary_profile="${APPLE_NOTARY_PROFILE:-}"

if [[ ! -d "$app_path" ]]; then
    echo "App bundle not found: $app_path"
    exit 1
fi

if [[ -z "$notary_profile" ]]; then
    echo "Set APPLE_NOTARY_PROFILE to a notarytool Keychain profile."
    echo "Create one with: xcrun notarytool store-credentials PROFILE_NAME"
    exit 1
fi

archive_path="$(mktemp -d)/Eucrante-notarization.zip"
ditto -c -k --keepParent "$app_path" "$archive_path"
xcrun notarytool submit "$archive_path" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
release_path="$project_root/dist/Eucrante-$version-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$release_path"
shasum -a 256 "$release_path" > "$release_path.sha256"

echo "Notarized release: $release_path"
