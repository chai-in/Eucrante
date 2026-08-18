# Changelog

All notable changes to Eucrante will be documented here.

## Unreleased

### Added

- Single-app local acquisition using pinned, checksum-verified yt-dlp and Deno executables.
- Explicit Brave, Chrome, Firefox, and Safari session selection for local authenticated YouTube requests.
- Native H.264 plus AAC download, AVFoundation merge, output inspection, and exact live end-to-end check.
- Four Apple-oriented one-click policies, filename previews, local queue/history, cancellation, retry, notifications, Finder/Trash actions, and explicit Music import.

### Changed

- Removed the Cloudflare Worker/Container/R2 architecture and every server/account setup screen.
- Diagnostics now report only local tool readiness, selected browser type, preferences, and job-state counts.

### Security

- Helper releases and SHA-256 digests are pinned; build fails on mismatch.
- Helper invocation uses `Process` argument arrays and never invokes a shell.
- Browser cookies are presented only to the selected provider; Eucrante has no receiving service and does not log or persist them.
