# Eucrante

A native macOS client for saving public media through a user-owned Cloudflare deployment backed by a Cobalt-compatible processing instance. Eucrante means “bringer of fulfillment” and is named for a Nereid of successful voyages. This independent open-source project is not affiliated with or endorsed by imput or the Cobalt project.

Eucrante uses an original Mac-native interface and no upstream names, mascots, illustrations, source code, or brand assets.

> [!WARNING]
> This repository is an early alpha. Local media conversion, persistence, signed distribution, and automated Apple Music import are not complete.

## Why Swift

SwiftUI gives the app native windows, menus, keyboard shortcuts, accessibility, drag and drop, Share extensions, Keychain access, and efficient background networking without shipping a browser runtime. AppKit bridges remain available for macOS-specific behavior that SwiftUI does not expose cleanly.

## Current vertical slice

- Configure a user-owned Cloudflare Worker endpoint.
- Paste or type a public media URL.
- Choose automatic, audio-only, or muted-video mode.
- Send the typed Cobalt v11 request.
- Handle tunnel, redirect, picker, and API-error responses.
- Download a selected result into `~/Downloads/Eucrante` using a path-safe, collision-free filename.
- Keep an in-memory queue of the current session.
- Authenticate to a private Eucrante deployment with Cloudflare Access credentials stored in Keychain.

Local merge/transcode responses are modeled but intentionally gated until the AVFoundation/FFmpeg decision in Phase 2 is implemented and tested.

## Planned one-click presets

- Apple Music — Best: preserve compatible sources; convert incompatible lossless audio to Apple Lossless without upsampling.
- Apple Music — Efficient: best source followed by AAC 256 VBR `.m4a` output optimized for quality and storage.
- Apple Video — Best: passthrough when possible; otherwise highest-quality HEVC with AAC while preserving HDR.
- Apple Video — Efficient: storage-oriented HEVC with AAC, no upscaling, and an explicit HDR policy.

The preset contract is documented in [Docs/PRESETS.md](Docs/PRESETS.md). Presets will not claim a converted output until the local conversion and verification path is implemented.

## Run locally

Requirements:

- macOS 14 or newer
- Full Xcode installation for the normal GUI development workflow
- Swift 6 toolchain for command-line builds

```sh
swift run EucranteCoreChecks
swift run Eucrante
make app
```

`swift run EucranteCoreChecks` verifies the core wire models and safety helpers.

Opening `Package.swift` in full Xcode provides the simplest GUI development workflow. A signed `.app`, entitlements, assets, and notarized release pipeline are Phase 1 delivery work after the product shell is approved.

`make app` builds a release executable, assembles `dist/Eucrante.app`, and applies ad-hoc signing by default. Set `CODESIGN_IDENTITY` to a Developer ID Application identity for a hardened signed build. Notarization is intentionally separate from this local packaging step.

## Important API constraint

The official Cobalt documentation says hosted instances such as `api.cobalt.tools` are not intended for third-party apps. The app therefore provides no shared backend: each user deploys the Worker, Cobalt Container, and private R2 bucket in their own Cloudflare account. Completed jobs and their media remain in that bucket until the user explicitly deletes them. The app never contains a project-operated endpoint or Cloudflare management token.

The deployable Worker/R2/Container package is in [`Backend/`](Backend/). The deployment, WARP policy, and retention contract is documented in [Docs/CLOUDFLARE.md](Docs/CLOUDFLARE.md).

- [Official Cobalt repository](https://github.com/imputnet/cobalt)
- [Cobalt API documentation](https://github.com/imputnet/cobalt/blob/main/docs/api.md)
- [Self-hosting guide](https://github.com/imputnet/cobalt/blob/main/docs/run-an-instance.md)

## Project documents

- [Product definition](Docs/PRODUCT.md)
- [System architecture](Docs/ARCHITECTURE.md)
- [UI system](Docs/UI-SYSTEM.md)
- [Delivery roadmap](Docs/ROADMAP.md)
- [Decision log](Docs/DECISIONS.md)
- [One-click preset specification](Docs/PRESETS.md)
- [Bring-your-own Cloudflare deployment](Docs/CLOUDFLARE.md)

## Contributing and support

- Read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing a change.
- Follow the [Code of Conduct](CODE_OF_CONDUCT.md).
- Use [SUPPORT.md](SUPPORT.md) for issue-reporting guidance.
- Review [PRIVACY.md](PRIVACY.md) before connecting the app to an instance.
- Report vulnerabilities privately using [SECURITY.md](SECURITY.md).

## Responsible use

Use this software only for public, non-DRM media that you own or are legally permitted to download and use. The project does not provide access to a hosted Cobalt API and does not bypass access controls.

## License

The original code and documentation in this repository are licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution and non-affiliation information.

The native client is written independently against the documented API contract. Upstream Cobalt API code is AGPL-3.0, its web client is CC-BY-NC-SA-4.0, and its branding assets are excluded from the web license. Do not copy those sources or assets into this repository without deliberately reviewing and adopting their obligations.
