# Privacy

Eucrante has no project account, analytics, advertising SDK, backend, remote job store, or telemetry endpoint.

## Stored on this Mac

- Preferences, including output policy and whether optional app features are enabled.
- A security-scoped bookmark for the chosen output folder.
- Local queue/history records.
- Temporary per-job media under Application Support until completion or history cleanup.

Eucrante does not store source links in diagnostics. Job history necessarily stores a submitted source URL locally so retry can work.

## Private website sessions

Website sign-in is optional. Public links are checked without requiring a login; a provider authentication failure identifies the website and offers a reconnect. The embedded browser displays its actual HTTPS destination, including identity providers. Sessions remain in Eucrante's private macOS WebKit store, preserving existing YouTube sessions. Eucrante does not read Safari, Chrome, or another app's cookie files.

Every staging directory and the Jobs root use mode `0700`. Applicable cookies for the selected website are exported to a temporary Netscape file created with mode `0600` before any credential bytes are written. Unrelated websites and identity-provider cookies are excluded. Each concurrent scan worker gets a separate, site-scoped copy. Exports are deleted after acquisition or scanning on success, failure, or cancellation. Startup removes abandoned scan/preview folders and both old YouTube and new website job exports. Removing a session cancels that site's active saves and clears only that site's WebKit records and applicable cookies.

Recent scan results are cached in memory for two minutes (failures for 30 seconds), with a 256-item bound. This contains display metadata and format descriptions, never signed media URLs or credentials, and is invalidated on session changes. Sessions, cookie exports, source links, and media are never uploaded to Eucrante infrastructure or included in diagnostics. Providers receive normal requests directly from this Mac and apply their own privacy policies.

The sign-in sheet can open Apple's Passwords app. Eucrante does not query, inspect, or receive the Passwords database; the user controls any copy and paste into the website. Automatic iCloud Password suggestions require a reciprocal associated-domain trust relationship between the app and website.

## Media and Apple apps

Downloads and processing remain local. When the user explicitly selects Import to Music, Eucrante asks macOS for Automation permission and sends only the selected verified local audio file and its chosen metadata to Music; it does not read the Music library.

Local job history is atomically stored with mode `0600`. Use Clear Local History and Finder/Trash actions to remove local records and files. Cancelling stops the job; removing a failed or cancelled job cleans its private staging directory. Clearing history requires confirmation and does not delete downloaded files.

Timeline previews resolve short-lived stream and storyboard URLs for the selected item. These URLs and decoded frames remain in memory, outside history, diagnostics and the page-scan cache. Storyboard requests use an ephemeral URL session with no shared cookie store or disk cache. Thumbnail caches are bounded, and source changes or closing the editor cancel preview work and release the player. Provider cookies are used only by the existing site-scoped extractor; preview requests do not copy those cookies to unrelated media hosts. Native playback may buffer remote media while the editor is open.
