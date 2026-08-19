#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
app_path="${1:-$project_root/dist/Eucrante.app}"
contents="$app_path/Contents"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/eucrante-verify.XXXXXX")"
trap 'find "$temporary_directory" -depth -delete 2>/dev/null || true' EXIT

fail() {
  echo "App verification failed: $1" >&2
  exit 1
}

[[ -d "$app_path" ]] || fail "bundle does not exist at $app_path"

required_files=(
  "$contents/Info.plist"
  "$contents/MacOS/Eucrante"
  "$contents/Resources/Tools/yt-dlp"
  "$contents/Resources/Tools/deno"
  "$contents/Resources/Tools/ffmpeg"
  "$contents/Resources/Eucrante.icns"
  "$contents/Resources/Licenses/yt-dlp/LICENSE"
  "$contents/Resources/Licenses/deno/LICENSE.md"
  "$contents/Resources/Licenses/ffmpeg/COPYING.LGPLv2.1"
  "$contents/Resources/THIRD_PARTY_NOTICES.md"
)

for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || fail "required file is missing: ${file#$app_path/}"
done

plutil -lint "$contents/Info.plist" >/dev/null
identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$contents/Info.plist")"
[[ "$identifier" == "app.eucrante.client" ]] || fail "unexpected bundle identifier: $identifier"
minimum_system="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$contents/Info.plist")"
[[ "$minimum_system" == "14.0" ]] || fail "unexpected minimum macOS version: $minimum_system"
icon_file="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$contents/Info.plist")"
[[ "$icon_file" == "Eucrante.icns" ]] || fail "unexpected app icon declaration: $icon_file"

for executable in \
  "$contents/Resources/Tools/yt-dlp" \
  "$contents/Resources/Tools/deno" \
  "$contents/Resources/Tools/ffmpeg"; do
  [[ -x "$executable" ]] || fail "tool is not executable: ${executable:t}"
  codesign --verify --strict --verbose=2 "$executable"
  signature_details="$(codesign --display --verbose=4 "$executable" 2>&1)"
  [[ "$signature_details" == *"flags="*"runtime"* ]] \
    || fail "Hardened Runtime is missing from ${executable:t}"
done
codesign --verify --deep --strict --verbose=2 "$app_path"
signature_details="$(codesign --display --verbose=4 "$app_path" 2>&1)"
[[ "$signature_details" == *"flags="*"runtime"* ]] \
  || fail "Hardened Runtime is missing from the app"

deno_entitlements="$temporary_directory/deno-entitlements.plist"
codesign --display --entitlements :- "$contents/Resources/Tools/deno" \
  > "$deno_entitlements" 2>/dev/null
plutil -lint "$deno_entitlements" >/dev/null
deno_allows_jit="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.cs.allow-jit' "$deno_entitlements" 2>/dev/null || true)"
[[ "$deno_allows_jit" == "true" ]] || fail "Deno is missing its required JIT entitlement"
/usr/libexec/PlistBuddy -c 'Delete :com.apple.security.cs.allow-jit' "$deno_entitlements"
[[ "$(/usr/libexec/PlistBuddy -c Print "$deno_entitlements")" == $'Dict {\n}' ]] \
  || fail "Deno has an unexpected additional entitlement"
"$contents/Resources/Tools/deno" eval 'if (6 * 7 !== 42) Deno.exit(1)' >/dev/null \
  || fail "Deno could not execute JavaScript under Hardened Runtime"

yt_dlp_entitlements="$temporary_directory/yt-dlp-entitlements.plist"
codesign --display --entitlements :- "$contents/Resources/Tools/yt-dlp" \
  > "$yt_dlp_entitlements" 2>/dev/null
plutil -lint "$yt_dlp_entitlements" >/dev/null
yt_dlp_allows_extracted_python="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.cs.disable-library-validation' "$yt_dlp_entitlements" 2>/dev/null || true)"
[[ "$yt_dlp_allows_extracted_python" == "true" ]] \
  || fail "yt-dlp is missing its required extracted-runtime entitlement"
/usr/libexec/PlistBuddy -c 'Delete :com.apple.security.cs.disable-library-validation' "$yt_dlp_entitlements"
[[ "$(/usr/libexec/PlistBuddy -c Print "$yt_dlp_entitlements")" == $'Dict {\n}' ]] \
  || fail "yt-dlp has an unexpected additional entitlement"
"$contents/Resources/Tools/yt-dlp" --version >/dev/null \
  || fail "yt-dlp could not launch its extracted Python runtime under Hardened Runtime"

ffmpeg_entitlements="$temporary_directory/ffmpeg-entitlements.plist"
codesign --display --entitlements :- "$contents/Resources/Tools/ffmpeg" \
  > "$ffmpeg_entitlements" 2>/dev/null
[[ ! -s "$ffmpeg_entitlements" ]] || fail "FFmpeg has unexpected entitlements"

app_entitlements="$temporary_directory/app-entitlements.plist"
codesign --display --entitlements :- "$app_path" > "$app_entitlements" 2>/dev/null
plutil -lint "$app_entitlements" >/dev/null
app_allows_music_automation="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.automation.apple-events' "$app_entitlements" 2>/dev/null || true)"
[[ "$app_allows_music_automation" == "true" ]] \
  || fail "the app is missing its required Music automation entitlement"
/usr/libexec/PlistBuddy -c 'Delete :com.apple.security.automation.apple-events' "$app_entitlements"
[[ "$(/usr/libexec/PlistBuddy -c Print "$app_entitlements")" == $'Dict {\n}' ]] \
  || fail "the app has an unexpected additional entitlement"

app_executable="$contents/MacOS/Eucrante"
app_architectures="$(lipo -archs "$app_executable")"
[[ -n "$app_architectures" ]] || fail "app executable has no reported architecture"
for architecture in ${(z)app_architectures}; do
  for executable in \
    "$contents/Resources/Tools/yt-dlp" \
    "$contents/Resources/Tools/deno" \
    "$contents/Resources/Tools/ffmpeg"; do
    lipo "$executable" -verify_arch "$architecture" >/dev/null \
      || fail "${executable:t} does not support app architecture $architecture"
  done
done

ffmpeg_version="$($contents/Resources/Tools/ffmpeg -version 2>&1)"
[[ "$ffmpeg_version" == *"ffmpeg version 9.0.1"* ]] || fail "unexpected FFmpeg version"
[[ "$ffmpeg_version" == *"--disable-network"* ]] || fail "FFmpeg networking is enabled"
[[ "$ffmpeg_version" == *"--disable-gpl"* ]] || fail "FFmpeg GPL mode is enabled"
[[ "$ffmpeg_version" == *"--disable-nonfree"* ]] || fail "FFmpeg non-free mode is enabled"
ffmpeg_decoders="$($contents/Resources/Tools/ffmpeg -decoders 2>&1)"
[[ "$ffmpeg_decoders" == *" vp9 "* ]] || fail "FFmpeg VP9 decoder is missing"
ffmpeg_encoders="$($contents/Resources/Tools/ffmpeg -encoders 2>&1)"
[[ "$ffmpeg_encoders" == *" hevc_videotoolbox "* ]] \
  || fail "FFmpeg VideoToolbox HEVC encoder is missing"

if find "$app_path" -name '.DS_Store' -o -name '.eucrante-youtube-cookies.txt' | grep -q .; then
  fail "bundle contains a forbidden transient file"
fi

echo "Verified signed Eucrante app bundle ($app_architectures): $app_path"
