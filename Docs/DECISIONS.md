# Architecture decisions

## ADR-001: Native SwiftUI application

Use SwiftUI for the Mac interface and Apple frameworks for filesystem integration, media verification, conversion, notifications, and Music automation.

## ADR-002: Single local runtime

Eucrante has no Worker, server, container, R2 bucket, localhost process, or relay computer. Provider extraction and byte transfer run as signed child executables within the app bundle.

## ADR-003: Local extractor boundary

Use the official `yt-dlp_macos` release behind the narrow `LocalMediaAcquiring` protocol. Do not copy an upstream web client/server or interpolate input into a shell. Pin and verify every bundled artifact.

## ADR-004: Opt-in browser session

Browser session use is disabled by default and selected in Settings. The helper reads the browser's current session directly; Eucrante does not create a cookie export or send credentials elsewhere.

## ADR-005: Apple-compatible first video path

Ship lossless merging of the best H.264 MP4 and AAC M4A tracks first. Add 4K VP9/AV1-to-HEVC only with a reproducible, appropriately licensed transcoder build and golden SDR/HDR fixtures.

## ADR-006: Apache-2.0

License original Eucrante code and documentation under Apache-2.0. Preserve the licenses and notices of independently distributed bundled tools.
