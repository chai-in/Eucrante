# Eucrante

Eucrante is a native macOS app for saving media directly on your Mac. There is no Eucrante account, server, localhost service, Cloudflare setup, relay PC, or remote job store.

[Website](https://eucrante-site.tibcon.workers.dev/) · [Documentation](Docs/PRODUCT.md) · [Releases](https://github.com/chai-in/Eucrante/releases)

![Eucrante icon](App/Artwork/EucranteIcon.png)

The app uses a bundled, signed `yt-dlp` executable for provider extraction, a bundled Deno runtime for YouTube's JavaScript challenges, a minimal LGPL FFmpeg build for VP9 decoding, and Apple frameworks for HEVC encoding, inspection, merging, notifications, Finder integration, and Music import. Eucrante means “bringer of fulfillment” and is named for a Nereid of successful voyages.

## Current product

- Four one-click Apple output policies: Music — Best, Music — Efficient, Video — Best, and Video — Efficient.
- Local YouTube downloads with a private YouTube sign-in inside Eucrante; no sign-in is needed for other supported providers.
- YouTube Premium formats are requested from the same app and Mac network context; Eucrante never reads another browser's files.
- H.264 through 1080p is merged with AAC locally without generation loss.
- 1440p and 4K VP9 sources are converted locally to Apple-native HEVC/H.265 with VideoToolbox hardware acceleration when available and Apple's software fallback otherwise; compatible AAC is copied without another lossy audio encode.
- Finished files are inspected before the job is marked complete.
- FIFO queue with pause/resume, search, status filters, cancellation, retry, custom output folder, Finder reveal, Trash, notifications, and explicit Music import.
- Each save retains its chosen settings and output folder, including after a relaunch or retry.
- Filename-style previews in Settings that match the actual saved names.
- No analytics or advertising SDKs.

Eucrante does not bypass DRM or access controls. Use it only for media you own or are legally permitted to save, and follow the provider's terms.

## Build

Requirements: an Apple silicon Mac running macOS 14 or newer, full Xcode, and the Swift 6 toolchain. Eucrante supports arm64 only. Run the build natively, outside Rosetta. `make app` builds and verifies an arm64 bundle before replacing the previous local build.

```sh
swift test -Xswiftc -warnings-as-errors
./Scripts/check-coverage.sh 92 83
swift run EucranteCoreChecks
make app
```

`make app` downloads the exact pinned helper releases, verifies their SHA-256 checksums, builds FFmpeg 9.0.1 from its verified official source with GPL and non-free components disabled, embeds the tools under `Eucrante.app/Contents/Resources/Tools`, signs the nested executables, and then signs the app. Development copies live only under `.build/eucrante-tools` and are not committed.

`make preview` opens a Debug build with disposable history, generated audio fixtures, and a non-persistent YouTube session. Media acquisition uses local fixtures and does not open the normal app library. Opening Sign In still contacts YouTube in that temporary session. Release builds do not include the fixture mode.

For the opt-in live YouTube check:

```sh
EUCRANTE_E2E_URL='https://www.youtube.com/watch?v=…' \
swift run EucranteCoreChecks
```

Add `EUCRANTE_E2E_4K=1` to exercise the VP9-to-HEVC 4K path. Developers may pass a temporary Netscape cookie file with `EUCRANTE_E2E_COOKIE_FILE`; the shipping app creates and immediately deletes its own file from its private WebKit session.

## Install

Eucrante has no tagged release yet. Until the first preview appears, clone `main` and build it locally using the steps above. Future public preview DMGs will be attached to [GitHub Releases](https://github.com/chai-in/Eucrante/releases) with matching checksum and provenance files.

The maintainer's free Apple developer account does not include Developer ID distribution or notarization. Preview DMGs are therefore ad-hoc signed, clearly named `*-unnotarized.dmg`, and published as GitHub prereleases. macOS blocks their first launch. This does not require disabling Gatekeeper:

1. Download the DMG and its `.sha256` file from the same GitHub Release.
2. Verify the checksum, open the DMG, and drag Eucrante to Applications.
3. Try to open Eucrante once.
4. Open **System Settings > Privacy & Security**, click **Open Anyway**, then confirm **Open**.

Never disable Gatekeeper and never run a command that removes quarantine attributes. Review the tag, source, checksum, and provenance before approving an unnotarized build.

Verify from the directory containing both downloaded files:

```sh
shasum -a 256 -c Eucrante-*.dmg.sha256
```

If Developer ID and notarization become available later, stable releases will use notarized DMG and ZIP artifacts that open normally. Homebrew Cask support remains deferred until then because Homebrew does not replace Apple signing or notarization.

The project website is deployed as Cloudflare Workers Static Assets. Its Cloudflare build runs `npm run build` to create validated, fingerprinted assets in `dist/site` before `npx wrangler deploy`. Fingerprinted resources use immutable browser caching; HTML revalidates on each visit. Native app checks remain local because Eucrante requires macOS, AppKit, AVFoundation, and Xcode, which are unavailable in Cloudflare's Linux build image.

## Architecture and product notes

- [Architecture](Docs/ARCHITECTURE.md)
- [Performance and resource usage](Docs/PERFORMANCE.md)
- [Product contract](Docs/PRODUCT.md)
- [Preset policies](Docs/PRESETS.md)
- [YouTube Premium boundary](Docs/YOUTUBE-PREMIUM.md)
- [Release process](Docs/RELEASING.md)
- [Repository settings](Docs/REPOSITORY.md)
- [Security policy](SECURITY.md)
- [Privacy](PRIVACY.md)

## License

Original Eucrante source and documentation are licensed under [Apache License 2.0](LICENSE). Bundled helpers retain their own licenses; see [Third-party notices](THIRD_PARTY_NOTICES.md).
