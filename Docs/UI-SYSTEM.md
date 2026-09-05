# UI system

Eucrante uses native SwiftUI controls, system materials, semantic colors, keyboard navigation, VoiceOver labels, Dynamic Type where available, and reduced-motion-friendly transitions.

## Main screen

- One prominent link field.
- Once a valid link resolves, show a compact thumbnail, title, creator, duration, and format count directly beneath it. Loading and sign-in-required states stay in the same space.
- Four equally weighted one-click Apple output buttons.
- Preset names stand on their own before a preview resolves. Afterward, add one compact factual line for the selected codec, container, quality, and exact or estimated size.
- Keep the optional Music metadata editor collapsed beneath the preset grid. After preview resolves, empty controls show the exact automatic source values and artwork that will be imported; unavailable values read `Auto — None fetched`, and typed values remain explicit overrides. It may override title, artist, album, album artist, composer, genre, year, track, disc, and artwork without making one-click saves wait for a separate screen.
- Custom controls remain collapsed until requested.
- The output folder is always visible.
- The save surface is an unframed native layout; preset buttons have stable dimensions and factual quality labels.
- Queue provides search, All/In Progress/Saved/Needs Attention filters, pause/resume, and visible open, Finder, Music import, retry, and overflow actions.
- Cancelled workers show Cancelling until they exit. Missing local files are distinguished from available saved files.
- Starting an output reveals a persistent bottom shelf with the active preset, phase, progress, Queue, and Cancel controls; completion leaves a concise saved-file confirmation.
- No Eucrante account, hosted server, endpoint, or infrastructure concepts appear in the UI; optional provider sign-in remains explicit.

## YouTube settings

- Show whether the embedded local tools are ready.
- Show a single **Sign In to YouTube** action backed by Eucrante's private in-app WebKit session.
- Provide **Sign Out of Eucrante** to remove the app-owned WebKit session.
- In the sign-in sheet, provide **Open Passwords** for a Touch ID-protected copy/paste flow. Do not claim `webcredentials` association with Google/YouTube or read credentials into Eucrante; Apple suppresses automatic suggestions for unassociated third-party web views as an anti-phishing boundary.
- When the session is ready, replace YouTube's account page with one native connected state. Show the embedded account chooser only when sign-in or account switching is needed.
- Keep the sign-in sheet chrome to one compact toolbar; do not repeat setup explanations around the website.
- Never describe sign-in as a password import or claim a Premium format exists when the provider did not expose one.

## Status language

Use concrete phases: Preparing, Downloading, Optimizing for Apple devices, Checking the finished file, Completed. Errors should say what the user can do next without exposing provider URLs, helper output, or credentials.
