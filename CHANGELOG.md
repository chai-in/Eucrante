# Changelog

All notable changes will be documented in this file. The project follows [Semantic Versioning](https://semver.org/) once public releases begin.

## Unreleased

### Fixed

- Forward Cobalt's signed root `/tunnel` URLs to the private container instead of returning a Worker 404.

### Added

- Native SwiftUI application shell and typed Cobalt v11 client.
- Keychain-backed API credentials and local download queue.
- Apache License 2.0 and public contribution documentation.
- Public-repository continuous integration and issue templates.
- Bring-your-own Cloudflare architecture with a private R2 resumable job store and explicit indefinite retention.
- Persistent local queue/history with output-folder bookmarks, progress, cancellation, retry, and resumable multipart R2 output uploads.
- Four Apple-oriented one-click output policies with local inspection and verification.
- Live sample filenames for every Metadata filename style.
- Explicit verified-audio import to Music, optional completion notifications, Dock activity count, URL drag-and-drop, and the `eucrante://save` scheme.
- Privacy-safe diagnostics export plus Developer ID entitlement, packaging, and notarization scripts.

### Security

- Public processing endpoints require HTTPS.
- API credentials are blocked on non-HTTPS connections except loopback connections to the same Mac.
- API control requests reject redirects so credentials cannot cross an unexpected origin or HTTPS downgrade.
- API control responses are capped before decoding to limit memory abuse by a misconfigured or malicious instance.
- Large retained-output uploads reject redirects and persist only opaque upload/part identifiers for resume.
