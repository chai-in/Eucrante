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
3. Select a preset to see its codec, container, quality, and exact or estimated size. Selection does not start a download.
4. Optionally open Music metadata to provide title, artist, album details, or local artwork.
5. Choose a time range and cover treatment, then press Save with Music — Best, Music — Efficient, Video — Best, Video — Efficient, or Custom.
6. Eucrante creates a local job, downloads to its private staging directory, merges or converts when needed, and verifies the result.
7. Reveal the file in Finder, open it, move it to Trash, or explicitly import audio into Music.

Preview probes use the same bundled downloader and private website session as the final save. They are debounced, cancelled when the link changes, and never routed through a Eucrante service. A tilde marks output size that must be estimated because the provider omitted a byte count or Eucrante will convert the selected stream.

For Music presets, provider title, artist, album fields, and artwork are captured automatically. Source album artwork is used when exposed; otherwise the best available thumbnail becomes the cover. Optional manual values override only the fields the user supplied. Chosen and provider artwork is normalized and retained in Eucrante's private app data until the job is removed from history. Importing into Music sets library metadata and artwork without changing or re-encoding the downloaded audio.

## Safari page button and review

Use **Safari button…** in Save to open the local setup page, then drag **↓ Eucrante** into Safari Favorites. Clicking it on a page sends HTTP(S) media links and titles to the app using its registered URL scheme. No server, browser cookie access, Safari developer settings or extension signing is required. The picker verifies candidates using the existing private downloader, in bounded, site-isolated batches, with streaming full-format results and bounded request/batch lifetimes. Only verified items can be selected. Hover or keyboard focus shows source identity, duration, format and exact/estimated sizes; clicking opens the editor without downloading.

The scan covers the current page, media elements, supported-provider links and direct media links exposed in the DOM, capped at 100 unique items and 55 KB. Unloaded infinite-scroll items, blob URLs, protected media and browser pages are not extractable. Sites can block bookmarklets. Unknown sizes are explicitly unavailable, never guessed as exact. Authentication failures name the affected site and offer Reconnect. Done automatically rechecks affected items. Public results are cached for two minutes; failed results for 30 seconds, with an explicit Retry Unavailable action. Session changes invalidate that site's cache.

A known duration opens the visual trim editor: drag either edge, click to inspect a position, type exact times, or use Set start/end here. Zoom, pan, Fit selection and Full view make long clips manageable. Focused handles support one-second arrow-key steps and 0.1-second Shift steps. Reset restores the full source; changing sources clears the range. Preview selection streams a separate low-bandwidth preview and stops at the selected end. Audio uses the same controls with cover art.

Thumbnails load progressively from provider storyboards, falling back to sampled remote frames when available. The hover/boundary preview is labelled approximate; timestamps determine the save range. Preview resources are resolved only for the selected item, never during page scanning. Unsupported or inaccessible streams report preview unavailability without blocking timestamp-based trimming. Refresh preview reacquires expiring stream links. Final save quality remains independent of preview quality.

Start/end fields accept seconds, `m:ss`, or `h:mm:ss` including fractional seconds. The full source downloads before local trimming; full-source size previews are not clip-size promises. Bounds are checked both at submission and against the acquired file.

Square covers offer Original, White, Black, From artwork, and Edge gradient. Non-original styles fit the artwork inside a square without cropping its content. Optional conservative black-bar detection removes only paired uniform dark borders. Edge gradient derives separate spatial colour profiles from each adjacent edge and broadens them into the empty border; it never blurs the artwork itself. Preview and saved cover use the same renderer, with existing 2048-pixel/90%-JPEG normalization. M4A saves embed title, artist, album and cover before publication; Music import also applies the full stored music metadata.

Malformed M4A timelines are compared with Core Audio's packet-derived duration and rebuilt from unchanged compressed packets when they disagree. This fixes doubled-duration fragmented AAC without a lossy encode. Audio-only outputs are fully decoded before publication to reject empty/silent tracks and duration mismatches. Downloads and existing Music library files are never overwritten by repair.

## Queue and file ownership

Saves run in first-in, first-out order, up to the configured concurrency limit. Pausing holds waiting jobs while running jobs finish. A save records its preferences and output-folder bookmark when submitted; changing Settings does not change queued or retried saves. Cancellation remains active until its worker exits, and delayed progress from an earlier attempt cannot alter a retry or completed job.

Conversion and verification happen in a private temporary folder beside the destination. Only a verified, playable file is moved into its final name, without replacing existing files. Once that move succeeds, completion wins a simultaneous cancellation so the queue accurately reports the retained file.

History migrates from the latest existing v2 or v1 file into `jobs-v3.json`, retaining earlier files for rollback. Newer unknown schemas are never overwritten. The v3 snapshot includes immutable save settings, time ranges, expected source duration and cover choices, so older builds cannot retry clips as full downloads. Clearing history removes the current history and cached artwork, not downloaded files or the retained migration copy.

## YouTube Premium

Website sign-in is optional and available for the current link's website in the app's private WebKit browser. The browser shows the actual destination and supports HTTPS identity-provider redirects. A saved cookie is labelled “Session saved”; only successful extraction or a completed save earns “Access verified”. Authentication failures produce a website-specific reconnect prompt in the picker, editor, and queue. Finishing login rechecks the affected work without discarding the selected link or saved job settings. A 403, network error, unsupported URL, rate limit, or DRM restriction receives its own explanation instead of indiscriminate sign-in advice.

Eucrante never requests another browser's private files. Applicable cookies are exported only to the local downloader, in permission-restricted temporary files, and removed after use. Removing a session clears that website, preserving other website sessions. Many yt-dlp websites are supported, including social and adult sites where the engine exposes compatible media; this is not a guarantee for every site, login flow, codec, or protected stream. Combined social-video MP4s can be saved as video or have their AAC track extracted for a music save. Premium membership does not guarantee that a distinct Premium format exists.

## Definition of done

- A fresh app build includes verified local helpers and needs no infrastructure setup.
- The exact live YouTube fixture completes through acquisition, local merge, and AVFoundation inspection.
- Cancellation stops the child process and a retry uses the same opaque staging boundary.
- Diagnostics contain tool readiness, the count of verified website sessions, preferences, and state counts, but no source URLs, cookies, media, or personal output paths.
