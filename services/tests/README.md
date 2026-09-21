# Backend acceptance gate

Run this before connecting more product UI:

```sh
./moku-ios test acceptance
./moku-ios test acceptance-live # adds live MangaDex; internet required
```

The in-repo `./moku-ios` launcher builds its Swift tool automatically. For a prepared backend and booted simulator, the
internal runner is also available:

```sh
python3 services/tests/backend_acceptance.py SIMULATOR_UDID --live
```

Use a simulator that is not running another UI-test session; a competing app
launch can suspend the probe. Select it with `--simulator UDID` on the CLI.

Requires the normal native backend toolchain plus host `ffmpeg`. The runner builds
two tiny Java extensions against the pinned sandbox JAR, generates a two-second
original video, and serves a protobuf repository and source website on an ephemeral
loopback port. Each run starts a fresh **backend-only simulator app** with its own
database and installs the extensions through the real catalog API. No product UI,
mock gRPC server, preinstalled source, or manually seeded media rows are involved.
The optional live check downloads a fresh MangaDex extension through Keiyoushi,
searches an exact title, fetches its cover, and calls the actual extension's
metadata and chapter methods through the embedded JVM.

The Python client exercises public GraphQL/HTTP. A separate Java gRPC **client**
calls the same iOS-hosted JVM to distinguish missing Go service wiring from JVM
execution failures. Extension execution stays in OpenJDK Zero inside Simulator.
The host JDK only compiles fixtures and runs that diagnostic client.

## Assertions

| Area | Verification |
| --- | --- |
| Runtime and auth | Fresh embedded startup, unauthenticated API rejected, credentials never forwarded on redirects |
| Extensions | Repository ingestion, downloaded JAR loading, installed flag and correct manga/anime/novel type |
| Search | Exact title and external ID, empty search, pagination, stable database identity across repeated requests |
| Timing | Startup, cold calls, five warm searches; configurable provisional 5-second maximum per warm local search |
| Source metadata | Description, author, genres, search/detail identity, chapter and episode mapping |
| Covers | Correct PNG bytes, successful read while origin is offline; optional real MangaDex cover bytes |
| Manga | Ordered page URLs and actual image bytes through JVM; public reader URLs and exact page bytes |
| Anime | JVM MP4/HLS source extraction, required Referer and subtitle metadata; public video bytes, byte-range seek, rewritten playlist and segment bytes |
| Subtitles | Track extraction; public proxy must reject private-IP subtitle targets (a deliberate security rule) |
| Novels | Actual JS plugin installation, source metadata, chapters and rendered text |
| Downloads | Enqueue/start, DONE and 100% progress within deadline, persisted artifacts, origin-offline retrieval, delete and downloaded-flag reset for each content type |
| Video downloads | Compare decoded frames so valid remuxing does not fail a byte-for-byte container comparison |
| Discovery/library | Popular/latest/filters, source preferences, library save/query and persisted reading progress |

`last-acceptance.json` and `last-acceptance.xml` under `services/.build` contain all
results and timings. FAIL and BLOCKED both produce a nonzero exit and JUnit
failures. A successful HTTP response or returned media URL alone is insufficient.
GraphQL errors fail even if the response also contains partial data. Checks
continue after failures so one unsupported operation cannot hide the others.

The temporary connection file contains fresh test credentials with mode 0600.
The runner removes it and stops the native host on success or failure. The host
also has a 15-minute lifetime limit. Source fixtures and generated assets are
deleted; the fresh app-owned database/download directory remains for inspection.

## Additional verification

```sh
services/scripts/verify.sh
services/scripts/test-video-engine.sh
services/scripts/test-video-device.sh CONNECTED_DEVICE_ID
go -C vendor/Tsunagu/backend test -race ./...
```

The native engine suite uses the actual embedded Objective-C adapter and pinned
FFmpeg libraries. Host command-line FFmpeg generates original fixtures and checks
outputs; it is never called by the iOS downloader. Cases include direct MP4 bytes,
TS/fMP4/master/AES-128 HLS, DASH, VideoToolbox/AAC conversion, DRM/live/truncation
rejection, required headers and cancellation. The device script installs a separate
disposable test host and removes it on exit.

The simulator gate now also builds a synthetic APK (binary Android manifest and
DEX), converts and executes it inside OpenJDK Zero, checks cover overrides/cache
invalidation, and relaunches the entire test host with the origin offline. Persistent
cookies, library entries, policies and downloaded bytes must survive the new process.
Search and concurrent image timings plus simulator resident memory are recorded.

Go race tests cover queue deduplication/atomic claims, cancellation/interruption,
fresh URL resolution on retry, progress finalization, metadata/provider contracts,
tracker fixtures, backup round trips, local scanning/relocation, format migration,
and controlled-clock automation catch-up. Swift smoke tests exercise native local
imports and backend suspend/resume. Kotlin tests cover cookie matching/persistence,
challenge classification and gRPC keepalive.

## Interpretation and remaining checks

The former disabled-service failures are fixed; do not weaken the assertions or
turn failures into skips. Public API results and JVM diagnostics are reported
separately. Source fixture success does not establish SwiftUI rendering, AVPlayer
presentation, universal third-party extension compatibility, or real provider uptime.

Real human browser challenge completion and real tracker-account authentication
remain manual checks. Physical-device validation covers the media adapter, not the
entire JVM/API acceptance matrix. VTT/SRT/ASS HTTP delivery is checked against an upstream transport fixture; the
simulator gate independently checks subtitle extraction and private-target rejection.
The native media suite covers adaptive download variants separately from the
simulator's public MP4/HLS/DASH delivery checks. Disk errors are injected in queue
tests and native output-write failures are checked. Real disk exhaustion and
large-library stress testing remain outstanding. No background-transfer or App Store
eligibility claim is made.

The gate's own error-detection regression tests run in `./moku-ios test backend`, or:

```sh
python3 -m unittest discover -s services/tests -p 'test_*.py' -v
```
