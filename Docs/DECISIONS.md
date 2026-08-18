# Architecture decision log

## ADR-001: Native SwiftUI application

**Status:** Accepted

Use Swift 6, SwiftUI, and targeted AppKit bridges instead of React/Electron, Tauri, or a web wrapper.

Reasons: the product is Mac-only; native menus, Settings, drag/drop, accessibility, Keychain, Share extensions, and background URLSession behavior are first-class requirements. The smaller runtime and direct platform integration outweigh cross-platform reuse.

## ADR-002: Engine protocol

**Status:** Accepted

All processing starts through `MediaProcessingEngine`. The first implementation is `CobaltAPIClient`; a later `LocalProcessingEngine` can be introduced without changing feature views.

## ADR-003: No default public API

**Status:** Accepted

The app starts unconfigured and asks for a user-controlled Cobalt endpoint. The official hosted endpoint is not a supported default because upstream documentation forbids unapproved third-party use.

## ADR-004: Direct distribution first

**Status:** Proposed

Target Developer ID signing and notarization first. Media download behavior, executable codecs, folder access, and helper processes need deliberate Mac App Store policy validation before choosing the store.

## ADR-005: Local processing boundary

**Status:** Proposed

Prefer AVFoundation for operations it can perform reliably. Evaluate a narrowly configured FFmpeg distribution for missing codecs/containers. Keep subprocess execution in a dedicated actor and never pass untrusted strings through a shell.

## ADR-007: Remote resolver for MVP

**Status:** Accepted

Use a user-controlled Cobalt v11 instance to resolve service URLs. Do not bundle the upstream Node server in the first release. A pure Swift rewrite would duplicate a large, fast-changing extractor surface, while a bundled server introduces AGPL, native-module, code-signing, sandbox, and maintenance costs before the native workflow is validated.

## ADR-006: Original visual identity

**Status:** Accepted

Use system typography, SF Symbols, an original product name, and an independent visual palette. Do not reuse upstream names, mascots, logos, illustrations, or web-client source.

## ADR-008: Apache-2.0 public project

**Status:** Accepted

License the original client code and documentation under Apache License 2.0. The explicit contributor patent grant and permissive redistribution terms fit a public native application. Keep upstream Cobalt code and branding out of the repository; any future bundled AGPL component requires a separate architecture and licensing review.

## ADR-009: Source-aware Apple presets

**Status:** Accepted

Provide four one-click output policies: Apple Music Best, Apple Music Efficient, Apple Video Best, and Apple Video Efficient. Always acquire and inspect the best available source, prefer passthrough/remux, never upscale, never imply that lossless conversion restores quality, and perform at most one lossy transcode. The complete contract lives in `PRESETS.md`.

## ADR-010: Bring-your-own Cloudflare deployment

**Status:** Accepted

Operate no shared project backend. Every user deploys their own Cloudflare Worker, Cobalt Container, and R2 bucket. The public repository supplies deployment automation and configuration contracts, but never an account credential, global service secret, or default hosted endpoint.

## ADR-011: Durable R2 job retention

**Status:** Accepted

Use a private R2 bucket for resumable job inputs and verified outputs. Completed jobs have no automatic expiration and remain until the user explicitly deletes the cloud job. Do not apply an indefinite bucket lock because it would prevent that user-directed deletion. Incomplete multipart parts may follow Cloudflare's safety cleanup policy; their durable job manifest remains retryable.

## ADR-012: Owner deployment requires WARP

**Status:** Accepted

Protect the maintainer's personal Worker with Cloudflare Access and require enrolled WARP/Gateway device posture. Authenticate the native app with a dedicated Access service token stored in Keychain; never embed a Cloudflare management token. Other users own and choose the Access policy for their separate deployment.

## ADR-013: Eucrante identity

**Status:** Accepted

Name the independent native project **Eucrante**, after the Nereid associated with fulfillment and successful voyages. Use an original icon and visual system, and retain Cobalt only where it names the compatible upstream API or separately distributed container.
