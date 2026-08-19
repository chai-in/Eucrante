# Privacy

Eucrante has no project account, analytics, advertising SDK, backend, remote job store, or telemetry endpoint.

## Stored on this Mac

- Preferences, including output policy and whether optional app features are enabled.
- A security-scoped bookmark for the chosen output folder.
- Local queue/history records.
- Temporary per-job media under Application Support until completion or history cleanup.

Eucrante does not store source links in diagnostics. Job history necessarily stores a submitted source URL locally so retry can work.

## In-app YouTube session

YouTube sign-in is optional and disabled by default. If the user signs in inside Eucrante, the session is stored only in Eucrante's private macOS WebKit data store. Eucrante does not read Brave, Safari, Chrome, Firefox, or any other app's files. For an authenticated save, Eucrante writes only applicable YouTube-domain cookies to a permission-restricted file inside that job's private staging folder, passes it to the bundled downloader, and deletes it immediately after acquisition succeeds or fails. If the process is forcibly terminated during that interval, startup cleanup removes the export before jobs resume. It is never logged, included in diagnostics, or uploaded to Eucrante infrastructure. The media provider receives normal authenticated requests from the user's Mac and applies its own privacy policy.

The sign-in sheet can open Apple's Passwords app. Eucrante does not query, inspect, or receive the Passwords database; the user controls any copy and paste into Google's page. Automatic iCloud Password suggestions are unavailable because Apple requires the app and website to establish a reciprocal associated-domain trust relationship, which Google does not provide to Eucrante.

## Media and Apple apps

Downloads and processing remain local. When the user explicitly selects Import to Music, Eucrante asks macOS for Automation permission and sends only the selected verified local audio file to Music; it does not read the Music library.

Use Clear Local History and Finder/Trash actions to remove local records and files. Cancelling or removing a failed job cleans its private staging directory.
