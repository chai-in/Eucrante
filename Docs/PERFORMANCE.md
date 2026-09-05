# Performance and resource usage

Eucrante runs locally. There is no media backend to tune: the hosted component is a static Cloudflare website. These changes reduce overhead while preserving selected media quality, FIFO scheduling, cancellation, output verification, history migration, and private provider sessions.

## Deeper pass, 2026-09-05

This pass starts from the earlier optimization below. These are additional measurements on the same development Apple silicon Mac, using disposable fixtures and optimized Swift builds targeting macOS 14. They isolate specific operations; they are not whole-app or real-provider guarantees.

| Check | Previous pass as baseline | Deeper pass | Result |
| --- | ---: | ---: | --- |
| Signed yt-dlp `--version`, median of five fresh private homes | 5.650 s | 0.529 s | 91% shorter launch |
| Temporary Python runtime materialized during a launch | 74,183,219 bytes | 0 bytes | No per-launch extraction |
| Installed signed downloader payload | 38,000,912 bytes | 46,690,749 bytes | **8.7 MB more installed space** |
| Compressed downloader payload, `ditto -c -k --keepParent` | 37,565,752 bytes | 24,424,493 bytes | 35% smaller archive |
| 20 durable changes, 2,000-job fixture | 0.435 s | 0.151 s | 65% less time |
| 20 unchanged saves, same fixture | 0.391 s | 0.000059 s | No encoding or replacement writes |
| History bytes, same fixture | 855,568 | 855,568 | Exact JSON representation retained |
| Five bounded 4 MiB artwork transfers | 0.507 s | 0.106 s | 79% less elapsed time |
| Process user CPU for those transfers | 0.48 s | 0.09 s | 81% less user CPU |
| Extra merged movie before an 8-second 1080p Efficient export | 9,131,722 bytes | 0 bytes | One full media write removed |
| Initial website resources, before HTTP compression | 54,533 bytes | 51,944 bytes | Further 4.7% reduction |

The helper comparison uses the old and new signed packaged helpers. Launch timings were collected without directory polling; extraction size was sampled separately. Timing ranges were 5.49–15.19 seconds before and 0.42–0.85 seconds after, so cold-cache and OS effects remain visible. The installed-space increase buys less temporary storage, less repeated decompression and fewer helper processes. The onedir ZIP remains the same upstream yt-dlp version, `2026.07.04`; all extractor code and runtime dependencies remain present. Only unused Intel slices and duplicate framework copies are removed. Deno and the restricted FFmpeg build retain their versions and capabilities.

The row cache retains at most 4 MiB of serialized history plus one associated snapshot/index; it falls back to normal encoding for larger libraries. This is a bounded RAM tradeoff for keeping durable UI transitions short. Whole-process peak RSS on the history fixture was 22.13 MB before and 21.86 MB after; no general RAM reduction is claimed. This fixture includes titles and artists and therefore differs from the earlier 777,568-byte fixture. Both encoders produce identical sorted v2 JSON, including edits, insertion, reordering, and removal. Reopened current histories also avoid an unnecessary startup rewrite.

Artwork transfer uses a local URLProtocol supplying 64 KiB chunks and exercises the existing HTTPS, MIME, response-size, cancellation, and byte-integrity boundaries. It measures the transfer loop, not Internet throughput or image encoding. Native URLSession task delegates retain the shared ephemeral session's connection reuse. ImageIO remains capped at 2048 pixels and 0.90 JPEG quality. Music import now preserves an already-normalized JPEG instead of encoding it again, and artwork preparation runs away from the main actor.

The video fixture contains generated 1920×1080 H.264 and AAC tracks, eight seconds long. Before and after use the same Apple HEVC export preset and produce 12,315,022-byte outputs. The synthetic high-entropy source is deliberately challenging and is not evidence that every HEVC output is smaller. Median export times were 1.516 and 1.567 seconds: **no speed improvement is claimed for this SSD fixture**. The gain is removal of the 9.13 MB intermediate write. Source tracks now remain until export ends, so this does not establish a lower overall peak staging size. Final track, duration, and dimension checks still precede atomic publication. VP9 hardware decoding was reported unavailable on this Mac; the established software decode / VideoToolbox encode path is unchanged.

