# Privacy

Eucrante has no project account, analytics, advertising SDK, backend, remote job store, or telemetry endpoint.

## Stored on this Mac

- Preferences, including the selected browser name and output policy.
- A security-scoped bookmark for the chosen output folder.
- Local queue/history records.
- Temporary per-job media under Application Support until completion or history cleanup.

Eucrante does not store source links in diagnostics. Job history necessarily stores a submitted source URL locally so retry can work.

## Browser sessions

Browser use is disabled by default. If the user selects Brave, Chrome, Firefox, or Safari, the bundled local downloader reads that browser's current session and presents the applicable cookies only to the selected provider as part of the requested download. Eucrante has no service that receives them and does not log or separately save them. The media provider receives the normal authenticated requests from the user's Mac and applies its own privacy policy.

## Media and Apple apps

Downloads and processing remain local. When the user explicitly selects Import to Music, Eucrante asks macOS for Automation permission and sends only the selected verified local audio file to Music; it does not read the Music library.

Use Clear Local History and Finder/Trash actions to remove local records and files. Cancelling or removing a failed job cleans its private staging directory.
