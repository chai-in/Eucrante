# Product contract

Eucrante should feel like a normal Mac utility: paste, choose an output, and save. Setup must never require a cloud account, server, terminal, network tunnel, or second computer.

## Principles

1. One app and one visible workflow.
2. Provider traffic and optional browser authentication stay on the user's Mac.
3. Apple-oriented defaults explain quality and storage tradeoffs in plain language.
4. A successful state means the final local file was opened and verified.
5. No DRM bypass, analytics, advertising, shared backend, or project account.

## Primary flow

1. Paste or share an HTTP/HTTPS media link.
2. Choose Music Best, Music Efficient, Video Best, Video Efficient, or Custom.
3. Eucrante creates a local job, downloads to its private staging directory, merges or converts when needed, and verifies the result.
4. Reveal the file in Finder, open it, move it to Trash, or explicitly import audio into Music.

## YouTube Premium

Browser use is explicit and off by default. Choosing Brave, Chrome, Firefox, or Safari authorizes the local helper to read that browser's signed-in session and present applicable cookies only to the selected provider for the requested download. Eucrante has no service that receives them and does not log or persist them. Premium membership does not guarantee that every video exposes a distinct Premium-labelled format.

## Definition of done

- A fresh app build includes verified local helpers and needs no infrastructure setup.
- The exact live YouTube fixture completes through acquisition, local merge, and AVFoundation inspection.
- Cancellation stops the child process and a retry uses the same opaque staging boundary.
- Diagnostics contain tool/browser choices and state counts, but no source URLs, cookies, media, or personal output paths.
