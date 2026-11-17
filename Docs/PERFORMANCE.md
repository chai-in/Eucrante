# Performance and resource usage

Eucrante runs locally. There is no media backend to tune: the hosted component is a static Cloudflare website. These changes reduce overhead while preserving selected media quality, FIFO scheduling, cancellation, output verification, history migration, and private provider sessions.

## Local measurements

Measured on the development Apple silicon Mac on 2026-09-05, comparing the working tree before and after this optimization. Synthetic fixtures isolate the changed paths; these are not overall app or real-provider speed guarantees.

| Check | Before | After | Result |
| --- | ---: | ---: | --- |
| Initial website resources, before HTTP compression | 131,979 bytes | 54,533 bytes | 59% smaller |
| History snapshot with 2,000 synthetic completed jobs | 1,057,582 bytes | 777,568 bytes | 26% smaller |
| 20 durable changes to that history, optimized Swift build | 0.881 s | 0.414 s | 53% less time |
| 20 unchanged history saves, optimized Swift build | 0.876 s | 0.363 s | 59% less time; no replacement writes |
| Artwork normalization peak process RSS | 254,279,680 bytes | 67,895,296 bytes | 73% less peak memory |
| Normalized JPEG size for that artwork | 376,265 bytes | 44,969 bytes | 88% smaller |
| Helper launches for separate video/audio acquisition | 2 | 1 | One shared provider extraction |

The artwork benchmark reads a synthetic 6000×4000 PNG in separate optimized processes and measures RSS with `/usr/bin/time -l`. The new result has a maximum 2048-pixel edge and uses 90% JPEG quality instead of 95%; this intentionally trades excess cover-art resolution for lower RAM and storage use. It does not change downloaded audio/video quality. Artwork gains vary by source size and format.

The initial website budget includes HTML, CSS, and the shared icon. The Open Graph image is requested by social crawlers and is excluded from page-load bytes. The browser inspection confirmed the 128px image rendered correctly at 38px and 30px and was reused for the second occurrence. The site has no JavaScript or external fonts. Fingerprinting prevents stale cached assets when a deployment changes their content.

## Verification and boundaries

- Native tests cover acquisition branches, stale progress, FIFO and concurrency, cancellation, private cookies, persisted completion, external history changes, oversized artwork responses, thumbnail dimensions, and repeated previews.
- A 10,000-sample progress burst verifies that delivery is coalesced and completion remains durable.
- The actual pinned yt-dlp binary was exercised against a disposable local HTTP fixture. Preview plus acquisition used exactly two helper launches in total, and acquisition made exactly one GET for each track. Both downloaded files matched their source bytes. This checks the real helper's output-template and multi-format behavior without using a personal provider session.
- Native compact/wide rendering and the built static website are checked visually. Release packaging separately verifies nested tools and code signatures.
- `npm run build` checks asset hashes, references, cache rules, required release guidance, the 128px icon, absence of JavaScript, and a 60 KiB initial-resource budget. Wrangler's deployment dry run passed. Its local emulator could not start on this Mac (`spawn Unknown system error -88`), so browser inspection used a local static server; no emulator or production cache measurement is claimed.

APFS clone savings depend on the destination filesystem; other filesystems retain the normal copy path. Total download bandwidth still depends mainly on the provider's selected media bitrate. Tool payloads remain pinned and verified, and finished files/history are not automatically deleted. These changes do not establish a notarized release or a production website deployment. Real-provider throughput, whole-app idle RAM, and field Core Web Vitals were not benchmarked.

Run the normal local checks with `swift test -Xswiftc -warnings-as-errors`, `./Scripts/check-coverage.sh 92 83`, `make check`, `npm run build`, and `make app`. Use `make preview` for a disposable native fixture session.

## Safari picker measurements — 21 September 2026

Full extraction was compared on the same 64 public YouTube links on this Apple silicon Mac. The original two-worker strategy was reconstructed with the same pinned yt-dlp engine and fresh per-item directories. It printed only the metadata fields required for measurement, while still performing full format extraction. The updated measurements ran the actual `PagePickerModel` and `LocalMediaAcquirer` in the app test target, with a new, empty result cache and no login cookies on each run. No flat playlist or title-only result was counted as verified.

| Work | Original strategy | Updated app, run 1 | Updated app, run 2 |
| --- | ---: | ---: | ---: |
| All 64 links resolved | 205.44 s | 15.73 s | 17.39 s |
| Playable / login-required items | 63 / 1 | 63 / 1 | 63 / 1 |
| Full-scan speedup | — | 13.06× | 11.81× |
| First playable result | about 6 s | 9.33 s | 11.27 s |
| Immediate repeat, all results already checked | full scan again | 0.82 ms | 0.98 ms |

The improvement is in full-page completion and repeated scans. Starting more helpers can delay the first result; it does not make the provider's first request ten times faster. An initial 24-link experiment improved from 81.96 to 13.60 seconds with twelve batch workers (6.03×). Twenty-four simultaneous independent processes were slower (25.34 seconds), so that approach was rejected. The final implementation caps concurrency at sixteen processes, batches at eight same-site URLs, and cached results at 256. It uses full formats, includes unavailable items' real reasons, and never caches signed media URLs or cookies. Cache lifetimes are two minutes for success and 30 seconds for failures; session changes and explicit retries invalidate affected entries.

These are local benchmark results, not a universal 10× guarantee for small pages, every provider, every network, or cold first-item latency. A successful scan verifies extraction and matching media formats; the final save still performs fresh acquisition and file validation.

Evidence and inputs are in `Docs/Benchmarks/page-scan-*.json` and `Docs/Benchmarks/page-scan-urls.txt`. Reproduce the old strategy with:

```sh
python3 Scripts/benchmark-page-scan.py --output /tmp/eucrante-baseline.json
```

Run the shipping model against those same inputs with:

```sh
EUCRANTE_SCAN_INPUT="$PWD/Docs/Benchmarks/page-scan-urls.txt" \
EUCRANTE_SCAN_EXPECTED=63 EUCRANTE_SCAN_OUTPUT=/tmp/eucrante-scan.json \
swift test --filter PageScanBenchmarkTests
```

The live test is skipped by ordinary test runs. Provider availability can change, so inspect the reported unavailable items as well as timing. The tested unavailable video was the same one in the baseline and updated runs.
