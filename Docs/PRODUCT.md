# Product contract

Eucrante should feel like a normal Mac utility: paste, choose an output, and save. Setup must never require an Eucrante account, hosted backend, terminal, network tunnel, or second computer.

## Principles

Eucrante supports Apple silicon Macs running macOS 14 or newer.

1. One app and one visible workflow.
2. Provider traffic and optional browser authentication stay on the user's Mac.
3. Apple-oriented defaults explain quality and storage tradeoffs in plain language.
4. A successful state means the final local file was opened and verified.
5. No DRM bypass, analytics, advertising, shared backend, or project account.

## Primary flow

1. Paste or share an HTTP/HTTPS media link.
2. Eucrante locally probes the link and shows its title, creator, artwork, duration, and available formats.
3. Each one-click preset shows its selected codec, container, quality, and exact or estimated size.
4. Optionally open Music metadata to provide title, artist, album details, or local artwork.
5. Choose Music — Best, Music — Efficient, Video — Best, Video — Efficient, or Custom.
6. Eucrante creates a local job, downloads to its private staging directory, merges or converts when needed, and verifies the result.
7. Reveal the file in Finder, open it, move it to Trash, or explicitly import audio into Music.

Preview probes use the same bundled downloader and private YouTube session as the final save. They are debounced, cancelled when the link changes, and never routed through a Eucrante service. A tilde marks output size that must be estimated because the provider omitted a byte count or Eucrante will convert the selected stream.

For Music presets, provider title, artist, album fields, and artwork are captured automatically. Source album artwork is used when exposed; otherwise the best available thumbnail becomes the cover. Optional manual values override only the fields the user supplied. Chosen and provider artwork is normalized and retained in Eucrante's private app data until the job is removed from history. Importing into Music sets library metadata and artwork without changing or re-encoding the downloaded audio.

## Queue and file ownership

Saves run in first-in, first-out order, up to the configured concurrency limit. Pausing holds waiting jobs while running jobs finish. A save records its preferences and output-folder bookmark when submitted; changing Settings does not change queued or retried saves. Cancellation remains active until its worker exits, and delayed progress from an earlier attempt cannot alter a retry or completed job.

Conversion and verification happen in a private temporary folder beside the destination. Only a verified, playable file is moved into its final name, without replacing existing files. Once that move succeeds, completion wins a simultaneous cancellation so the queue accurately reports the retained file.

History migrates from `jobs-v1.json` into `jobs-v2.json`, retaining the original v1 file for rollback. Newer unknown schemas are never overwritten. The v2 snapshot includes immutable save settings and the cancelling state. Clearing history removes the current history and cached artwork, not downloaded files or the retained migration copy.

## YouTube Premium

YouTube sign-in is explicit and off by default. Before creating a YouTube job without a usable session, Eucrante opens its dedicated sign-in window and retains the entered link instead of starting a job that is likely to fail anonymously. The window is backed by the app's private WebKit data store. Eucrante never requests access to Brave, Safari, Chrome, Firefox, or another browser. Applicable cookies are exposed to the bundled downloader only through a permission-restricted per-job file that is deleted immediately after acquisition. Eucrante has no service that receives them and does not log or retain the export. Premium membership does not guarantee that every video exposes a distinct Premium-labelled format.

## Definition of done

- A fresh app build includes verified local helpers and needs no infrastructure setup.
- The exact live YouTube fixture completes through acquisition, local merge, and AVFoundation inspection.
- Cancellation stops the child process and a retry uses the same opaque staging boundary.
- Diagnostics contain tool readiness, whether an in-app YouTube session exists, preferences, and state counts, but no source URLs, cookies, media, or personal output paths.
