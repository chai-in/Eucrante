# Repository configuration

These settings are part of Eucrante's release and contribution boundary. They describe the verified GitHub configuration and should be rechecked whenever GitHub changes its settings model.

## Public profile

- Visibility is public.
- Description: `Native, local-first macOS media tools with Apple Music import and Apple-native video output.`
- Website: `https://eucrante-site.tibcon.workers.dev/`
- Topics: `macos`, `swift`, `swiftui`, `media`, `audio`, `video`, `apple-music`, `local-first`, `privacy`, `open-source`.
- Issues and Discussions are enabled.
- Wiki and Projects are disabled; repository documentation and the Cloudflare-hosted project website are authoritative.
- Only squash merging is enabled. GitHub suggests branch updates and automatically deletes merged branches.
- Web-based commits require contributor signoff.
- Published releases and their tags/assets are immutable.

## Rulesets

The active `main` branch ruleset:

- prevents deletion and force pushes;
- requires a pull request for non-bypassing contributors;
- requires all review conversations to be resolved;
- requires linear history;
- allows repository administrators to bypass for emergency and solo-maintainer releases.

The active `v*` tag ruleset prevents release-tag updates and deletion. Repository administrators may bypass it for a deliberate corrective release operation. Release tags remain annotated and point to the exact versioned release commit.

## Builds and website

- GitHub Actions workflows are not used.
- Cloudflare Workers Static Assets serves the fingerprinted `dist/site/` output of `npm run build` at `https://eucrante-site.tibcon.workers.dev/`; editable source stays in `Site/`.
- The Cloudflare production branch is `main`, the build command is `npm run build`, and the deploy command is `npx wrangler deploy`.
- `npm run build` validates required files, page titles, local links/assets, and rejects local-only URLs before deployment.
- Dependabot maintains the pinned Wrangler development dependency.

Cloudflare's build image is Linux. It cannot compile or test Eucrante's AppKit, SwiftUI, AVFoundation, or Xcode-dependent code. Native app checks and coverage therefore run locally on macOS before pushing; the Cloudflare build owns only portable website validation and deployment.

## Security

- Private vulnerability reporting is enabled.
- Dependency graph, automatic dependency submission, Dependabot alerts, malware alerts, and security updates are enabled.
- CodeQL default setup is enabled for the detected source languages.
- Secret scanning and push protection are enabled.
- Do not weaken native test, coverage, or security thresholds to make a check green.

## Releases

- No tagged release exists yet.
- While the maintainer uses a free Apple developer account, public binary previews are explicitly ad-hoc signed, unnotarized, architecture-labelled, and published as GitHub prereleases.
- Draft first; publish only after a clean-checkout build and complete test pass.
- Unnotarized preview DMGs include matching checksums and provenance, retain the `-unnotarized` filename suffix, and include the Settings > Privacy & Security > Open Anyway instructions.
- Future binary releases must contain paired notarized DMG and ZIP artifacts for each supported architecture, plus one checksum and provenance file per artifact.
- Never describe an unnotarized preview as Apple-verified, and never tell users to disable Gatekeeper or strip quarantine attributes.
