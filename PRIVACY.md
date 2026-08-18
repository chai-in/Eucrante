# Privacy

## Summary

The app is designed to operate without analytics, advertising, user accounts, or third-party crash reporting. It does not sell personal information.

## Data handled on this Mac

- The configured processing endpoint is stored in app preferences.
- Optional Cloudflare Access service-token credentials are stored in macOS Keychain.
- Save history is currently held in memory for the active session.
- Downloaded files are written to the configured local destination.

The planned deployment-backed release also stores job manifests, resumable inputs, and verified outputs in an R2 bucket owned by the user. It does not send those objects to infrastructure operated by this project. Completed cloud jobs remain until the user explicitly deletes them.

## Data sent over the network

When a user starts a save, the app sends the entered public media URL and selected processing options to the Cobalt-compatible endpoint configured by that user. If configured, the API credential is sent in the request authorization header. Public endpoints must use HTTPS; credentials are blocked on non-HTTPS endpoints except loopback connections to the same Mac.

The configured Worker and Container may return direct or proxied download URLs. The app then connects to those URLs or to the user's private R2 bucket to retrieve the selected media. Cloudflare and media providers may independently observe network metadata and request content according to their own policies.

## Data the app does not access

The app does not import browser cookies, access private or DRM-protected media, or inspect an Apple Music library. It uploads job artifacts only to the R2 bucket configured by that user; there is no project-operated storage. Future Apple Music import support will require a separate, visible permission and privacy review before release.

## Diagnostics

The current build does not transmit diagnostics. Planned diagnostics exports will be local, user-initiated, and redacted by default.

## Contact

Open a public issue for privacy questions that do not contain sensitive information. Use private vulnerability reporting for security-sensitive privacy concerns.
