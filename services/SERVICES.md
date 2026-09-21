# Embedded service contract

Product screens are separate from these services. The native host must start the
JVM once, register `TSVideoEngine`, and start `BackendController` with its sandbox
endpoint. The controller registers the engine automatically. A missing native
engine returns an error; iOS never falls back to an FFmpeg process.

## Public interfaces

All HTTP routes use the per-start backend bearer credential and numeric loopback.
Never attach that credential to source websites or permit authenticated redirects.
Existing GraphQL fields and `/content/{media}/{chapter}/...` URLs are preserved.

| Interface | Contract |
| --- | --- |
| `GET /api/mobile/status` | Capability booleans, migration count, explicit platform limitations |
| `POST /api/graphql` | Composed upstream library, discovery, metadata, extension, tracker, download and administration operations |
| `/content/` | Manga pages, novel HTML, local downloads, MP4/ranges, HLS/DASH and subtitles |
| `/proxy/cover/`, `/proxy/img/`, `/proxy/icon/` | Authenticated cover, override and extension icon delivery |
| `POST /api/backups/import-file` | Bounded multipart backup import |
| `GET/PUT /api/mobile/automation?mediaId=0` | Global policy; a positive media ID selects that series |
| `POST /api/mobile/chapter-open` | JSON `{ "mediaId": 1, "chapterId": 2 }` |
| `POST /api/mobile/tracker/callback` | JSON `{ "tracker": "mal", "callbackURL": "..." }`; validates OAuth state and consumes it once |

The temporary catalog allowlist is removed. Source-dependent operations require a
connected embedded JVM; offline library and local content remain available without
it. Managed FlareSolverr, server-password replacement, process/bootstrap settings,
and paths outside app-owned storage fail explicitly. AniList token login uses the
existing GraphQL operation; MAL callbacks use the native authenticated forwarding
route. No real tracker account is modified by the fixture tests.

## Native bridges and ownership

`beginBrowserVerification` returns an opaque, expiring session ID, source ID, URL
and pending state. `SourceVerificationBrowser` seeds a `WKWebView` from the shared
source cookie store. The host presents that view and calls `complete(retry:)`
after the user finishes. Completion transfers cookies and user agent through
`WKHTTPCookieStore`, then invokes the original operation once. Continuing challenges
remain errors. `cancel()` drops the pending session. Cookie values are native-only;
GraphQL and status responses never expose them. Source headers in content URLs
use authenticated, opaque tokens instead of clear base64 JSON; legacy URLs remain
accepted for desktop compatibility. Persistent cookies and per-host
user agents survive app restarts; pending verification sessions do not.

`importLocalFile` holds the user-granted security scope while copying a regular
file into app-owned storage. It does not retain an external path. Supply
`kind` (`manga`, `anime`, `novels`), series, chapter and filename. CBZ manga can be
imported directly under the series; loose pages need a chapter directory.

The host must call `suspend()` on foreground loss and `resume()` on return. Resume
returns a new authenticated connection. The JVM remains alive until process exit.
Shutdown drains HTTP handlers, cancels image/enrichment/scheduler work, interrupts
and joins download workers, then closes gRPC and SQLite. Interrupted downloads
remain queued and resolve new source URLs; explicit cancellation removes partial
work. No OS background-transfer capability is advertised.

## Automation policies

`PUT` replaces the policy object at that scope. Omitted per-series fields inherit
global values; `{}` removes effective overrides. Field names follow desktop
preferences: `autoDownload`, `downloadAhead`, `deleteOnRead`, `deleteDelayHours`,
`maxKeepChapters`, `autoDownloadScanlators`, `pauseUpdates`, `refreshInterval`.
Defaults are automation off, ahead zero, unlimited retention (`maxKeepChapters=0`),
zero deletion delay, updates unpaused and refresh `manual`. Refresh also accepts
`daily`, `weekly`, and per-series `global`.

Policies, delayed deletion and scheduler timestamps use additive migration 18.
Repeated progress/open events do not duplicate jobs. Deletion rechecks current
policy and completion; retention uses source order. Library catch-up runs at most
one title per tick, with a five-minute failure backoff. Tracker polling, backups
and policy work run only while this service is foregrounded.

## Media and image limits

Pinned FFmpeg 9.0.2 libraries provide direct compatible MP4 copies, finite HLS/DASH
remuxing, and incompatible-track conversion with VideoToolbox H.264 and AAC.
Copies and remuxes are validated before atomic finalization; progress remains below
100% until completion. A single native engine processes one video job at a time.
Ordinary AES-128 HLS is supported. DRM/CENC and unbounded live downloads are rejected.
See [media notices/build inputs](THIRD_PARTY_MEDIA.md).

Image validation supports JPEG, PNG, GIF and WebP, with a 32 MiB encoded limit,
16-megapixel decode limit and at most two concurrent validation decoders. Mobile
manga cache is 64 MiB, segment cache 32 MiB, and page prefetch concurrency two.
Source cover/page retrieval uses the source's HTTP headers and shared cookies.
Metadata enrichment is owned background work and does not block source search.
