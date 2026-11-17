# UI system

Eucrante uses native SwiftUI controls, system materials, semantic colors, keyboard navigation, VoiceOver labels, Dynamic Type where available, and reduced-motion-friendly transitions.

## Main screen

- One prominent link field.
- Once a valid link resolves, show a compact thumbnail, title, creator, duration, and format count directly beneath it. Loading and sign-in-required states stay in the same space.
- Four equally weighted Apple output choices, followed by an explicit Save action.
- Preset names stand on their own before a preview resolves. Afterward, add one compact factual line for the selected codec, container, quality, and exact or estimated size.
- Keep the optional Music metadata editor collapsed beneath the preset grid. After preview resolves, empty controls show the exact automatic source values and artwork that will be imported; unavailable values read `Auto — None fetched`, and typed values remain explicit overrides. It may override title, artist, album, album artist, composer, genre, year, track, disc, and artwork without making one-click saves wait for a separate screen.
- Custom controls remain collapsed until requested.
- The output folder is always visible.
- The save surface is an unframed native layout; preset buttons have stable dimensions and factual quality labels.
- Queue provides search, All/In Progress/Saved/Needs Attention filters, pause/resume, and visible open, Finder, Music import, retry, and overflow actions.
- Cancelled workers show Cancelling until they exit. Missing local files are distinguished from available saved files.
- Starting an output reveals a persistent bottom shelf with the active preset, phase, progress, Queue, and Cancel controls; completion leaves a concise saved-file confirmation.
- No Eucrante account, hosted server, endpoint, or infrastructure concepts appear in the UI; optional provider sign-in remains explicit.

## Website sessions

- Show local-tool readiness separately from website access.
- Offer **Open Website for Current Link…** and per-site session management. Do not show a blanket sign-in prompt in every window.
- Distinguish saved cookies from checked access. Show **Reconnect [website]** only for actual authentication failures; give network, unsupported-link, rate-limit, access-denied and DRM errors their own explanations.
- Keep unresolved failures per source, so a successful public link cannot hide a private item's login problem.
- Use the embedded private browser for the selected website, display its actual HTTPS destination, and keep **Open Passwords** available without reading the Passwords database or claiming an associated-domain relationship.
- **Done & Recheck** refreshes affected previews, page items and authentication-failed jobs. Do not mark a session connected merely because cookies exist.
- **Remove Session** clears only the selected website and cancels its active saves.
- Keep the immediate custom picker popover for source, duration, format and size details. Do not attach a second delayed system tooltip to the same row.

## Status language

Use concrete phases: Preparing, Downloading, Optimizing for Apple devices, Checking the finished file, Completed. Errors should say what the user can do next without exposing provider URLs, helper output, or credentials.
