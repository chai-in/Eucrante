# One-click media presets

## Design rule

Always acquire the best available source first. Do not upscale resolution, sample rate, bit depth, or bitrate, and do not transcode when the source is already compatible with the selected Apple destination. Converting a lossy source to a lossless format does not restore lost quality and only increases file size.

Presets are output policies, not promises that every provider exposes a lossless or high-resolution source. The completed job must show the source format and the actual output decision: passthrough, remux, or transcode.

| One-click action | Source request | Preferred output | Storage policy |
| --- | --- | --- | --- |
| Apple Music — Best | Best audio-only source | Compatible source, or ALAC `.m4a` for incompatible lossless audio | Preserve real source quality; never inflate lossy audio |
| Apple Music — Efficient | Best audio-only source | AAC `.m4a`, about 256 kbps VBR | High perceptual quality with predictable size |
| Apple Video — Best | Best video and audio source | Compatible passthrough/remux, otherwise highest-quality HEVC + AAC | Preserve resolution, frame rate, color, and HDR |
| Apple Video — Efficient | Best video and audio source | Hardware HEVC + AAC when available | Content-aware bitrate, source resolution up to 4K, never upscale |

The main screen exposes these as four primary buttons. Once a valid URL is present, choosing a preset creates the job immediately; advanced controls create a Custom policy instead of silently modifying a named preset.

## Audio presets

### Apple Music — Best

Goal: the highest-quality Apple Music-compatible file without wasteful expansion.

1. Request audio-only mode and the best available source audio.
2. If the source is already supported by Music, preserve it without transcoding.
3. If a lossless source is incompatible, convert it to Apple Lossless in an `.m4a` container while preserving its native sample rate, bit depth, and channel layout.
4. If a lossy source is incompatible, convert once to AAC in an `.m4a` container. Do not wrap lossy audio in Apple Lossless.
5. Preserve available title, artist, album, artwork, date, track, and copyright metadata.

### Apple Music — Efficient

Goal: high perceptual quality with predictable storage use.

This is a quality/storage balance, not a minimum-size mode. The interface calls the output **AAC 256**. The encoder profile is AAC-LC—the normal full-bandwidth AAC profile used for music—not low-bitrate HE-AAC.

1. Request audio-only mode and the best available source audio.
2. Preserve an existing compatible AAC source when it is already suitable.
3. Otherwise convert once to AAC in an `.m4a` container using the AAC-LC profile, targeting 256 kbps stereo VBR and preserving the native sample rate up to 48 kHz.
4. Do not increase the effective quality of a lower-bitrate lossy source by merely assigning a larger output bitrate.
5. Preserve the same metadata as the Best preset.

## Video presets

### Apple Video — Best

Goal: preserve the highest available picture quality in a format supported by current Apple playback and library apps.

1. Request the maximum source resolution and best available audio.
2. Passthrough or remux existing compatible H.264/HEVC video and AAC/ALAC audio when possible.
3. Otherwise use AVFoundation's highest-quality HEVC export with AAC audio.
4. Preserve source resolution, frame rate, aspect ratio, color metadata, and HDR/Dolby Vision when supported. Never upscale.
5. Prefer `.mp4`; use `.mov` only when required to preserve an Apple media feature or metadata.

### Apple Video — Efficient

Goal: materially smaller files while retaining strong visual quality and Apple compatibility.

1. Request the maximum source quality before local processing.
2. Encode video as HEVC using hardware acceleration when available, retaining source resolution up to 4K and never upscaling.
3. Preserve HDR with 10-bit HEVC when the source is HDR; do not silently tone-map to SDR.
4. Encode audio as AAC using the AAC-LC profile, targeting 192 kbps stereo or 320 kbps for 5.1 audio.
5. Use a content-aware bitrate budget based on pixel count and frame rate rather than a single bitrate for every resolution. Tune and lock the shipping bounds against licensed 720p, 1080p, and 4K SDR/HDR fixtures before release.
6. Show an estimated output size before a long conversion and retain the original until the converted file is verified.

## Apple Music import

Apple Music import is a separate user action after the output file has been verified. The app must request macOS Automation access only when the user first chooses **Import to Music**, keep the downloaded file unless the user explicitly requests deletion, and report whether Music accepted the file.

## Implementation boundary

The current vertical slice can request and download the best source but does not yet transcode media or automate Music. These presets become selectable only when their full local-processing path is available. Until then, the interface may preview them as planned capabilities but must not label an unconverted file as Apple Lossless, AAC, or HEVC output.

## Acceptance tests

- Lossy input is never expanded to Apple Lossless.
- Compatible input follows the passthrough/remux path without generation loss.
- Output never exceeds the source resolution, sample rate, or bit depth.
- AAC output imports into Music and carries expected metadata.
- HEVC output opens in QuickTime Player and imports into the intended Apple library app.
- HDR fixtures retain their transfer function and color metadata.
- Cancellation removes partial output and retains the verified source file.
- Efficient presets produce smaller files than their corresponding Best presets for representative fixtures.
- The named preset buttons map to immutable output policies; changing an advanced setting relabels the job as Custom.
