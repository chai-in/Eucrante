# Eucrante + Harbor

Harbor is the shared native installer and setup guide at `../Harbor`. The existing build/release process remains authoritative. This integration adds no updater daemon, changes no app data, and does not grant permissions.

Identity: `app.eucrante.client`. Harbor accepts only arm64 native code, including helpers. The legacy and preview bundle IDs are separate identities and are not silently migrated.

Build entry point observed on 2026-09-05: `Scripts/build-app.sh release`. Choose the actual completed app bundle from that build. No hosted release, Apple signing identity, or catalog key is assumed.

Package a release using Harbor's shared exporter (publisher workflow):

```sh
/Users/chai/Code/Harbor/scripts/export-app.sh eucrante /absolute/path/to/Eucrante.app /absolute/output/folder 'ACTUAL_HTTPS_ZIP_URL' preview
```

Pass `verified` only for a Developer ID-signed and notarized artifact; Harbor checks both. The exporter reports the required version/build/arm64 filename if the URL differs. It round-trips the ZIP through the same archive and bundle checks used by the installer, then emits a release record. It never uploads anything.

Follow `/Users/chai/Code/Harbor/docs/RELEASE_CONTRACT.md` to put the record in an expiring, monotonically sequenced, Ed25519-signed catalog. A release record or SHA-256 file alone is not publisher authentication. Preview filenames keep `-unnotarized` and first-open guidance keeps macOS's **Privacy & Security → Open Anyway** path.

The `HarborKit` Swift package product owns the shared manifest, release types and permission guidance. Its models can be imported by app or release tooling through a local Swift package dependency on `../Harbor`; the existing app has no runtime dependency on Harbor. TCC requests continue to originate from Eucrante's own UI. Harbor cannot query or grant Eucrante's protected access.
