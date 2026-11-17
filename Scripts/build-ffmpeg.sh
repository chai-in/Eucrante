#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
tools_directory="$project_root/.build/eucrante-tools"
licenses_directory="$tools_directory/ffmpeg-licenses"
ffmpeg_version="9.0.1"
ffmpeg_source_sha256="cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635"
ffmpeg_source_url="https://ffmpeg.org/releases/ffmpeg-$ffmpeg_version.tar.xz"
ffmpeg_binary="$tools_directory/ffmpeg"
ffmpeg_stamp="$tools_directory/ffmpeg.sha256"

[[ "$(uname -m)" == "arm64" ]] || {
  echo "Eucrante's media engine requires a native Apple silicon build." >&2
  exit 1
}

mkdir -p "$tools_directory"

verified_cached_binary() {
  [[ -x "$ffmpeg_binary" && -f "$ffmpeg_stamp" ]] || return 1
  [[ "$(lipo -archs "$ffmpeg_binary")" == "arm64" ]] || return 1
  local expected actual
  expected="$(<"$ffmpeg_stamp")"
  actual="$(shasum -a 256 "$ffmpeg_binary" | awk '{print $1}')"
  [[ -n "$expected" && "$actual" == "$expected" ]] || return 1
  "$ffmpeg_binary" -version 2>/dev/null | grep -q "ffmpeg version $ffmpeg_version" || return 1
  "$ffmpeg_binary" -version 2>/dev/null | grep -q -- "--disable-gpl" || return 1
  "$ffmpeg_binary" -version 2>/dev/null | grep -q -- "--disable-nonfree" || return 1
  "$ffmpeg_binary" -encoders 2>/dev/null | grep -q "hevc_videotoolbox" || return 1
  "$ffmpeg_binary" -decoders 2>/dev/null | grep -q "vp9" || return 1
}

if verified_cached_binary && [[ -f "$licenses_directory/COPYING.LGPLv2.1" ]]; then
  echo "Pinned LGPL FFmpeg $ffmpeg_version is ready."
  exit 0
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/eucrante-ffmpeg.XXXXXX")"
trap 'find "$temporary_directory" -depth -delete 2>/dev/null || true' EXIT

curl --fail --location --proto '=https' --tlsv1.2 \
  "$ffmpeg_source_url" \
  --output "$temporary_directory/ffmpeg.tar.xz"

actual_source_sha256="$(shasum -a 256 "$temporary_directory/ffmpeg.tar.xz" | awk '{print $1}')"
if [[ "$actual_source_sha256" != "$ffmpeg_source_sha256" ]]; then
  echo "Checksum verification failed for FFmpeg $ffmpeg_version source."
  exit 1
fi

tar -xJf "$temporary_directory/ffmpeg.tar.xz" -C "$temporary_directory"
source_directory="$temporary_directory/ffmpeg-$ffmpeg_version"
install_directory="$temporary_directory/install"

cd "$source_directory"
./configure \
  --prefix="$install_directory" \
  --disable-doc \
  --disable-debug \
  --disable-network \
  --disable-autodetect \
  --disable-gpl \
  --disable-nonfree \
  --disable-programs \
  --enable-ffmpeg \
  --disable-everything \
  --enable-avcodec \
  --enable-avformat \
  --enable-avfilter \
  --enable-swscale \
  --enable-swresample \
  --enable-protocol=file,pipe \
  --enable-demuxer=matroska,mov \
  --enable-muxer=mp4 \
  --enable-decoder=vp9,aac \
  --enable-encoder=hevc_videotoolbox \
  --enable-parser=vp9,aac \
  --enable-filter=scale,format \
  --enable-videotoolbox \
  --enable-audiotoolbox

make -j"$(sysctl -n hw.logicalcpu)" ffmpeg
strip ffmpeg

version_output="$(./ffmpeg -version)"
[[ "$version_output" == *"ffmpeg version $ffmpeg_version"* ]]
[[ "$version_output" == *"--disable-gpl"* ]]
[[ "$version_output" == *"--disable-nonfree"* ]]
./ffmpeg -encoders 2>/dev/null | grep -q "hevc_videotoolbox"
./ffmpeg -decoders 2>/dev/null | grep -q "vp9"

ditto ./ffmpeg "$ffmpeg_binary"
chmod 755 "$ffmpeg_binary"
shasum -a 256 "$ffmpeg_binary" | awk '{print $1}' > "$ffmpeg_stamp"

find "$licenses_directory" -depth -delete 2>/dev/null || true
mkdir -p "$licenses_directory"
ditto "$source_directory/LICENSE.md" "$licenses_directory/LICENSE.md"
ditto "$source_directory/COPYING.LGPLv2.1" "$licenses_directory/COPYING.LGPLv2.1"
ditto "$source_directory/COPYING.LGPLv3" "$licenses_directory/COPYING.LGPLv3"

echo "Built pinned LGPL FFmpeg $ffmpeg_version with Apple VideoToolbox HEVC support."
