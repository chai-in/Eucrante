# Delivery roadmap

## Current implementation snapshot

Delivered in the development branch: the native SwiftUI shell, bring-your-own Cloudflare Worker/Container/R2 stack, WARP or service-token access, persistent local jobs, folder bookmarks, progress/cancel/retry, retained-cloud deletion, one-click preset policy and verification, filename previews, explicit Music import, redacted diagnostics, a custom URL scheme, and Developer ID/notarization scripts.

Remaining before a public beta: broader local-processing response coverage, gallery multi-select and Quick Look, licensed golden-media tests across SDR/HDR and multichannel audio, notification/Dock integrations, app identity assets, clean-machine permission testing, and an actual Developer ID notarized artifact. Share/Shortcuts extensions and a signed update feed remain later integrations.

## Phase 0 — Foundation

- Product definition, decision record, system design, and UI specification.
- Swift package with `EucranteCore`, `EucranteApp`, and tests.
- Typed request/response models.
- Eucrante deployment settings and Keychain-backed Cloudflare Access credentials.
- Auto/audio/mute request-to-file vertical slice.

Exit: `swift run EucranteCoreChecks` and `swift test` pass under their documented toolchains and the package builds; a compatible API can save a tunnel or redirect response.

## Phase 0.5 — Bring-your-own Cloudflare stack

- Worker gateway with generated bindings, structured redacted logging, and deployment discovery.
- Cobalt Container binding with a single-instance-safe MVP routing policy.
- Private R2 bucket and opaque job-prefix object model.
- Conditional Range downloads, multipart output upload, retry manifests, and explicit prefix deletion.
- Deployment automation that creates resources in the user's account without committing secrets.
- Cloudflare Access service-token support; maintainer deployment requires the dedicated token plus WARP/Gateway posture.

Exit: a fresh paid Cloudflare account can deploy the stack, save a job, resume an interrupted transfer, relaunch the Mac app, retrieve the retained output, and delete the cloud job.

## Phase 1 — Product-quality remote client

- Xcode app project, bundle metadata, assets, sandbox decision, signing, and entitlements.
- User-selected output folder and security-scoped bookmark.
- Download progress/cancellation through a background-capable URLSession delegate.
- Persistent queue/history, retry, gallery multi-select, Quick Look, Finder reveal.
- Complete settings schema and endpoint diagnostics.
- Unit, networking-contract, accessibility, and UI tests.
- Developer ID archive, notarization, and private release artifact.

Exit: daily-driver beta with no local processing dependency.

## Phase 2 — Local media pipeline

- Implement the four output presets in `PRESETS.md`: Apple Music Best/Efficient and Apple Video Best/Efficient.
- Add verified passthrough/remux decisions before any transcoding.
- Add Apple Lossless and AAC `.m4a` outputs, metadata/artwork transfer, and an explicit Music import action.
- Add highest-quality and storage-efficient HEVC outputs with HDR preservation tests.
- Implement `local-processing` response stages: merge, mute, audio, GIF, remux, proxy, subtitles, cover art, and metadata.
- AVFoundation capability matrix and FFmpeg licensing decision.
- Bounded worker pool, disk-space preflight, cancellation, temp-file cleanup, and crash recovery.
- Golden-media integration fixtures.

Exit: every documented Cobalt response type and every one-click Apple preset completes end to end with verified output metadata.

## Phase 3 — macOS integrations

- Share extension, Services menu, drag/drop, custom URL scheme, Shortcuts actions.
- Menu-bar drop target, notifications, Dock progress, and configurable completion actions.
- Presets and per-service overrides.

Exit: native entry points work without opening the main window first.

## Phase 4 — Distribution and maintenance

- Signed update feed, privacy policy, attribution bundle, crash-diagnostics opt-in.
- Compatibility matrix across supported macOS and Cobalt API versions.
- Release checklist and rollback plan.

## Recommended next implementation order

1. Install full Xcode and create the signed app target around the package.
2. Approve the working UI shell and identity.
3. Add URLProtocol-backed API tests and a local fixture server.
4. Implement cancellable progress downloads and folder bookmarks.
5. Build and exercise the bring-your-own Cloudflare Worker, Container, and R2 stack.
6. Decide and implement local processing.
