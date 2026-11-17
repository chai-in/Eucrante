# Work to resume

Snapshot: 17 November 2026. “Implemented in source” means code and supporting tests/docs are present, not that the original user scenario has been proven fixed in this migration run.

## First continuation

- [ ] Recover or reproduce the final preview-success/save-failure report on a Mac. Its original URL and diagnostic error are absent from the prompt cache. Inspect `LocalMediaAcquirer`, `DownloadPipeline`, `SiteSessionStore`, `SiteRecoveryTests` and `LiveDownloadVerificationTests`; preserve the selected format, session, time range and metadata from preview through final acquisition.
- [ ] Verify the original silent/wrong-duration M4A case using an available permitted fixture. `AudioContainerRepair` and output audio decoding are implemented; the exact original case has no recovered completion reply.
- [ ] Complete native validation and capture UI/assistive verification for the picker, trim handles, zoom/pan, approximate thumbnails, selection playback and site reconnect states. Preserve the intentional distinction between preview quality and saved quality.
- [ ] Bring meaningful native coverage to the existing floors: core measured 87.05% against 92%; app measured 74.91% against 83%. Ordinary tests/build/format/core checks pass. Do not lower the thresholds; see [VALIDATION.md](VALIDATION.md).
- [ ] Compare the preserved source against `codex/resource-optimization` (`1f719942e565cec1b04bee4b7cf97bf0ca2eb871`). Some work overlaps the local snapshot; do not blindly cherry-pick duplicate changes.
- [ ] Review `licensing/gpl-3` (`27f442552d8bc508d14fab0aa5a20a0dd7367489`) as a separate pending branch. This migration retains the current main/source licensing and does not decide that proposal.
- [ ] Review the Harbor release integration against the existing release/repository documentation. The preserved workflow is tag/manual-triggered; no release has been run here. Existing repository notes say GitHub Actions workflows are not used, so reconcile that documentation with the new integration before enabling it.

## Existing implementation to retain

- Safari Favorites button and bounded, verified media picker: `SafariPageButton`, `PagePicker.js`, `PagePickerModel` and browser/native picker tests.
- Full-scan optimization and cached results: historical 64-link runs recorded 13.06× and 11.81× completion speedups; first-result latency was slower. Do not promise a universal tenfold speedup. Benchmark JSON and inputs are preserved.
- Trim handles, exact timestamps, zoom/pan, thumbnails and selection playback: `TrimEditorView`, `TrimPreviewModel`, `TrimTimelineGeometry`, `TimelineMedia` and related tests.
- Square cover treatments and Music metadata: `CoverEditor`, `CoverRenderer`, `CoverStyle`, `MusicMetadataEditor` and cover/save-editing tests.
- Site-specific private sessions, truthful auth diagnostics and reconnect/recheck: `SiteSessionStore`, `SiteSignInView`, `MediaSite` and diagnostics/recovery tests.
- HEVC conversion where required, immutable per-job options, FIFO/concurrency, cancellation/retry and v3 persistence: core acquisition/processing, `DownloadQueue`, `DownloadPipeline`, `DownloadWorkspace` and `JobStore`.

## Existing roadmap and repository work

Carry forward [ROADMAP.md](../ROADMAP.md), particularly clean-machine first launch/permissions/relaunch recovery, licensed SDR/HDR and channel-layout fixtures, first reviewed public preview, future notarized distribution, and either a reviewed signed update feed with key recovery or automatic updates remaining disabled. AV1/HDR guarantees, batch metadata/templates and new-provider guarantees remain future work.

Open pull requests at discovery:

- [#1: GitHub Actions dependency group](https://github.com/chai-in/Eucrante/pull/1).
- [#2: Wrangler dependency group](https://github.com/chai-in/Eucrante/pull/2).
- [#3: sharp and Wrangler](https://github.com/chai-in/Eucrante/pull/3).
- [#5: undici and Wrangler](https://github.com/chai-in/Eucrante/pull/5).

No open issue records or tagged GitHub releases were returned. These PRs are inventory, not merge instructions; refresh their status and identify overlapping updates before acting.

## Migration completion, once the host is supplied

- [ ] Identify/link the owner's Linux T3 Code environment and chosen project path.
- [ ] Refresh the snapshot to include intervening work.
- [ ] Reconcile any unique changes in the older Windows mirror; its disk state was not accessible in this run.
- [ ] Transfer the private history/artifact bundle separately and verify its checksums.
- [ ] Clone the migration branch and register the project with portable build/test scripts.
- [ ] Supply the local-backup design instructions/reference guide to the destination agent.
- [ ] Run portable checks on the actual Linux machine, then establish an available Mac validation route.
- [ ] Reconcile any recovered Desktop transcript with the nine-request reconstruction.
- [ ] Confirm source/history/task continuity before retiring old workspaces. No old workspace has been removed by this preparation.
