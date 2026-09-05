#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
tools_directory="$project_root/.build/eucrante-tools"
yt_dlp_version="2026.07.04"
yt_dlp_sha256="b0724470a0cf6dae5175a87eee05d6e75c5a0c10d2c3015166bd4d34e92b1b7b"
deno_version="2.9.5"

[[ "$(uname -m)" == "arm64" ]] || {
  echo "Eucrante requires Apple silicon. Run the build natively, outside Rosetta." >&2
  exit 1
}
deno_asset="deno-aarch64-apple-darwin.zip"
deno_sha256="b796aadd131f6930560c1ee040cf0d6f53933fbb987464e9ff46bd7ea4830615"
deno_binary_sha256="b5bd08edab254d42d7b05aa5b6cb4c9b8d4dede4975aff76951ce2cce18866fa"

mkdir -p "$tools_directory"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/eucrante-tools.XXXXXX")"
trap 'find "$temporary_directory" -depth -delete 2>/dev/null || true' EXIT

verify() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "Checksum verification failed for ${file:t}."
    exit 1
  fi
}

matches_checksum() {
  local file="$1"
  local expected="$2"
  [[ -x "$file" ]] || return 1
  [[ "$(shasum -a 256 "$file" | awk '{print $1}')" == "$expected" ]]
}

if ! python3 "$project_root/Scripts/prepare-downloader.py" verify \
  "$tools_directory/downloader" "$yt_dlp_sha256" 2>/dev/null; then
  curl --fail --location --proto '=https' --tlsv1.2 \
    "https://github.com/yt-dlp/yt-dlp/releases/download/$yt_dlp_version/yt-dlp_macos.zip" \
    --output "$temporary_directory/yt-dlp.zip"
  python3 "$project_root/Scripts/prepare-downloader.py" prepare \
    "$temporary_directory/yt-dlp.zip" "$temporary_directory/downloader" "$yt_dlp_sha256"
  if [[ -d "$tools_directory/downloader" ]]; then
    mv "$tools_directory/downloader" "$temporary_directory/previous-downloader"
  fi
  mv "$temporary_directory/downloader" "$tools_directory/downloader"
fi

if ! matches_checksum "$tools_directory/deno" "$deno_binary_sha256"; then
  curl --fail --location --proto '=https' --tlsv1.2 \
    "https://github.com/denoland/deno/releases/download/v$deno_version/$deno_asset" \
    --output "$temporary_directory/deno.zip"
  verify "$temporary_directory/deno.zip" "$deno_sha256"
  /usr/bin/unzip -q "$temporary_directory/deno.zip" -d "$temporary_directory/deno"
  verify "$temporary_directory/deno/deno" "$deno_binary_sha256"
  chmod 755 "$temporary_directory/deno/deno"
  ditto "$temporary_directory/deno/deno" "$tools_directory/deno"
fi

"$project_root/Scripts/build-ffmpeg.sh"

echo "Local media tools are ready in $tools_directory"
