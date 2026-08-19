# Repository configuration

These settings are part of Eucrante's release and contribution boundary. Review them after GitHub changes its settings UI or adds materially different controls.

## General

- Visibility: public.
- Description: `Private, native macOS media tools with Apple Music import and Apple-native video output.`
- Website: `https://chai-in.github.io/Eucrante/`
- Topics: `macos`, `swift`, `swiftui`, `media`, `audio`, `video`, `apple-music`, `local-first`, `privacy`, `open-source`.
- Enable Issues and Discussions.
- Disable Wiki; repository documentation and GitHub Pages are authoritative.
- Disable Projects until the issue tracker needs a separate planning board.
- Allow squash merging only, update pull-request branches, and automatically delete merged branches.
- Require contributors to sign off web-based commits.

## Rulesets

Protect `main` with a branch ruleset:

- prevent branch deletion and force pushes;
- require a pull request for non-maintainers;
- require the `Swift checks` status check and up-to-date branches;
- require all review conversations to be resolved;
- require linear history;
- allow repository administrators to bypass for emergency and solo-maintainer releases.

Protect tags matching `v*` from deletion and non-fast-forward updates. Release tags are annotated and point to the exact versioned release commit.

## Actions and Pages

- Default workflow token permissions: read repository contents.
- Do not allow Actions to create or approve pull requests.
- Keep third-party actions pinned to complete commit SHAs; Dependabot maintains them.
- Pages source: GitHub Actions.
- Pages URL: `https://chai-in.github.io/Eucrante/`.
- Enforce HTTPS.

The Pages workflow deploys only the versioned contents of `Site/`. It receives `pages: write` and `id-token: write`; other workflows remain read-only.

## Security

- Enable private vulnerability reporting.
- Enable dependency graph, Dependabot alerts, and Dependabot security updates.
- Enable secret scanning and push protection when GitHub offers them for the repository.
- Keep CodeQL enabled for Swift-capable analysis; do not weaken CI to make a security check green.
- Keep release attachments immutable after publication. Correct a release with a new patch version.

## Releases

- Source-only while the maintainer uses a free Apple developer account.
- Draft first; publish only after a clean-checkout build and complete test pass.
- Future binary releases must contain paired notarized DMG and ZIP artifacts for each supported architecture, plus one checksum and provenance file per artifact.
- Never publish unsigned or ad-hoc-signed app binaries.
