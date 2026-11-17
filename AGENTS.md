# Continuing Eucrante

- Start with `Docs/Migration/HANDOFF.md`, `TASKS.md`, `REQUEST-HISTORY.md` and `VALIDATION.md` in that directory. Keep the distinction between preserved code, historical evidence and newly verified behavior.
- This is a native Apple silicon macOS project. A Linux T3 Code host can edit code and run the portable browser/site checks; native Swift/framework, playback, Music, signing and packaging checks require a Mac.
- Preserve the local-first product contract in `Docs/PRODUCT.md` and the selected-job settings, output verification, cancellation and private-session boundaries in `Docs/ARCHITECTURE.md`.
- For UI changes, follow `Docs/UI-SYSTEM.md` and the owner's Asterline v0.2-or-later-approved design/accessibility guide supplied in the private migration references. Retain native platform behavior, keyboard/focus/assistive routes, both themes and reduced-motion support. Record deliberate platform differences; a passing build does not establish rendered accessibility.
- Read `CONTRIBUTING.md` for native checks. Portable checks are `node --test Tests/Browser/PagePicker.test.mjs` and `npm run build`.
- The main Desktop transcript is incomplete. Do not infer completed work from missing assistant replies, or publish personal raw history, app jobs, cookies, signing material or downloaded media.
