# UI system

Eucrante uses native SwiftUI controls, system materials, semantic colors, keyboard navigation, VoiceOver labels, Dynamic Type where available, and reduced-motion-friendly transitions.

## Main screen

- One prominent link field.
- Four equally weighted one-click Apple output buttons.
- Custom controls remain collapsed until requested.
- The output folder is always visible.
- Starting an output reveals a persistent bottom shelf with the active preset, phase, progress, Queue, and Cancel controls; completion leaves a concise saved-file confirmation.
- No server, account, endpoint, or infrastructure concepts appear in the UI.

## YouTube settings

- Show whether the embedded local tools are ready.
- Show a single **Sign In to YouTube** action backed by Eucrante's private in-app WebKit session.
- Explain that Eucrante does not read an external browser and that nothing is uploaded to Eucrante infrastructure.
- Provide **Sign Out of Eucrante** to remove the app-owned WebKit session.
- In the sign-in sheet, provide **Open Passwords** for a Touch ID-protected copy/paste flow. Do not claim `webcredentials` association with Google/YouTube or read credentials into Eucrante; Apple suppresses automatic suggestions for unassociated third-party web views as an anti-phishing boundary.
- Keep the sign-in sheet chrome to one compact toolbar; do not repeat setup explanations around the website.
- Never describe sign-in as a password import or claim a Premium format exists when the provider did not expose one.

## Status language

Use concrete phases: Preparing, Downloading, Optimizing for Apple devices, Checking the finished file, Completed. Errors should say what the user can do next without exposing provider URLs, helper output, or credentials.
