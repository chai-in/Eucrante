## Outcome

Describe the user-visible or developer-visible result.

## Changes

-

## Verification

- [ ] `swift format lint --recursive Sources Tests Package.swift`
- [ ] `swift test`
- [ ] `swift build -Xswiftc -warnings-as-errors`
- [ ] `swift run EucranteCoreChecks`
- [ ] `make app` when packaging or UI behavior changed

## Safety and licensing

- [ ] No credentials, private URLs, personal filenames, signing material, or downloaded media are included.
- [ ] New media fixtures are original, openly licensed, or authorized for redistribution.
- [ ] No upstream Cobalt source code, branding, mascots, or artwork was copied.
- [ ] Security, privacy, API, and user-facing documentation was updated where applicable.
