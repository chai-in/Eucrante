# Migration validation

Run on 17 November 2026 in an isolated checkout on Apple silicon, with full Xcode and Swift 6.4.2. The original development checkout was not used for builds and retains its uncommitted work.

Passed:

- `swift test -Xswiftc -warnings-as-errors`: 108 test cases across core and app suites, zero failures; five cases skipped. There were 103 non-skipped cases.
- `node --test Tests/Browser/PagePicker.test.mjs`: three tests passed.
- `npm run build`: static website validation, content hashes, cache rules and initial-resource budget passed (54,533 bytes before HTTP compression).
- `zsh -n Scripts/*.sh`: shell syntax passed.
- `swift format lint --strict --recursive Sources Tests Package.swift Scripts/render-app-icon.swift Scripts/render-dmg-background.swift`: passed.
- `swift build -Xswiftc -warnings-as-errors`: passed.
- `swift run EucranteCoreChecks`: all checks passed.
- Exact local-backup restore into a new folder: all 164 source files matched their SHA-256 records, the original Git status/index state was reproduced, offline bundle verification passed and `git fsck --full` found no corruption. Unreachable Git objects were retained.
- No matches for common credential-token/private-key patterns in the source selected for publication. Raw personal history, app jobs, authentication material and build artifacts were not selected for this public branch.

The five native skips were explicit:

- One fragmented AAC repair fixture needs the checksum-pinned local helper tools installed.
- Two live timeline/preview tests need `EUCRANTE_VERIFY_TIMELINE=1`.
- One existing-job pipeline test needs `EUCRANTE_VERIFY_JOB`.
- One real-provider scan benchmark needs `EUCRANTE_SCAN_INPUT`.

The required `./Scripts/check-coverage.sh 92 83` gate failed for the preserved development source. Its test execution still had zero failures and the same five skips. The exported coverage report measured:

| Target | Covered / total lines | Actual | Required |
| --- | --- | --- | --- |
| EucranteCore | 3,034 / 3,485 | 87.05% | 92% |
| EucranteApp | 5,540 / 7,395 | 74.91% | 83% |

The script stops at the first failing target; both values above were also read from the generated report. Thresholds were not changed. Keep this migration PR as a draft until the required coverage and the remaining validation are addressed.

No helper installation/release bundle build (`make app`), live provider/session checks, visual or assistive-technology review, clean-machine first launch, release signing/notarization, production deployment or actual Linux execution is claimed. Historical scan benchmark results are retained as historical evidence.
