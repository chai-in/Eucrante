# Roadmap

## Working now

- Native SwiftUI app shell and four Apple-oriented one-click policies.
- Local pinned `yt-dlp`, Deno, and reproducibly built LGPL FFmpeg helper installation, embedding, and nested code signing.
- Optional private in-app YouTube session with no external-browser dependency.
- Lossless local H.264 + AAC through 1080p, plus VP9-to-Apple-hardware-HEVC for verified 4K SDR output.
- AVFoundation inspection, output verification, cancellation, queue/history, Finder, Trash, notifications, and Music import.
- Exact local YouTube end-to-end developer check.

## Before the first public binary

- Add process-runner fixture tests for progress, cancellation, malformed output, and browser argument construction.
- Add a clean-machine UI test for first launch, browser consent, folder permission, Music automation, and relaunch recovery.
- Add update provenance and a signed release-feed policy.
- Run licensed SDR/HDR and mono/stereo/multichannel media fixtures.
- Publish notarized arm64 and x86_64 artifacts or clearly document the supported architecture.

## Later

- Verified AV1 input and HDR/color-metadata preservation after licensed fixtures pass.
- Metadata and artwork editing with before/after previews.
- Additional providers only after their local extraction and legal boundaries are tested.
