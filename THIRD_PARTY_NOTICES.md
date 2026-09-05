# Third-party notices

Eucrante's build embeds the following command-line tools. They are separate works and retain their own licenses.

## yt-dlp

- Project: https://github.com/yt-dlp/yt-dlp
- Pinned release: `2026.07.04`
- License: The Unlicense
- Source artifact: upstream `yt-dlp_macos.zip` (onedir), verified before preparation
- Packaging changes: remove Intel Mach-O slices using `lipo`, restore byte-verified Python.framework aliases as relative symlinks, and sign the launcher and native libraries. Python bytecode, extractors, dependency data, and licenses are retained. No runtime source code is patched.

## Deno

- Project: https://github.com/denoland/deno
- Pinned release: `2.9.5`
- License: MIT License
- Embedded artifact: upstream macOS architecture-specific `deno` executable

## FFmpeg

- Project: https://ffmpeg.org/
- Pinned release: `9.0.1`
- License: GNU Lesser General Public License 2.1 or later
- Embedded artifact: locally built, separate minimal `ffmpeg` executable
- Configuration: GPL, non-free, network, and external codec libraries disabled; native VP9 decoding and Apple VideoToolbox HEVC encoding enabled
- Corresponding source: exact official source URL and SHA-256 are recorded in `Scripts/build-ffmpeg.sh`

Release archives include the corresponding upstream license texts. Pinned versions, source/artifact hashes, and the reproducible FFmpeg configuration are recorded in `Scripts/install-local-tools.sh` and `Scripts/build-ffmpeg.sh`.
