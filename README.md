# Eucrante

Eucrante is a native macOS app for saving media directly on your Mac. There is no server, account, localhost service, Cloudflare setup, relay PC, or remote job store.

![Eucrante icon](App/Artwork/EucranteIcon.png)

The app uses a bundled, signed `yt-dlp` executable for provider extraction, a bundled Deno runtime for YouTube's JavaScript challenges, a minimal LGPL FFmpeg build for VP9 decoding, and Apple frameworks for HEVC encoding, inspection, merging, notifications, Finder integration, and Music import. Eucrante means “bringer of fulfillment” and is named for a Nereid of successful voyages.

## Current product

- Four one-click Apple output policies: Music Best, Music Efficient, Video Best, and Video Efficient.
- Local YouTube downloads with a private YouTube sign-in inside Eucrante; no sign-in is needed for other supported providers.
- YouTube Premium formats are requested from the same app and Mac network context; Eucrante never reads another browser's files.
- H.264 through 1080p is merged with AAC locally without generation loss.
- 1440p and 4K VP9 sources are converted locally to Apple-native HEVC/H.265 with VideoToolbox hardware acceleration when available and Apple's software fallback otherwise; compatible AAC is copied without another lossy audio encode.
- Finished files are inspected before the job is marked complete.
- Local queue/history, cancellation, retry, custom output folder, Finder reveal, Trash, notifications, and explicit Music import.
- Filename-style previews in Settings that match the actual saved names.
- No analytics or advertising SDKs.

Eucrante does not bypass DRM or access controls. Use it only for media you own or are legally permitted to save, and follow the provider's terms.

## Build

Requirements: macOS 14 or newer, full Xcode, and the Swift 6 toolchain. `make app` creates a native bundle for the build Mac and verifies that every bundled helper supports that architecture; release archives declare their architecture explicitly.

```sh
swift test -Xswiftc -warnings-as-errors
./Scripts/check-coverage.sh 47 8
swift run EucranteCoreChecks
make app
```

`make app` downloads the exact pinned helper releases, verifies their SHA-256 checksums, builds FFmpeg 9.0.1 from its verified official source with GPL and non-free components disabled, embeds the tools under `Eucrante.app/Contents/Resources/Tools`, signs the nested executables, and then signs the app. Development copies live only under `.build/eucrante-tools` and are not committed.

For the opt-in live YouTube check:

```sh
EUCRANTE_E2E_URL='https://www.youtube.com/watch?v=…' \
swift run EucranteCoreChecks
```

Add `EUCRANTE_E2E_4K=1` to exercise the VP9-to-HEVC 4K path. Developers may pass a temporary Netscape cookie file with `EUCRANTE_E2E_COOKIE_FILE`; the shipping app creates and immediately deletes its own file from its private WebKit session.

## Architecture and product notes

- [Architecture](Docs/ARCHITECTURE.md)
- [Product contract](Docs/PRODUCT.md)
- [Preset policies](Docs/PRESETS.md)
- [YouTube Premium boundary](Docs/YOUTUBE-PREMIUM.md)
- [Release process](Docs/RELEASING.md)
- [Security policy](SECURITY.md)
- [Privacy](PRIVACY.md)

## License

Original Eucrante source and documentation are licensed under [Apache License 2.0](LICENSE). Bundled helpers retain their own licenses; see [Third-party notices](THIRD_PARTY_NOTICES.md).
