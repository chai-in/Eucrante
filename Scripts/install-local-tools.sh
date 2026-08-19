#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
tools_directory="$project_root/.build/eucrante-tools"
yt_dlp_version="2026.07.04"
yt_dlp_sha256="498bd0dae17855c599d371d68ec5bafc439a9d8640e838be25c765a9792f261b"
deno_version="2.9.5"

case "$(uname -m)" in
  arm64)
    deno_asset="deno-aarch64-apple-darwin.zip"
    deno_sha256="b796aadd131f6930560c1ee040cf0d6f53933fbb987464e9ff46bd7ea4830615"
    deno_binary_sha256="b5bd08edab254d42d7b05aa5b6cb4c9b8d4dede4975aff76951ce2cce18866fa"
    ;;
  x86_64)
    deno_asset="deno-x86_64-apple-darwin.zip"
    deno_sha256="c1b8b89a81e91b2a8b3f96def3195d08cfe3a105651da7908d53061f7140510d"
    deno_binary_sha256="befc4fee79127584c0f5c9f76ca6bb73c8e6ff523c01acd52e9c5db1968a09cb"
    ;;
  *)
    echo "Eucrante does not have local media tools for this Mac architecture."
    exit 1
    ;;
esac

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

if ! matches_checksum "$tools_directory/yt-dlp" "$yt_dlp_sha256"; then
  curl --fail --location --proto '=https' --tlsv1.2 \
    "https://github.com/yt-dlp/yt-dlp/releases/download/$yt_dlp_version/yt-dlp_macos" \
    --output "$temporary_directory/yt-dlp"
  verify "$temporary_directory/yt-dlp" "$yt_dlp_sha256"
  chmod 755 "$temporary_directory/yt-dlp"
  ditto "$temporary_directory/yt-dlp" "$tools_directory/yt-dlp"
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
