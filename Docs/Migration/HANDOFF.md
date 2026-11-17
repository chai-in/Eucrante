# Eucrante: Linux T3 Code handoff

Prepared 17 November 2026. Destination environment is deliberately unspecified until the owner supplies it. This is a development migration of the existing native Mac project; no Linux app port has been requested.

## What this branch preserves

The local development checkout had 164 existing source/documentation files, two tracked deletions, and substantial uncommitted changes based on `efc5d669005fdb7353211a615d11367f5db5e3c5`, on `codex/apple-silicon-refactor`. The preserved work includes:

- Safari Favorites page scanning and a verified-item picker.
- Time-range editing, zoom, thumbnails and selection playback.
- Square cover treatments, metadata editing and M4A audio validation/repair.
- Site-specific private sign-in, reconnect detection and rechecking.
- Queue/pipeline separation, immutable per-save settings and history migration.
- Resource/performance work, benchmark evidence, website changes, Harbor SDK integration and release tooling.

The initial preservation commit records the original source tree. The following README merge retains the newer public `main` changes (`823feb3` and `8e195a1`) while documenting the local features. The original local checkout remains untouched.

Start with [pending work](TASKS.md), [recovered request history](REQUEST-HISTORY.md), and [validation](VALIDATION.md). Read [PRODUCT.md](../PRODUCT.md), [ARCHITECTURE.md](../ARCHITECTURE.md), [UI-SYSTEM.md](../UI-SYSTEM.md), [ROADMAP.md](../ROADMAP.md), and [PERFORMANCE.md](../PERFORMANCE.md) before changing behavior.

## Start on Linux when the destination is provided

Use a current supported Node release (the migration checks used Node 24.22.1), Git, and Python 3.12+ for the separate local-backup restore tools. These project checks need no npm dependency installation:

```sh
git clone --branch migration/linux-t3-20261117 https://github.com/chai-in/Eucrante.git
cd Eucrante
node --test Tests/Browser/PagePicker.test.mjs
npm run build
```

Register this folder as the Eucrante project in the supplied T3 Code environment. Suggested saved scripts are `node --test Tests/Browser/PagePicker.test.mjs` (test) and `npm run build` (build). Keep setup scripts manual until the chosen host, provider and workspace path are known. There are no Eucrante T3 threads or scheduled tasks in the existing Home-PC project to recreate, and no matching Desktop queue/goals/automation records were found in the inspected local stores.

First continuation prompt:

> Read Docs/Migration/HANDOFF.md, REQUEST-HISTORY.md, TASKS.md and VALIDATION.md. Continue Eucrante's existing native macOS project from this preserved work. Keep the local-first product boundary and distinguish source implementation from verified behavior. Resolve the last reported preview-success/save-failure issue first when its original reproduction is available. Run portable checks on Linux and use an explicitly available Mac for native checks. Do not mark lost conversation history or outstanding release/fixture work complete.

## Keep native validation on a Mac

SwiftUI, AppKit, AVFoundation, AudioToolbox, WebKit, VideoToolbox, Music automation, signing, DMG packaging and notarization require macOS. Installing Swift on Linux does not provide these frameworks. The current app build targets Apple silicon, macOS 14+ and full Xcode.

```sh
swift test -Xswiftc -warnings-as-errors
./Scripts/check-coverage.sh 92 83
swift run EucranteCoreChecks
make app
```

No remote Mac runner, provider authentication, signing identity, website deployment or destination enrollment is created by this handoff. The local backup retains the owner's existing design instructions and the Asterline guide for future UI work; those references must travel with the eventual private transfer.

## History and completeness

The main Codex Desktop development conversation is available locally only as nine cached user prompts, without timestamps or assistant replies. Its full transcript was absent from the current state/history stores, archived rollouts, the available previous export and the inspected Desktop catalogs. The request ledger is a reconstruction from those prompts and source evidence, not a complete conversation export. Earlier implementation discussions may therefore be missing. If the original Desktop conversation is recovered, append it to the private backup and reconcile the task ledger.

A separate local migration bundle preserves the exact working tree, original Git index/refs/reflogs, offline Git bundles, the nine original prompts, a related download transcript, matching historical evidence, saved app job snapshots/artwork, and existing Mac build artifacts. Personal raw transcripts, saved app jobs, browser/login data and binaries are not part of this public handoff. Authentication files and browser sessions were excluded from the bundle too.

Home-PC's T3 registration points to an older Windows checkout. T3 reports no Eucrante threads or schedules there; its actual filesystem could not be inspected from this run because SSH was unavailable. Reconcile that mirror before claiming every machine's local work has been collected.

The migration is prepared, not cut over. After the owner names the Linux environment, transfer the private bundle separately, register the restored/current source folder, verify access and portable checks, connect a Mac validation route, and refresh the final source/history snapshot before retiring any old workspace.
