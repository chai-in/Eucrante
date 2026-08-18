# Contributing

Thank you for helping improve this independent macOS media client.

## Before opening a change

- Search existing issues and pull requests.
- Use an issue for substantial behavior, architecture, or user-interface changes before investing in an implementation.
- Keep changes focused and avoid unrelated formatting or dependency additions.
- Do not copy source code, artwork, names, mascots, or other branding from the upstream Cobalt project.
- Use only media fixtures that you created, that are openly licensed, or that you are authorized to redistribute.

## Development setup

Requirements:

- macOS 14 or newer
- Full Xcode installation
- Swift 6 toolchain

Run the same checks used by continuous integration:

```sh
swift format lint --recursive Sources Tests Package.swift
swift test
swift build -Xswiftc -warnings-as-errors
swift run EucranteCoreChecks
make app

cd Backend
pnpm install --frozen-lockfile
pnpm run check
pnpm test
```

## Pull requests

- Add or update tests for behavioral changes.
- Explain the user-visible outcome and important tradeoffs.
- Update documentation when behavior, security boundaries, or API compatibility changes.
- Never include API keys, tokens, private URLs, downloaded media, signing identities, or provisioning profiles.
- Treat source URLs, filenames, API responses, and remote downloads as untrusted input.

By submitting a contribution, you agree that it is licensed under the Apache License 2.0 under the contribution terms in section 5 of that license. No separate contributor license agreement is currently required.

## Reporting security problems

Do not open a public issue for a suspected vulnerability. Follow the private reporting instructions in [SECURITY.md](SECURITY.md).
