# Release process

Eucrante has no unsigned public-release path. A publishable artifact must come from a clean, exactly tagged commit, use a Developer ID Application signature, pass the assembled-bundle audit, be accepted by Apple's notary service, carry a stapled ticket, pass Gatekeeper assessment, and ship with a portable SHA-256 file plus machine-readable provenance.

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

Do not push the tag until the release candidate has passed the signing and notarization steps below.

## Sign, notarize, and package

Store notary credentials in Keychain once with `xcrun notarytool store-credentials`. Never place signing credentials, private keys, profiles, or notary secrets in the repository or CI logs.

```sh
CODESIGN_IDENTITY='Developer ID Application: …' ./Scripts/build-app.sh release
APPLE_NOTARY_PROFILE='Eucrante-Notary' ./Scripts/notarize-app.sh
```

The notarization script refuses a dirty worktree, a mismatched tag, an ad-hoc signature, a failed bundle audit, a rejected notarization, an unstapled ticket, or a failed Gatekeeper assessment. On success, `dist/` contains:

- the architecture-labelled ZIP archive;
- a portable `<sha256>  <filename>` checksum file;
- a JSON provenance record containing the version, build, tag, commit, architecture, minimum macOS version, archive hash and size, notarization state and request ID, and every bundled-helper hash.

Verify the checksum from inside `dist/`:

```sh
shasum -a 256 -c Eucrante-0.1.0-1-macOS-arm64.zip.sha256
```

## Publish

1. Push the exact release commit and annotated tag.
2. Create the GitHub release from that tag.
3. Attach the ZIP, checksum, and provenance JSON without renaming them.
4. Copy the matching changelog section into the release notes and state the supported architecture and minimum macOS version.
5. Download the public attachments on a clean Mac, verify the checksum, inspect the signature and stapled ticket, pass Gatekeeper, launch the app, and complete the first-run smoke test.

Automatic updates remain disabled until a separately reviewed signed-feed design is implemented. GitHub release attachments are not an update trust root by themselves.
