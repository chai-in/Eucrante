# Roadmap

## Working now

- Native SwiftUI app shell and four Apple-oriented one-click policies.
- Local pinned `yt-dlp`, Deno, and reproducibly built LGPL FFmpeg helper installation, embedding, and nested code signing.
- Private in-app YouTube session with no external-browser dependency, required only for YouTube saves.
- Lossless local H.264 + AAC through 1080p, plus VP9-to-Apple-VideoToolbox-HEVC for verified 4K SDR output.
- AVFoundation inspection, output verification, cancellation, queue/history, Finder, Trash, notifications, and Music import.
- Exact local YouTube end-to-end developer check.
- Signed-bundle audit, branded reproducible app icon, app/core security-boundary tests, and an enforced coverage floor.
- Escalation-tested child-process cancellation, bounded streaming diagnostics, and synchronous atomic job-state persistence.
- Architecture-labelled notarized-release policy with portable checksums and machine-readable provenance.
- Deterministic app-orchestration coverage for verified completion, crash recovery, and authenticated-session cancellation, with ratcheted core/app coverage floors.

## Before the first public binary

- Add a clean-machine UI test for first launch, browser consent, folder permission, Music automation, and relaunch recovery.
- Ship tagged source-only GitHub Releases while the maintainer uses a free Apple developer account.
- If Apple Developer Program membership becomes available, ship notarized GitHub binary releases, then add a project-owned Homebrew Cask after release URLs and architecture coverage are stable.
- Implement a separately reviewed signed Sparkle update feed and signing-key recovery policy or keep automatic updates disabled; release provenance is already generated.
- Run licensed SDR/HDR and mono/stereo/multichannel media fixtures.
- Produce and clean-machine test the first notarized architecture-labelled artifact; source/build architecture policy is documented.

## Later

- Verified AV1 input and HDR/color-metadata preservation after licensed fixtures pass.
- Metadata and artwork editing with before/after previews.
- Additional providers only after their local extraction and legal boundaries are tested.
