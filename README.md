# Eucrante

Eucrante is a native macOS app for saving media directly on your Mac. There is no server, account, localhost service, Cloudflare setup, relay PC, or remote job store.

The app uses a bundled, signed `yt-dlp` executable for provider extraction, a bundled Deno runtime for YouTube's JavaScript challenges, and Apple frameworks for inspection, merging, conversion, notifications, Finder integration, and Music import. Eucrante means “bringer of fulfillment” and is named for a Nereid of successful voyages.

## Current product

- Four one-click Apple output policies: Music Best, Music Efficient, Video Best, and Video Efficient.
- Local YouTube downloads with optional use of a Brave, Chrome, Firefox, or Safari session selected by the user.
- YouTube Premium formats are requested from the same Mac and network context as the selected browser.
- Separate H.264 video and AAC audio tracks are merged locally without generation loss.
- Finished files are inspected before the job is marked complete.
- Local queue/history, cancellation, retry, custom output folder, Finder reveal, Trash, notifications, and explicit Music import.
- Filename-style previews in Settings that match the actual saved names.
- No analytics or advertising SDKs.

Eucrante does not bypass DRM or access controls. Use it only for media you own or are legally permitted to save, and follow the provider's terms.

## Build

Requirements: macOS 14 or newer, full Xcode, and the Swift 6 toolchain.

```sh
swift test -Xswiftc -warnings-as-errors
swift run EucranteCoreChecks
make app
```

`make app` downloads the exact pinned helper releases, verifies their SHA-256 checksums, embeds them under `Eucrante.app/Contents/Resources/Tools`, signs the nested executables, and then signs the app. Development copies live only under `.build/eucrante-tools` and are not committed.

For the opt-in live YouTube check:

```sh
EUCRANTE_E2E_URL='https://www.youtube.com/watch?v=…' \
EUCRANTE_E2E_BROWSER=brave \
swift run EucranteCoreChecks
```

## Architecture and product notes

- [Architecture](Docs/ARCHITECTURE.md)
- [Product contract](Docs/PRODUCT.md)
- [Preset policies](Docs/PRESETS.md)
- [YouTube Premium boundary](Docs/YOUTUBE-PREMIUM.md)
- [Security policy](SECURITY.md)
- [Privacy](PRIVACY.md)

## License

Original Eucrante source and documentation are licensed under [Apache License 2.0](LICENSE). Bundled helpers retain their own licenses; see [Third-party notices](THIRD_PARTY_NOTICES.md).
