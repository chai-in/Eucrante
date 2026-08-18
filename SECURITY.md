# Security Policy

## Reporting a vulnerability

Use GitHub private vulnerability reporting from the repository's Security tab.
If private reporting is unavailable, contact the maintainer privately using the
security contact published on the repository owner's GitHub profile.

Do not open a public issue for a suspected vulnerability.

Include:

- The affected app version or commit.
- The affected component and macOS version.
- Reproduction steps using non-sensitive test data.
- The expected security boundary and observed impact.
- Any suggested mitigation or proof of concept.

Do not include real API keys, authorization headers, private URLs, personal
filenames, downloaded media, or other user data.

The maintainer aims to acknowledge reports within seven calendar days and
provide an initial assessment within fourteen days. Disclosure timing will be
coordinated with the reporter when a fix is required.

## Supported versions

| Version | Security support |
| --- | --- |
| `main` | Yes |
| Latest tagged release, once releases exist | Yes |
| Older prerelease builds | No |

## Scope and trust model

This policy covers the native macOS client, `EucranteCore`, the code in
`Backend/`, packaging scripts, release configuration, and project-controlled
dependencies.

Source URLs, processing-instance responses, redirect and download URLs,
filenames, metadata, subtitles, artwork, and media files are untrusted input.
API credentials, local files, output-folder access, and future Music automation
permission are protected assets.

## Security requirements

- Public processing endpoints use HTTPS.
- Unauthenticated HTTP endpoints are limited to loopback and private
  development hosts.
- API credentials are sent only over HTTPS or HTTP loopback connections to the
  same Mac.
- API control requests do not follow redirects.
- API control-response bodies are limited to 2 MiB before decoding. Media
  downloads are intentionally not subject to that small control-response cap.
- API credentials remain in macOS Keychain and are excluded from preferences,
  diagnostics, and logs.
- Production Workers disable `workers.dev`, sit behind Cloudflare Access, and
  reject requests that lack the Access assertion added by Cloudflare.
- Cloudflare Access service-token values remain in Keychain and are never sent
  to the upstream Cobalt Container.
- R2 buckets and objects remain private; media access is mediated by the Worker.
- R2 job deletion is explicit and prefix-scoped to a validated UUID.
- Remote filenames are sanitized and cannot select an output path.
- Local processing must never interpolate untrusted input into a shell command.
- Logs and diagnostics must redact credentials, source queries, response
  bodies, and personal filesystem paths.
- The app does not import browser cookies or bypass authentication, paywalls,
  DRM, or private-content controls.

## Reportable vulnerabilities

Examples include:

- Credential disclosure or transport to an unintended host.
- Arbitrary file read, write, overwrite, or path traversal.
- Code execution or command injection.
- TLS, endpoint-policy, redirect-policy, or authorization-boundary bypass.
- Unsafe media or metadata processing with a concrete security impact.
- Sensitive-data exposure through logs, diagnostics, preferences, or UI.
- Dependency, signing, update, or release-pipeline compromise.

## Third-party systems

Vulnerabilities solely in the separately distributed upstream Cobalt container,
a media provider, an Apple or Cloudflare service, or another dependency should
also be reported to that project's maintainer. Report them here when Eucrante's
behavior creates or amplifies the user impact.

Legal-use, provider-policy, and general availability questions are not security
reports. Do not test infrastructure or accounts you do not own or have
permission to assess.

## Known alpha limitations

- No signed and notarized public release exists yet.
- The sandbox, entitlement, and automatic-update designs are not finalized.
- Local media conversion and Music automation are not implemented.
- Queue history is currently held only for the active session.
- The Swift client does not yet resume R2 multipart state after relaunch.
- Public release provenance and reproducible-build automation remain Phase 1
  work.
