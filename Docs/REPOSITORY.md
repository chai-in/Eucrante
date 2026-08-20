# Repository configuration

These settings are part of Eucrante's release and contribution boundary. They describe the verified GitHub configuration and should be rechecked whenever GitHub changes its settings model.

## Public profile

- Visibility is public.
- Description: `Native, local-first macOS media tools with Apple Music import and Apple-native video output.`
- Website: `https://chai-in.github.io/Eucrante/`
- Topics: `macos`, `swift`, `swiftui`, `media`, `audio`, `video`, `apple-music`, `local-first`, `privacy`, `open-source`.
- Issues and Discussions are enabled.
- Wiki and Projects are disabled; repository documentation and GitHub Pages are authoritative.
- Only squash merging is enabled. GitHub suggests branch updates and automatically deletes merged branches.
- Web-based commits require contributor signoff.
- Published releases and their tags/assets are immutable.

## Rulesets

The active `main` branch ruleset:

- prevents deletion and force pushes;
- requires a pull request for non-bypassing contributors;
- requires the `Swift checks` status check and an up-to-date branch;
- requires all review conversations to be resolved;
- requires linear history;
- allows repository administrators to bypass for emergency and solo-maintainer releases.

The active `v*` tag ruleset prevents release-tag updates and deletion. Repository administrators may bypass it for a deliberate corrective release operation. Release tags remain annotated and point to the exact versioned release commit.

## Actions and Pages

- Actions must be pinned to full commit SHAs.
- Default workflow-token permissions are read-only for repository contents and packages.
- Actions cannot create or approve pull requests.
- Dependabot maintains the pinned third-party Actions.
- Pages deploys from GitHub Actions to `https://chai-in.github.io/Eucrante/` with HTTPS enforced.

The Pages workflow deploys only the versioned contents of `Site/`. It receives `pages: write` and `id-token: write`; other workflows remain read-only.

## Security

- Private vulnerability reporting is enabled.
- Dependency graph, automatic dependency submission, Dependabot alerts, malware alerts, and security updates are enabled.
- CodeQL default setup is enabled for the detected source languages.
- Secret scanning and push protection are enabled.
- Do not weaken CI or security thresholds to make a check green.

## Releases

- No tagged release exists yet.
- Any release remains source-only while the maintainer uses a free Apple developer account.
- Draft first; publish only after a clean-checkout build and complete test pass.
- Future binary releases must contain paired notarized DMG and ZIP artifacts for each supported architecture, plus one checksum and provenance file per artifact.
- Never publish unsigned or ad-hoc-signed app binaries.
