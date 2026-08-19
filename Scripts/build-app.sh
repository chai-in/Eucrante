#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
configuration="${1:-release}"
app_name="Eucrante"
app_bundle="$project_root/dist/$app_name.app"
contents="$app_bundle/Contents"
entitlements="$project_root/App/Eucrante.entitlements"

if ! xcodebuild -version >/dev/null 2>&1; then
    echo "Full Xcode is required. Install Xcode, then select it with xcode-select."
    exit 1
fi

cd "$project_root"
"$project_root/Scripts/install-local-tools.sh"
swift_sandbox_args=()
if [[ "${EUCRANTE_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
    swift_sandbox_args+=(--disable-sandbox)
fi
swift_debug_args=()
if [[ "${EUCRANTE_SKIP_DEBUG_SYMBOLS:-0}" == "1" ]]; then
    swift_debug_args+=(-debug-info-format none)
fi
swift build "${swift_sandbox_args[@]}" "${swift_debug_args[@]}" --configuration "$configuration" --product "$app_name"
binary_directory="$(swift build "${swift_sandbox_args[@]}" "${swift_debug_args[@]}" --configuration "$configuration" --show-bin-path)"

rm -rf "$app_bundle"
mkdir -p "$contents/MacOS" "$contents/Resources"
ditto "$binary_directory/$app_name" "$contents/MacOS/$app_name"
ditto "$project_root/App/Info.plist" "$contents/Info.plist"
mkdir -p "$contents/Resources/Tools"
ditto "$project_root/.build/eucrante-tools/yt-dlp" "$contents/Resources/Tools/yt-dlp"
ditto "$project_root/.build/eucrante-tools/deno" "$contents/Resources/Tools/deno"
ditto "$project_root/.build/eucrante-tools/ffmpeg" "$contents/Resources/Tools/ffmpeg"
ditto "$project_root/ThirdParty" "$contents/Resources/Licenses"
mkdir -p "$contents/Resources/Licenses/ffmpeg"
ditto "$project_root/.build/eucrante-tools/ffmpeg-licenses" "$contents/Resources/Licenses/ffmpeg"
ditto "$project_root/THIRD_PARTY_NOTICES.md" "$contents/Resources/THIRD_PARTY_NOTICES.md"
"$project_root/Scripts/build-icon.sh" "$contents/Resources/Eucrante.icns"

signing_identity="${CODESIGN_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
    codesign --force --sign - "$contents/Resources/Tools/yt-dlp"
    codesign --force --sign - "$contents/Resources/Tools/deno"
    codesign --force --sign - "$contents/Resources/Tools/ffmpeg"
    codesign --force --sign - --entitlements "$entitlements" "$app_bundle"
else
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$contents/Resources/Tools/yt-dlp"
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$contents/Resources/Tools/deno"
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$contents/Resources/Tools/ffmpeg"
    codesign --force --options runtime --timestamp --entitlements "$entitlements" --sign "$signing_identity" "$app_bundle"
fi

"$project_root/Scripts/verify-app.sh" "$app_bundle"
codesign --display --entitlements - "$app_bundle"
echo "Built $app_bundle"