### Verification of the deeper pass

- 80 native tests passed; line coverage was 92.63% in core and 85.18% in the app, above the 92%/83% floors. Three packaging tests additionally reject cache tampering, changed permissions, external aliases, bad archive hashes, and archive traversal.
- The actual packaged downloader passed a local HTTP fixture driven through `LocalMediaAcquirer`: exactly one preview launch, one acquisition launch, one GET per track, and matching downloaded bytes. Its 1,752-entry extractor inventory also matches the previous signed helper exactly. A local info document supplies formats, so this is not a live-provider extraction test. No private session was used.
- `make check`, strict Swift formatting, script validation, static-site checks, and the pinned Wrangler deployment dry run passed. CSS uses the already-installed esbuild version, now declared directly; the site has no added runtime JavaScript, fonts, or network dependencies. The resource budget is now 52 KiB.
- Native UI inspection observed a disposable save complete with a collision-safe filename, another save stay queued while paused, and completion after resuming. Queue progress, file actions, and layout were visible. The app tests also render compact and wide layouts. No personal library or Music import was used for these checks.
- Browser inspection at desktop width and 390 pixels confirmed rendering, loaded 128px icons, and no horizontal overflow. This used a local static server; no production cache or field Core Web Vitals measurement is claimed.
- A Release bundle passed the nested-library/arm64/entitlement/signature audit and real helper launches. A portable ZIP round trip preserved framework symlinks and passed the same audit from a different directory. The checked ZIP was 67,891,184 bytes. This is local ad-hoc signing evidence, not notarization or a published release.

The remaining dominant costs are provider-selected media bytes, provider/challenge latency, required media decoding/encoding, and durable filesystem synchronization. FIFO/concurrency limits, progress coalescing, private per-attempt environments, stale-preview suppression, and atomic recovery were retained. Preview extraction is deliberately not persisted as a reusable signed-media-URL cache. No media quality reduction, history retention limit, background media service, production deployment, or notarized release is introduced.

### Reproducing the fixtures

`Scripts/measure-history.swift` compiles with the core sources using `swiftc -O -target arm64-apple-macosx14.0 -parse-as-library`. Run the same harness against a retained pre-change source snapshot for comparisons. It creates and removes a private temporary library.

`Scripts/measure-media.swift` compiles the same way. Pass a disposable directory followed by `create`, then run `before` and `after` against those generated tracks. Creation is excluded from the measurements, and each run removes only its own output directory.

`Scripts/measure-artwork-download.swift` compiles with `ArtworkStore.swift` after omitting that file's module import, plus `SecureCredentialFile.swift`. It measures five synthetic 4 MiB chunked responses without network access.

Compile `Scripts/check-downloader.swift` with the core sources, then run `python3 Scripts/check-downloader.py <app-bundle> <generated-media-directory> <compiled-check>`. The Python harness serves only copied fixture media on a temporary loopback port, supplies a local info document, checks request counts, and deletes its private workspace on exit. It does not access browser sessions or provider accounts.

## Earlier pass measurements

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
- At that stage, `npm run build` checked asset hashes, references, cache rules, required release guidance, the 128px icon, absence of JavaScript, and a 60 KiB initial-resource budget. Wrangler's deployment dry run passed. Its local emulator could not start on this Mac (`spawn Unknown system error -88`), so browser inspection used a local static server; no emulator or production cache measurement is claimed.

APFS clone savings depend on the destination filesystem; other filesystems retain the normal copy path. Total download bandwidth still depends mainly on the provider's selected media bitrate. Tool payloads remain pinned and verified, and finished files/history are not automatically deleted. These changes do not establish a notarized release or a production website deployment. Real-provider throughput, whole-app idle RAM, and field Core Web Vitals were not benchmarked.

Run the normal local checks with `swift test -Xswiftc -warnings-as-errors`, `./Scripts/check-coverage.sh 92 83`, `make check`, `npm run build`, and `make app`. Use `make preview` for a disposable native fixture session.
