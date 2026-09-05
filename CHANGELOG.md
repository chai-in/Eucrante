# Changelog

All notable changes to Eucrante will be documented here.

## Unreleased

### Added

- Searchable queue with status filters, FIFO scheduling, pause/resume, and inline file actions.
- Immutable per-save preferences and destination bookmarks, including retry and relaunch behavior.
- Debug-only disposable UI preview with generated media fixtures.

- Single-app local acquisition using pinned, checksum-verified yt-dlp and Deno executables.
- Optional app-owned YouTube sign-in using Eucrante's private WebKit data store, with no external-browser file access.
- Native H.264 plus AAC download, AVFoundation merge, output inspection, and exact live end-to-end check.
- Verified 1440p/4K VP9 acquisition and Apple VideoToolbox HEVC/H.265 conversion with AAC stream copy.
- Pinned, checksum-verified, reproducible LGPL FFmpeg 9.0.1 source build with GPL, non-free, network, x264, and x265 components excluded.
- Four Apple-oriented one-click policies, filename previews, local queue/history, cancellation, retry, notifications, Finder/Trash actions, and explicit Music import.
- Persistent bottom download progress with the active preset, concrete phase, percentage when available, queue access, and cancellation.
- Branded, reproducibly generated macOS app icon with a complete `.icns` size pyramid.
- Native drag-to-Applications DMG generation with a branded Finder layout, development preview mode, future Developer ID signing/notarization, Gatekeeper verification, checksums, and provenance.
- Public unnotarized DMG prerelease flow with enforced filenames, ad-hoc-signing provenance, portable checksums, and fixed macOS Open Anyway guidance.
- Responsive Cloudflare Workers Static Assets product/documentation site with portable build validation and a branded social preview.
- Public repository metadata, release immutability, security analysis, and protected release/branch rulesets without GitHub Actions usage.
- App-layer navigation tests, downloader parser/error/output tests, concurrent destination tests, secure-file tests, and an enforced coverage floor.
- Unresponsive-process cancellation, bounded streaming-output, concurrent store, and immediate app-model persistence tests.
- Deterministic app-orchestration tests covering verified local completion, interrupted-job recovery, the embedded YouTube-session gate, and sign-out cancellation.

### Changed

- Package the pinned yt-dlp onedir runtime with arm64 native libraries and deduplicated framework aliases, eliminating runtime extraction on every launch. Verify all nested code and record the full payload in release provenance.
- Reuse unchanged history rows' JSON with a bounded cache, skip unchanged startup snapshots, and retain exact v2 recovery and atomic-write behavior.
- Receive artwork in native URLSession chunks, preserve normalized JPEG bytes during Music import, and avoid a full artwork encode during selection validation.
- Export separate video/audio compositions directly into verified destination staging; Efficient saves no longer write a full H.264 intermediate before HEVC encoding.
- Run independent startup readiness checks concurrently and minify fingerprinted website CSS without adding browser dependencies.

- Share one downloader invocation and provider extraction across video/audio tracks, and request only the preview fields the app displays.
- Bound and coalesce progress delivery, reuse identical previews, and avoid filesystem checks during queue-row rendering.
- Stream artwork with a 10 MiB response limit and downsample through ImageIO to 2048 pixels before JPEG encoding.
- Use APFS clones for compatible media copies, release consumed staging inputs earlier, and compact/deduplicate atomic history writes while preserving recovery protections.
- Generate fingerprinted website assets with immutable browser caching and reuse the smaller packaged icon for page loads.

- Apple silicon is now the only supported architecture. App, Deno, and FFmpeg builds require arm64; Intel and Rosetta builds are rejected.
- Split application orchestration into a queue owner, download pipeline, link preview controller, and metadata editor.
- Every output, including Custom, is checked before same-volume publication; failed and cancelled processing cleans up partial files.
- History migrates into a v2 store while retaining the original v1 file. Future schemas are rejected without replacement.
- Cancellation remains active until the worker exits; stale progress cannot overwrite retry or completion state.
- Main-window YouTube sign-in now presents its sheet directly, and sign-out waits for credential-using work to finish.

- Removed the Cloudflare Worker/Container/R2 architecture and every server/account setup screen.
- Diagnostics now report only local tool readiness, whether an in-app YouTube session exists, preferences, and job-state counts.
- The in-app YouTube browser uses a compact native toolbar and shows the website only while sign-in or account switching is needed.
- Save now presents only essential controls, Queue rows preserve horizontal alignment, and a ready session uses a concise native state instead of YouTube's account page.
- Removed inherited Cobalt settings that the fully local engine did not honor.
- Destructive history clearing now requires confirmation and states that downloaded files are preserved.
- Apple VideoToolbox HEVC conversion may use Apple's software fallback when hardware encoding is unavailable.
- Job-state transitions now use synchronous atomic persistence instead of a debounce window.
- Unreadable job history is preserved in a private recovery copy before a valid store replaces it; future schemas are never replaced.
- Cancellation now escalates when a helper ignores graceful termination, and retained diagnostics use the latest bounded output.
- Process completion is driven by the child termination signal while output streams through a serialized bounded reader; cancellation no longer depends on pipe EOF and cannot hang when a descendant retains a descriptor.
- Helper HOME, XDG config/cache, Deno cache, and temporary paths now resolve inside each private job directory instead of the user's home folder.
- Bundled-tool readiness checks now run in parallel and time out with cancellation instead of leaving Settings indefinitely busy when a helper stalls.

### Security

- Helper releases and SHA-256 digests are pinned; build fails on mismatch.
- Helper invocation uses `Process` argument arrays and never invokes a shell.
- Temporary in-app-session cookie exports are created inside mode-`0700` job directories with mode `0600` before any credential bytes are written, are used only for YouTube jobs, and are deleted after acquisition on both success and failure.
- Job history uses mode-`0600` same-directory atomic replacement; downloader output discovery rejects empty files and symbolic links.
- The embedded sign-in browser has an automated HTTPS/domain allowlist contract that rejects lookalike hosts.

### Build

- Local macOS checks validate plist and shell syntax, enforce strict Swift formatting plus `92%` core and `83%` app line-coverage floors, and audit the assembled signed app bundle, tool architectures, licenses, identifier, icon, and restricted FFmpeg configuration.
- Cloudflare builds validate the static website before deploying it; Dependabot maintains the pinned Wrangler dependency.
- Coverage is enforced by `make coverage` against 92% core and 83% app line-coverage floors.
- Explicit main-actor app-model initialization avoids an Xcode 16.4 Swift 6.1 compiler crash during clean builds.
- The release script now requires a clean exact version tag and Developer ID signature before notarization, then emits paired architecture-labelled DMG/ZIP artifacts, portable checksums, and JSON provenance containing Apple's notarization request IDs.
- The public-preview publisher accepts only exact-tag `-unnotarized.dmg` artifacts, verifies their ad-hoc-signing provenance, and creates a prerelease draft with non-optional Gatekeeper instructions.
- All nested tools and the app now use Hardened Runtime. Deno receives only its required V8 JIT entitlement; yt-dlp receives only the library-validation exception required by its extracted Python framework. The verifier rejects unexpected extra entitlements and exercises both helpers under their final signatures.
