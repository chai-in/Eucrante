# Changelog

All notable changes to Eucrante will be documented here.

## Unreleased

### Added

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

- Removed the Cloudflare Worker/Container/R2 architecture and every server/account setup screen.
- Diagnostics now report only local tool readiness, whether an in-app YouTube session exists, preferences, and job-state counts.
- The in-app YouTube browser uses a compact native toolbar and shows the website only while sign-in or account switching is needed.
- Save now presents only essential controls, Queue rows preserve horizontal alignment, and a ready session uses a concise native state instead of YouTube's account page.
- Removed inherited Cobalt settings that the fully local engine did not honor.
- Destructive history clearing now requires confirmation and states that downloaded files are preserved.
- Apple VideoToolbox HEVC conversion may use Apple's software fallback when hardware encoding is unavailable.
- Job-state transitions now use synchronous atomic persistence instead of a debounce window.
- Unreadable or future-schema job history is preserved in a private recovery copy before a valid store replaces it.
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
- Latest measured line coverage is 92.52% for EucranteCore and 84.91% for EucranteApp, above enforced 92% and 83% floors.
- Explicit main-actor app-model initialization avoids an Xcode 16.4 Swift 6.1 compiler crash during clean builds.
- The release script now requires a clean exact version tag and Developer ID signature before notarization, then emits paired architecture-labelled DMG/ZIP artifacts, portable checksums, and JSON provenance containing Apple's notarization request IDs.
- The public-preview publisher accepts only exact-tag `-unnotarized.dmg` artifacts, verifies their ad-hoc-signing provenance, and creates a prerelease draft with non-optional Gatekeeper instructions.
- All nested tools and the app now use Hardened Runtime. Deno receives only its required V8 JIT entitlement; yt-dlp receives only the library-validation exception required by its extracted Python framework. The verifier rejects unexpected extra entitlements and exercises both helpers under their final signatures.
