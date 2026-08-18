#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
configuration="${1:-release}"
app_name="Eucrante"
app_bundle="$project_root/dist/$app_name.app"
contents="$app_bundle/Contents"

if ! xcodebuild -version >/dev/null 2>&1; then
    echo "Full Xcode is required. Install Xcode, then select it with xcode-select."
    exit 1
fi

cd "$project_root"
swift build --configuration "$configuration" --product "$app_name"
binary_directory="$(swift build --configuration "$configuration" --show-bin-path)"

rm -rf "$app_bundle"
mkdir -p "$contents/MacOS" "$contents/Resources"
ditto "$binary_directory/$app_name" "$contents/MacOS/$app_name"
ditto "$project_root/App/Info.plist" "$contents/Info.plist"

signing_identity="${CODESIGN_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
    codesign --force --sign - "$app_bundle"
else
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$app_bundle"
fi

codesign --verify --deep --strict --verbose=2 "$app_bundle"
echo "Built $app_bundle"
