# FFmpeg licensing and source

Eucrante builds FFmpeg 9.0.1 from the official source release as a separate,
minimal executable under LGPL 2.1 or later. GPL and non-free components are
explicitly disabled. Eucrante does not include or use x264, x265, or other GPL
codec libraries.

The exact source URL, source SHA-256, configuration, and build steps are in
`Scripts/build-ffmpeg.sh`. The app build embeds FFmpeg's upstream `LICENSE.md`,
`COPYING.LGPLv2.1`, and `COPYING.LGPLv3` alongside this notice.

No changes are made to the FFmpeg source. Public binary releases should attach
the exact corresponding source archive, or provide it from the same download
location, for LGPL compliance.
