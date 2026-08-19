# Security Policy

## Reporting

Use GitHub private vulnerability reporting from the repository Security tab. Do not open a public issue for a suspected vulnerability.

Include the affected version/commit and macOS version, the smallest reproduction using non-sensitive data, the expected boundary, observed impact, and any proposed mitigation. Do not include browser data, cookies, source links, personal filenames, downloaded media, signing material, or other secrets.

The maintainer aims to acknowledge reports within seven calendar days and provide an initial assessment within fourteen days.

## Supported versions

| Version | Security support |
| --- | --- |
| `main` | Yes |
| Latest tagged release, once releases exist | Yes |
| Older prerelease builds | No |

## Scope and trust model

This policy covers the native app, `EucranteCore`, helper-installation and release scripts, bundled-helper integration, and project-controlled dependencies.

Source URLs, provider output, titles, filenames, metadata, media files, WebKit content, and helper output are untrusted. The private YouTube session, local files, output-folder access, Music automation, signing identities, and release hashes are protected assets.

## Required properties

- The app opens no listening port and depends on no Eucrante server or remote job store.
- YouTube sign-in is off by default, occurs only in Eucrante's private WebKit store, and never reads an external browser.
- Every job staging directory and the Jobs root use mode `0700`. Applicable cookies are written only for YouTube jobs; the cookie file is created mode `0600` before any credential bytes are written, presented to the provider for acquisition, and deleted on both success and failure before staging can be retained. Startup repairs existing staging-directory permissions and purges an export left by forced process termination before jobs resume, and Sign Out cancels active YouTube saves before purging exports. Eucrante has no service that receives them and does not log them.
- Untrusted values are passed to `Process` as argument-array elements; no shell interpolation is permitted.
- Downloaded helper executables and FFmpeg source are pinned by version and SHA-256, verified before use, and code-signed inside the final app.
- FFmpeg is built with network, GPL, and non-free functionality disabled. Eucrante does not bundle x264, x265, or other external codec libraries.
- Helper paths come only from signed bundle resources, the development build directory, or explicit developer overrides.
- Provider titles are sanitized and cannot select an output path.
- Job staging is constrained to an opaque UUID directory under Application Support.
- Job history is replaced atomically in the same directory and stored mode `0600`.
- Embedded sign-in navigation is restricted to HTTPS pages on the required YouTube and Google domain suffixes; lookalike hosts are rejected.
- A zero-byte or unreadable output is never marked complete.
- Diagnostics omit source URLs, cookies, helper output, media, and personal output paths.
- The app does not bypass DRM or access controls.

## Reportable examples

- Cookie or private-session disclosure, including a temporary cookie export retained after acquisition.
- Arbitrary file read/write, path traversal, shell/argument injection, or code execution.
- Escape from the per-job staging/output boundary.
- Malicious media or metadata causing a concrete security impact.
- Dependency, checksum, nested-signing, notarization, or update-provenance compromise.

Vulnerabilities solely in yt-dlp, Deno, a media provider, or Apple frameworks should also be reported upstream. Report them here when Eucrante creates or amplifies the user impact.

## Known alpha limitations

- No signed and notarized public release exists yet.
- Automatic updates remain disabled until a signing-key and release-feed policy exists.
- Broader licensed golden-media and clean-machine browser/Music permission testing remains before v1.
