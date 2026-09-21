# Backend verification — 2026-09-20

The current deterministic simulator gate is **52 passed, 0 failed, 0 blocked**.
It runs the actual embedded OpenJDK Zero, Kotlin sandbox, Go server and native
FFmpeg engine on the dedicated iPhone 17 Pro simulator (iOS 26.5). Of these checks,
40 cover public interfaces/test-host behavior and 12 are explicitly marked JVM
diagnostics. Diagnostics do not substitute for the public content checks.

## Verified

- Repository synchronization, JAR installation/update/removal, actual APK-to-JAR
  conversion and execution, source preference writes and restart persistence.
- Exact manga/anime/novel metadata; source headers and cookies; cover/icon bytes,
  overrides, offline caches and invalidation; manga reader pages and real HTTP
  chapter fetching through the Graal JavaScript interpreter.
- Public MP4 bytes and seeking, HLS playlists/segments, DASH manifests/init/media
  fragments, subtitle extraction and private-target rejection.
- Manga loose-page/CBZ, anime and novel downloads; final progress, persisted bytes,
  deletion, and origin-offline delivery after a complete app/JVM relaunch.
- Library progress/folders/filtering/download counts, source migration including
  per-series automation overrides, backups, storage and tracker API composition.
- Native browser cookie/user-agent transfer, domain isolation and persistent cookie
  restoration after app restart.

The separate native media suite passes **16 cases**: compatible MP4 direct-copy
bytes; TS/fMP4/master/separate-audio/AES-128 HLS; DASH; VideoToolbox H.264/AAC
conversion; and rejection of missing segments, DRM, truncated/invalid media,
unbounded live streams, missing source headers, cancellation and output-write
failure. These tests use the embedded libraries, not an FFmpeg subprocess.

The full vendored Go race suite passes. Additional tests cover metadata provider
failure, public AniList login/progress and MAL OAuth callback fixtures, replay
rejection, browser session cancellation/expiry, corrupt images, queue atomicity,
interruption/fresh URL retry, injected disk failure, backup round trips, local
imports/scanning/relocation, format migration and controlled-clock automation.
Kotlin tests, six Python harness regressions, seven CLI tests, Rust formatting/
Clippy, Go vet, Swift native-import/restart smoke and device/simulator Swift 6
checks also pass. The simulator product app builds with the service bridges.

## Performance sample

- Warm fixture manga search: **27.1 ms median**, **28.0 ms maximum** of five calls.
  The previous baseline median was 27.0 ms; this sample shows no material warm
  search regression. Third-party network latency is excluded.
- Cached cover delivery: **1.57 ms median**, **3.03 ms maximum**, 32 requests at
  concurrency eight.
- Simulator process RSS after relaunch and offline checks: **364.4 MiB**. This is
  an observed process footprint, not a memory ceiling or physical-device estimate.

## Device and external validation

An earlier physical iPhone 13 Pro run passed embedded MP4 remuxing and
VideoToolbox H.264/AAC conversion. The final rerun, after direct MP4 copying and
validation changes, could not launch because the phone was locked. This latest
device check is **pending**, not a pass. The disposable test app was removed.

Real human WKWebView challenge completion and real tracker-account authentication
remain manual checks. No live-provider success is inferred from fixtures. The
historical live MangaDex run fetched metadata/covers but returned no chapters for
the selected title; that provider/content limitation is not converted into a pass.
Whole-JVM physical-device acceptance, real disk exhaustion and large-library stress
checks have not been performed. Product UI and OS background transfers are outside
this service implementation.

The original 2026-09-19 baseline was 26 passed, 17 failed, 3 blocked. Its disabled
public APIs and disabled novel runtime are no longer the current implementation.

## Reproduce

```sh
./moku-ios test acceptance --simulator DA9EC3F6-C296-4F18-9C7E-84EF0088F3DC
./moku-ios test backend
go -C vendor/Tsunagu/backend test -race ./...
services/scripts/test-video-device.sh 9A98E069-1018-5A66-8737-34ABA5C1141E
```

The device command requires that phone connected and unlocked. Run native builds
sequentially. Live providers can be checked separately with `./moku-ios test
acceptance-live`; FAIL and BLOCKED both fail the gate.

Detailed current outputs are `services/.build/last-acceptance.json` and `.xml`,
`verify-services.log`, `services-all-test.log`, `sandbox-tests.log`, and
`device-media-result.log`. They are ignored build artifacts and replaced on rerun.
