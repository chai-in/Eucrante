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

### Changed

- Removed the Cloudflare Worker/Container/R2 architecture and every server/account setup screen.
- Diagnostics now report only local tool readiness, whether an in-app YouTube session exists, preferences, and job-state counts.
- The in-app YouTube browser now uses a compact native toolbar and leaves the rest of the window to the website.

### Security

- Helper releases and SHA-256 digests are pinned; build fails on mismatch.
- Helper invocation uses `Process` argument arrays and never invokes a shell.
- Temporary in-app-session cookie exports use mode `0600`, are presented only to the provider, and are deleted after acquisition on both success and failure.
