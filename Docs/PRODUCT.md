# Product definition

## Product promise

Paste a link, choose how it should be saved, and get a file with native macOS reliability and no account, tracking, ads, or embedded browser.

The app is an independent open-source desktop client, not a project-operated processing service. It only handles public media that the user is authorized to save. Each user owns the configured Cloudflare deployment, private R2 history, and output files.

## Product principles

1. **One obvious primary action.** A URL field and Save button remain the visual center.
2. **Mac-native, not a wrapped website.** Windows, menus, Settings, keyboard navigation, Keychain, Finder reveal, Share extension, and notifications behave like first-party macOS software.
3. **Private by ownership.** No analytics, project account, shared backend, browser cookies, or clipboard polling. Cloud history exists only inside the user's own private R2 bucket.
4. **Progressive control.** Common defaults are visible; service-specific settings stay out of the way until needed.
5. **Recoverable work.** Queue entries explain their stage, can be retried, and retain enough state to diagnose failures.
6. **Engine independence.** Remote API and future local processing conform to one contract.

## Users and primary jobs

### Primary user

A Mac user who occasionally saves a public video, audio track, image set, or post and values a fast, trustworthy native workflow.

### Core jobs

- Paste or Share a URL and save the best compatible media.
- Extract audio in a preferred format and bitrate.
- Save a muted video.
- Choose one or many items when a post contains a gallery.
- Inspect progress and reveal completed files in Finder.
- Change quality, codec, container, subtitles, metadata, and filename behavior.
- Use a private, user-owned Worker/Container/R2 deployment with Access or API-key authentication.

## Scope

### MVP

- macOS 14+ SwiftUI application.
- Remote Cobalt v11-compatible engine.
- Endpoint health check and supported-service discovery.
- URL validation and Save modes: Auto, Audio, Mute.
- Video quality; audio format and bitrate; metadata and filename preferences.
- Tunnel and redirect downloads.
- Picker UI for galleries.
- Persistent queue/history, retry, cancellation, Finder reveal, local Trash, and retained-cloud deletion.
- Cloudflare Access service token in Keychain.
- Original light/dark visual system, VoiceOver labels, keyboard support, Reduce Motion support.
- Direct Developer ID distribution and notarization.

### Implemented development-beta capabilities

- One-click Apple Music Best/Efficient and Apple Video Best/Efficient presets.
- Verified passthrough/remux decisions, Apple Lossless and AAC audio, and HEVC video with explicit HDR preservation.
- User-initiated import of verified audio into the Music app.
- Local merge, remux, audio conversion, GIF conversion, subtitle muxing, and metadata writing.
- Persistent Codable history stored with complete-file protection.
- Durable resumable job history in the user's private R2 bucket, retained until explicit deletion.
- User-selected download folder stored as a security-scoped bookmark.
- Multiple concurrent jobs with configurable limit.
- Menu-bar drop target and system Share extension.
- Optional completion notifications and a Dock activity count.

Broader gallery multi-select, Quick Look keyboard actions, Share/Menu Bar extensions, and golden-media tuning remain pre-release work.

### Later

- Per-service overrides layered on the four primary output presets.
- Watch-folder or clipboard actions only when explicitly enabled.
- Shortcuts actions.
- Batch import and playlist-aware workflows.
- Signed automatic updates for direct distribution.

### Explicitly out of scope

- Bypassing authentication, paywalls, DRM, or private-content controls.
- Importing browser cookies or account sessions.
- Shipping the upstream web UI inside `WKWebView`.
- Calling `api.cobalt.tools` without permission.
- Running a public multi-user processing service from the app.
- Copying upstream mascot or branding assets.

## Functional requirements

### Save flow

1. Accept a URL through typing, paste, drag and drop, Share extension, or custom URL scheme.
2. Reject non-HTTP(S) URLs before network work.
3. Resolve the current preference preset into a `CobaltRequest`.
4. Submit to the configured engine with a user-visible stage.
5. Route the typed response:
   - tunnel/redirect -> download;
   - picker -> show media selection;
   - local-processing -> enqueue local pipeline;
   - error -> map the code to an actionable message.
6. Save using a sanitized unique filename.
7. Reveal, Quick Look, copy source URL, retry, or remove the queue item.

### Settings

- General: launch behavior, output folder, completion behavior, concurrency.
- Video: quality, YouTube codec/container, H.265 policy, GIF conversion.
- Audio: mode, format, bitrate, better audio, dub language, TikTok original audio.
- Metadata: filename style, metadata toggle, subtitle language.
- Processing: user-owned Worker URL, deployment test, supported services, Access status, API-key auth, and local processing preference.
- Cloud storage: R2 usage, resumable-job state, download retained output, and explicit cloud-job deletion.
- Privacy: diagnostics export and data deletion. Analytics remains absent.

## Success criteria

- A first-time user with a valid personal Cloudflare deployment completes a save without documentation.
- All network and API failures produce an actionable state and preserve the source URL.
- VoiceOver can complete the full save flow.
- A tunnel/redirect integration test writes the expected file and never escapes the destination directory.
- Cold launch to interactive window is under one second on Apple silicon target hardware.
- Idle memory remains materially below an embedded-browser implementation.

## Open product decisions

- Final production Eucrante icon asset; the pearl-and-wave direction is selected, but generated drafts with baked checkerboards were rejected.
- Developer ID direct distribution versus Mac App Store constraints.
- Whether local processing may bundle an FFmpeg build and under which license/configuration.
