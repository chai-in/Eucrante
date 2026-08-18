# Changelog

All notable changes will be documented in this file. The project follows [Semantic Versioning](https://semver.org/) once public releases begin.

## Unreleased

### Added

- Native SwiftUI application shell and typed Cobalt v11 client.
- Keychain-backed API credentials and local download queue.
- Apache License 2.0 and public contribution documentation.
- Public-repository continuous integration and issue templates.
- Bring-your-own Cloudflare architecture with a private R2 resumable job store and explicit indefinite retention.

### Security

- Public processing endpoints require HTTPS.
- API credentials are blocked on non-HTTPS connections except loopback connections to the same Mac.
- API control requests reject redirects so credentials cannot cross an unexpected origin or HTTPS downgrade.
- API control responses are capped before decoding to limit memory abuse by a misconfigured or malicious instance.
