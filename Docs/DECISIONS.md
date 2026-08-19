# Architecture decisions

## ADR-001: Native SwiftUI application

Use SwiftUI for the Mac interface and Apple frameworks for filesystem integration, media verification, conversion, notifications, and Music automation.

## ADR-002: Single local runtime

Eucrante has no Worker, server, container, R2 bucket, localhost process, or relay computer. Provider extraction and byte transfer run as signed child executables within the app bundle.

## ADR-003: Local extractor boundary

Use the official `yt-dlp_macos` release behind the narrow `LocalMediaAcquiring` protocol. Do not copy an upstream web client/server or interpolate input into a shell. Pin and verify every bundled artifact.

## ADR-004: Opt-in app-owned YouTube session

Authenticated use is disabled by default. Sign-in occurs inside Eucrante using the app's private persistent WebKit store. Eucrante does not read an external browser. A permission-restricted Netscape cookie file is created inside the opaque job folder only for helper acquisition and is removed immediately on success or failure.

Apple Password AutoFill suggestions require a reciprocal `webcredentials` association controlled by the website. Eucrante cannot legitimately claim Google or YouTube domains, so the sign-in sheet provides **Open Passwords** for user-controlled, Touch ID-protected copy/paste. Eucrante must not add a false associated-domain entitlement or programmatically extract credentials from Apple Passwords.

## ADR-005: Apple-compatible wide video path

Losslessly merge H.264 MP4 and AAC M4A through 1080p. For 1440p/4K, prefer VP9 and convert it to `hvc1` HEVC with Apple VideoToolbox. Build a separate minimal FFmpeg executable from pinned official source under LGPL 2.1 or later with GPL, non-free, network, and external codec libraries disabled. Do not use x265. Add AV1 and claim HDR only after their decoder and color fixtures are verified.

## ADR-006: Apache-2.0

License original Eucrante code and documentation under Apache-2.0. Preserve the licenses and notices of independently distributed bundled tools.
