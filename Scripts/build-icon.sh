#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
source_image="$project_root/App/Artwork/EucranteIconSource.png"
output_path="${1:-$project_root/dist/Eucrante.icns}"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/eucrante-icon.XXXXXX")"
trap 'find "$temporary_directory" -depth -delete 2>/dev/null || true' EXIT

[[ -f "$source_image" ]] || {
  echo "App icon source is missing: $source_image" >&2
  exit 1
}

master="$temporary_directory/EucranteIcon.png"
iconset="$temporary_directory/Eucrante.iconset"
committed_master="$project_root/App/Artwork/EucranteIcon.png"
mkdir -p "$iconset" "${output_path:h}"
swift "$project_root/Scripts/render-app-icon.swift" "$source_image" "$master"
cmp -s "$master" "$committed_master" || {
  echo "Committed app icon is missing or does not match its reproducible source." >&2
  exit 1
}

for specification in \
  '16 icon_16x16.png' \
  '32 icon_16x16@2x.png' \
  '32 icon_32x32.png' \
  '64 icon_32x32@2x.png' \
  '128 icon_128x128.png' \
  '256 icon_128x128@2x.png' \
  '256 icon_256x256.png' \
  '512 icon_256x256@2x.png' \
  '512 icon_512x512.png' \
  '1024 icon_512x512@2x.png'; do
  size="${specification%% *}"
  name="${specification#* }"
  sips --resampleHeightWidth "$size" "$size" "$master" --out "$iconset/$name" >/dev/null
done

iconutil --convert icns "$iconset" --output "$output_path"
echo "Built app icon: $output_path"
