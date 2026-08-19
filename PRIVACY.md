# Privacy

Eucrante has no project account, analytics, advertising SDK, backend, remote job store, or telemetry endpoint.

## Stored on this Mac

- Preferences, including output policy and whether optional app features are enabled.
- A security-scoped bookmark for the chosen output folder.
- Local queue/history records.
- Temporary per-job media under Application Support until completion or history cleanup.

Eucrante does not store source links in diagnostics. Job history necessarily stores a submitted source URL locally so retry can work.

## In-app YouTube session

YouTube sign-in is disabled by default and required only when saving from YouTube. If the user signs in inside Eucrante, the session is stored only in Eucrante's private macOS WebKit data store. Eucrante does not read Brave, Safari, Chrome, Firefox, or any other app's files. Every staging directory and the Jobs root use mode `0700`. For an authenticated YouTube save, Eucrante creates the temporary cookie file with mode `0600` before writing any credential bytes, writes only applicable YouTube-domain cookies, passes it to the bundled downloader, and deletes it immediately after acquisition succeeds or fails. The cookie file is never created for another provider. If the process is forcibly terminated during that interval, startup cleanup repairs existing staging-directory permissions and removes the export before jobs resume. Choosing Sign Out cancels active YouTube saves and purges their exports. The session is never logged, included in diagnostics, or uploaded to Eucrante infrastructure. The media provider receives normal authenticated requests from the user's Mac and applies its own privacy policy.

The sign-in sheet can open Apple's Passwords app. Eucrante does not query, inspect, or receive the Passwords database; the user controls any copy and paste into Google's page. Automatic iCloud Password suggestions are unavailable because Apple requires the app and website to establish a reciprocal associated-domain trust relationship, which Google does not provide to Eucrante.

## Media and Apple apps

Downloads and processing remain local. When the user explicitly selects Import to Music, Eucrante asks macOS for Automation permission and sends only the selected verified local audio file to Music; it does not read the Music library.

Local job history is atomically stored with mode `0600`. Use Clear Local History and Finder/Trash actions to remove local records and files. Cancelling or removing a failed job cleans its private staging directory. Clearing history requires confirmation and does not delete downloaded files.
