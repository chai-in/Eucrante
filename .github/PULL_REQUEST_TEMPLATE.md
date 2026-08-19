## Outcome

Describe the user-visible or developer-visible result.

## Changes

-

## Verification

- [ ] `swift format lint --strict --recursive Sources Tests Package.swift Scripts/render-app-icon.swift`
- [ ] `./Scripts/check-coverage.sh 58 16`
- [ ] `swift build -Xswiftc -warnings-as-errors`
- [ ] `swift run EucranteCoreChecks`
- [ ] `make app` when packaging or UI behavior changed

## Safety and licensing

- [ ] No browser data, cookies, private URLs, personal filenames, signing material, or downloaded media are included.
- [ ] New media fixtures are original, openly licensed, or authorized for redistribution.
- [ ] New or updated executables have pinned hashes, compatible licenses, and reviewed provenance.
- [ ] Security, privacy, architecture, and user-facing documentation was updated where applicable.
