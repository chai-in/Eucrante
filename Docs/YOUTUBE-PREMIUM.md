# YouTube Premium

## Selected design

Premium-aware acquisition runs locally inside Eucrante. The user selects a signed-in browser in Settings; the bundled downloader reads that session on the same Mac and presents applicable cookies only to YouTube while requesting media from the same local network context. Eucrante has no service that receives them and does not log or persist them.

This design replaced the Cloudflare experiment. Testing showed that authenticated resolution in a datacenter container did not make the selected media object transferable: container fetches produced an empty body and redirecting the short-lived URL to the Mac produced HTTP 403. Adding a residential relay or proxy would have created the extra runtime layer the product rejects.

## Current behavior

- Browser session use is optional and off by default.
- Brave, Chrome, Firefox, and Safari are exposed because the local downloader supports those browser stores on macOS.
- Premium may expose higher-bitrate audio or authenticated formats, but not every video has a distinct “Premium” 1080p entry.
- The first release selects the best Apple-compatible H.264 video and AAC audio exposed to the chosen session, then merges locally without re-encoding.
- DRM-protected media remains out of scope.

## Verified fixture

The live check for `YH6HJb_F-LE` completed from a Brave Premium session as 1920×1080 H.264 plus AAC, produced a 65,350,728-byte merged MP4, and passed AVFoundation inspection. This is a development fixture result, not a redistributable test asset or a promise that the provider's future formats remain identical.
