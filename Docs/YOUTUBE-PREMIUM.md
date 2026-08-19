# YouTube Premium

## Selected design

Premium-aware acquisition runs locally inside Eucrante. The user signs in through a dedicated WebKit view owned by Eucrante; the bundled downloader receives applicable cookies from that private session only while requesting media from the same local network context. Eucrante does not read an external browser, has no service that receives the session, and does not log or retain its temporary cookie export.

This design replaced the Cloudflare experiment. Testing showed that authenticated resolution in a datacenter container did not make the selected media object transferable: container fetches produced an empty body and redirecting the short-lived URL to the Mac produced HTTP 403. Adding a residential relay or proxy would have created the extra runtime layer the product rejects.

## Current behavior

- The private in-app session is optional and off by default.
- Eucrante does not request Files & Folders access to Brave, Safari, Chrome, Firefox, or another browser.
- The session persists in Eucrante's own WebKit store until the user chooses **Sign Out of Eucrante**.
- Per-job cookie exports use mode `0600` and are deleted immediately after acquisition succeeds or fails.
- Premium may expose higher-bitrate audio or authenticated formats, but not every video has a distinct “Premium” 1080p entry.
- Through 1080p, Eucrante selects H.264 plus AAC and merges locally without re-encoding. For 1440p/4K it prefers VP9 and converts locally to Apple-native HEVC while copying AAC.
- DRM-protected media remains out of scope.

## Verified fixture

The media path for `YH6HJb_F-LE` has completed authenticated development checks in both forms: 1920×1080 H.264 plus AAC produced a 65,350,728-byte losslessly merged MP4, and 3840×2160 VP9 plus Premium AAC produced a 327,407,509-byte `hvc1` HEVC MP4. Both passed AVFoundation inspection. These are development fixture results, not redistributable test assets or a promise that the provider's future formats remain identical. The app-owned sign-in UI and cookie lifecycle require a fresh interactive acceptance check before the first public binary.
