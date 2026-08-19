#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
app_path="${1:-$project_root/dist/Eucrante.app}"
contents="$app_path/Contents"

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
done
codesign --verify --deep --strict --verbose=2 "$app_path"

ffmpeg_version="$($contents/Resources/Tools/ffmpeg -version 2>&1)"
[[ "$ffmpeg_version" == *"ffmpeg version 9.0.1"* ]] || fail "unexpected FFmpeg version"
[[ "$ffmpeg_version" == *"--disable-network"* ]] || fail "FFmpeg networking is enabled"
[[ "$ffmpeg_version" == *"--disable-gpl"* ]] || fail "FFmpeg GPL mode is enabled"
[[ "$ffmpeg_version" == *"--disable-nonfree"* ]] || fail "FFmpeg non-free mode is enabled"
$contents/Resources/Tools/ffmpeg -decoders 2>&1 | grep -q ' vp9 ' \
  || fail "FFmpeg VP9 decoder is missing"
$contents/Resources/Tools/ffmpeg -encoders 2>&1 | grep -q ' hevc_videotoolbox ' \
  || fail "FFmpeg VideoToolbox HEVC encoder is missing"

if find "$app_path" -name '.DS_Store' -o -name '.eucrante-youtube-cookies.txt' | grep -q .; then
  fail "bundle contains a forbidden transient file"
fi

echo "Verified signed Eucrante app bundle: $app_path"
