# Release process

Eucrante has no unsigned public binary-release path. A publishable app binary must come from a clean, exactly tagged commit, use a Developer ID Application signature, pass the assembled-bundle audit, be accepted by Apple's notary service, carry a stapled ticket, pass Gatekeeper assessment, and ship with a portable SHA-256 file plus machine-readable provenance.

## Architecture policy

`make app` produces a native bundle for the build Mac. The app executable, Deno, and the restricted FFmpeg build are single-architecture; the bundle verifier requires every helper to support the app architecture. The pinned yt-dlp helper is universal. Release filenames declare their architecture, for example `Eucrante-0.1.0-1-macOS-arm64.zip`.

The source and helper installer support Apple Silicon and Intel builds, but the project does not claim a universal artifact until both Deno and FFmpeg slices are assembled and tested together. Release notes must list the architecture of every attached archive.

## Prepare

1. Update `CFBundleShortVersionString`, `CFBundleVersion`, and `CHANGELOG.md`.
2. Run the complete local checks and acceptance tests.
3. Commit the release state and create the exact annotated tag `v<CFBundleShortVersionString>`.
4. Confirm the worktree is clean.

```sh
make check
make coverage
make app
git tag -a v0.1.0 -m "Eucrante 0.1.0"
```

For a binary release, do not push the tag until the release candidate has passed the signing and notarization steps below. A source-only release may push its checked tag before creating the draft described later.

## Sign, notarize, and package

Store notary credentials in Keychain once with `xcrun notarytool store-credentials`. Never place signing credentials, private keys, profiles, or notary secrets in the repository or CI logs.

```sh
CODESIGN_IDENTITY='Developer ID Application: …' ./Scripts/build-app.sh release
APPLE_NOTARY_PROFILE='Eucrante-Notary' ./Scripts/notarize-app.sh
```

The notarization script refuses a dirty worktree, a mismatched tag, an ad-hoc signature, a failed bundle audit, a rejected notarization, an unstapled ticket, or a failed Gatekeeper assessment. On success, `dist/` contains:

- the notarized, stapled drag-to-Applications DMG;
- the architecture-labelled ZIP archive;
- one portable `<sha256>  <filename>` checksum file per artifact;
- one JSON provenance record per artifact containing the version, build, tag, commit, architecture, minimum macOS version, artifact hash and size, notarization state and request ID, and every bundled-helper hash.

Verify the checksum from inside `dist/`:

```sh
shasum -a 256 -c Eucrante-0.1.0-1-macOS-arm64.zip.sha256
shasum -a 256 -c Eucrante-0.1.0-1-macOS-arm64.dmg.sha256
```

## Distribution policy

GitHub Releases is Eucrante's canonical distribution channel. No tagged release exists yet. With the maintainer's current free Apple developer account, any published release must be source-only: GitHub generates a ZIP and tarball from the exact version tag, and users build locally. Do not attach an unsigned or ad-hoc-signed app and instruct users to weaken Gatekeeper.

Notarization and Developer ID distribution require Apple Developer Program membership. If the project later gains that membership, a binary release carries a friendly DMG and portable ZIP per supported architecture, each with its own checksum and provenance record. `Scripts/create-dmg.sh` produces the native drag-to-Applications layout, signs the disk image, submits it separately to Apple, staples its ticket, and verifies Gatekeeper.

Maintainers can exercise the complete visual installation flow without creating a publishable artifact:

```sh
make dmg-development
```

The resulting ad-hoc-signed image lives under `dist/development/` and is permanently excluded from the publisher.

Homebrew Cask is deferred until the first stable notarized binary release. A cask does not replace Developer ID signing or notarization. When added, it must reference immutable versioned GitHub assets and their exact SHA-256 values. Start with a project-owned tap; propose the cask to Homebrew's main repository only after release URLs and maintenance practices are stable.

Automatic updates remain disabled until a separately reviewed signed Sparkle feed and signing-key rotation/recovery policy exist. GitHub release attachments and HTTPS alone are not an update trust root.

## Publish a draft

Install and authenticate GitHub CLI once:

```sh
brew install gh
gh auth login
```

Create `dist/RELEASE_NOTES.md` from the matching changelog section. For a source release, include macOS/Xcode requirements, local build steps, and the provider-authorization reminder. Then push the exact release commit and annotated tag and create a source-only draft:

```sh
git push origin main v0.1.0
make publish-source-release NOTES=dist/RELEASE_NOTES.md
```

`Scripts/publish-release.sh --source-only` creates a draft with GitHub's generated source archives and no app binary. It refuses a dirty or incorrectly tagged tree, an unpushed tag, or an existing release for that tag.

## Future notarized binary draft

After obtaining Apple Developer Program membership and producing the notarized artifacts above, create the binary draft with:

```sh
make publish-release NOTES=dist/RELEASE_NOTES.md
```

`Scripts/publish-release.sh` refuses a dirty or incorrectly tagged tree, an unpushed tag, an architecture missing its paired DMG or ZIP, a failed checksum, mismatched provenance, or an artifact that is not recorded as accepted and stapled by Apple. It creates a draft only and attaches every architecture's DMG, ZIP, checksums, and provenance without renaming them.

## Publish

For source-only releases, inspect the draft's rendered notes and generated archives, build the tag in a clean checkout, run the complete checks, and publish the draft only after they pass.

For future binary releases:

1. Inspect the draft's rendered notes, tag, and all attached files.
2. Download the draft attachments to another directory or clean Mac and verify every checksum.
3. Inspect each app signature and stapled ticket, pass Gatekeeper, launch the app, and complete the first-run download and Music-import smoke tests.
4. Publish the draft only after those checks pass.
5. Download the public attachments once more and confirm their hashes match the draft artifacts.

Never replace an asset on a published release. Publish a new patch version when any binary or metadata must change.
