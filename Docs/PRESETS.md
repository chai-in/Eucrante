# One-click media presets

## Design rule

Acquire the best source that the current Apple-native pipeline can decode and verify. Do not upscale resolution, sample rate, bit depth, or bitrate, and do not transcode when the source is already compatible with the selected Apple destination. Converting a lossy source to a lossless format does not restore lost quality and only increases file size.

Presets are output policies, not promises that every provider exposes a lossless or high-resolution source. The completed job must show the source format and the actual output decision: passthrough, remux, or transcode.

| One-click action | Source request | Preferred output | Storage policy |
| --- | --- | --- | --- |
| Music — Best | Best Apple-compatible AAC/M4A audio exposed by the provider | Verified source `.m4a` | Preserve the best directly compatible source without generation loss |
| Music — Efficient | Best Apple-compatible AAC/M4A audio exposed by the provider | Verified AAC `.m4a`; preserve a suitable existing source | Storage-conscious without unnecessary re-encoding |
| Video — Best | Best H.264 through 1080p; VP9 for 1440p/4K; best AAC | Preserved H.264 or high-quality VideoToolbox HEVC in MP4 | Preserve resolution and favor picture quality |
| Video — Efficient | Same resolution policy and compatible AAC | Storage-balanced VideoToolbox HEVC + AAC | Smaller Apple-native output without upscaling or minimum-size compromises |

The main screen exposes these as four primary buttons. Once a valid URL is present, choosing a preset creates the job immediately; advanced controls create a Custom policy instead of silently modifying a named preset.

## Audio presets

### Music — Best

Goal: the highest-quality Apple Music-compatible file without wasteful expansion.

1. Request audio-only mode and the best AAC/M4A source exposed by the provider.
2. Preserve the compatible source without transcoding.
3. Verify that the output contains readable audio and is non-empty before completion.
4. Do not wrap lossy audio in Apple Lossless or claim quality the source does not contain.

### Music — Efficient

Goal: high perceptual quality with predictable storage use.

This is a quality/storage balance, not a minimum-size mode. AAC-LC is the normal full-bandwidth AAC profile used for music—not low-bitrate HE-AAC.

1. Request audio-only mode and the best AAC/M4A source exposed by the provider.
2. Preserve an existing compatible AAC source when it is already suitable.
3. Otherwise convert once to AAC in an `.m4a` container using Apple's system encoder.
4. Do not increase the effective quality of a lower-bitrate lossy source by merely assigning a larger output bitrate.

If the provider exposes only one suitable AAC source, Best and Efficient may preserve the same file. Eucrante does not re-encode merely to make the bitrate label smaller.

## Video presets

### Video — Best

Goal: preserve the highest Apple-compatible picture quality in a format supported by current Apple playback and library apps.

1. Through 1080p, request H.264 MP4 video and AAC/M4A audio and merge locally without re-encoding.
2. At 1440p and above, prefer VP9 video, decode locally, and encode high-quality HEVC using Apple VideoToolbox; use hardware acceleration when available and Apple's software fallback otherwise, and copy compatible AAC without another lossy encode.
3. Preserve source resolution, frame rate, aspect ratio, and compatible color metadata. Never upscale.
4. Tag HEVC as `hvc1` and use `.mp4` output for Apple playback.

The 4K SDR path is live and verified. HDR preservation is not yet promised; HDR/color fixtures remain a release gate.

### Video — Efficient

Goal: materially smaller files while retaining strong visual quality and Apple compatibility.

1. Request the same resolution and codec source policy as Video — Best.
2. Encode VP9 video as HEVC using Apple VideoToolbox with a storage-balanced quality setting, retaining source resolution and never upscaling; use hardware acceleration when available and Apple's software fallback otherwise.
3. This is not a minimum-size mode and does not use low-quality compatibility settings.
4. Do not claim HDR preservation until HDR/color fixtures ship.
5. Keep Apple-compatible AAC audio in the output.
6. Retain the original until the converted file is verified.

## Apple Music import

Apple Music import is a separate user action after the output file has been verified. The app must request macOS Automation access only when the user first chooses **Import to Music**, keep the downloaded file unless the user explicitly requests deletion, and report whether Music accepted the file.

## Implementation boundary

The native client exposes all four policies, acquires tracks locally, inspects the source, selects passthrough or conversion, re-inspects the output, and records the actual decision in job history. Music import remains a separate explicit action. If an installed or beta macOS build does not expose the required Apple encoder, the job fails with a capability message and retains its source staging data for retry; it is never labeled as a successful AAC, ALAC, or HEVC output.

Before a notarized public release, the policies still require licensed 720p/1080p/4K SDR golden fixtures, multichannel audio fixtures, clean-machine browser/Music permission testing, and tuning of the Efficient video bounds. HDR fixtures are required before HDR preservation can be claimed.

## Acceptance tests

- Lossy input is never expanded to Apple Lossless.
- Compatible input follows the passthrough/remux path without generation loss.
- Output never exceeds the source resolution, sample rate, or bit depth.
- AAC output opens correctly and can be imported into Music.
- HEVC output opens in QuickTime Player and imports into the intended Apple library app.
- Cancellation removes partial output and retains the verified source file.
- Efficient video produces a smaller verified file for representative fixtures; Efficient audio avoids a higher-bitrate source when the provider exposes a suitable alternative.
- The named preset buttons map to immutable output policies; changing an advanced setting relabels the job as Custom.
