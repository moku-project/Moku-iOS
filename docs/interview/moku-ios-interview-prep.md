# Moku iOS: interview prep

A reminder list, not a script. Numbers were checked with `gh` on 2026-10-28.

## Pitches

**30 seconds**
- Moku is an open-source manga, light-novel and anime reader. Its desktop app has about 7k downloads and 190 GitHub stars.
- I led the native iOS port in SwiftUI.
- The hard part: Moku's sources are Android/JVM extensions run by a backend server (Tsunagu). I embedded that backend on the phone (Go library + an interpreter-only JVM), so the iOS app runs the same extensions with no separate server.

**2 minutes**
- Problem: desktop Moku talks to Tsunagu, a Go server that loads Mihon/Aniyomi extensions (Android APKs) in a Kotlin sandbox. On iOS you cannot ask users to run a server, and there is no Android runtime.
- Approach: compile the Go backend with gomobile into a static framework. Build OpenJDK for iOS (Zero, interpreter-only, because iOS forbids JIT). Start both in the app process. They talk over loopback with per-launch bearer tokens.
- Extensions: APKs are converted on-device with dex2jar and loaded into the embedded JVM. LNReader novel plugins (JavaScript) run in GraalJS on the same JVM.
- App: about 20k lines of Swift 6 (strict concurrency), SwiftUI, MVVM with `@Observable` view models and repository protocols, so every screen has a fixture-backed preview and UI test.
- Results: search, details, chapter lists and page images from a real source (MangaDex) load on the simulator through the embedded runtime. The project's acceptance suite (52 checks: manga pages, MP4/HLS/DASH video, subtitles, novels, downloads, restart) passes on-device.
- What I'd improve: cold start (the JVM boots in about 10 s), App Store policy risk, and upstreaming the iOS fork.

## Architecture

```
┌──────────────────────── iOS app process (Moku.app) ────────────────────────┐
│                                                                            │
│  SwiftUI views ── @Observable view models ── repositories (protocols)      │
│        │                                         │                         │
│        │ AVPlayer (HLS/MP4)                      │ URLSession              │
│        ▼                                         ▼  http://127.0.0.1:<port> │
│  ┌──────────────────────┐   Bearer token   ┌──────────────────────────┐    │
│  │ BackendController     │ ───────────────▶ │ Tsunagu core (Go,         │   │
│  │ (Swift actor)         │                  │ gomobile static lib)      │   │
│  └──────────────────────┘                  │ GraphQL + REST + SQLite    │   │
│        │ JNI_CreateJavaVM (once)            │ image cache, HLS proxy,   │   │
│        ▼                                    │ downloads, FFmpeg (video) │   │
│  ┌──────────────────────┐   gRPC (loopback, └────────────┬─────────────┘   │
│  │ OpenJDK Zero JVM      │◀── token) ────────────────────┘                 │
│  │ Kotlin sandbox        │                                                 │
│  │  • dex2jar'd APK exts │                                                 │
│  │  • GraalJS novel exts │                                                 │
│  │  • OkHttp             │                                                 │
│  └──────────┬───────────┘                                                  │
└─────────────┼──────────────────────────────────────────────────────────────┘
              ▼  HTTPS
   Extension repos (index.min.json / repo.json → index.pb) and source sites
```

- Swift ↔ Go: gomobile bindings for start, stop and status, plus HTTP/GraphQL for data. That is the same API the desktop app uses, so feature parity is mostly UI work.
- Go ↔ JVM: gRPC over loopback with a shared secret. The Go side owns the DB and caching. The JVM only runs untrusted extension code. AVPlayer gets authenticated loopback URLs (`AVURLAssetHTTPHeaderFieldsKey`).
- Lifecycle: the JVM can only start once per process, so the source runtime starts lazily, the first time a screen needs it. Local SQLite reads work without it.

## Key design decisions

**1. Embed the backend on-device instead of running a separate server**
- Why: no setup for users, works offline for downloaded content, and runs the exact extension ecosystem desktop users have.
- Alternatives: (a) self-hosted server plus a thin client, the way Moku desktop and Suwayomi clients work; (b) rewrite extensions natively in Swift; (c) a cloud proxy.
- Trade-offs: a big binary (about 210 MB before thinning), roughly 10 s JVM cold start, interpreter speed, roughly 200 MB RSS, a complex native build (OpenJDK, Go, FFmpeg), and App Store risk. The upside is zero infrastructure and full extension compatibility.

**2. How extensions run on iOS**
- APK → dex2jar → JAR → loaded by a custom classloader in the Kotlin sandbox. Android APIs used by extensions (WebView cookies, SharedPreferences, OkHttp setup) are stubbed or shimmed in Kotlin.
- JVM: OpenJDK "Zero" port, interpreter only. iOS doesn't allow writable+executable memory for third-party apps, so there's no JIT, and HotSpot's template interpreter is out too.
- JS novel plugins: GraalJS on the same JVM (also interpreted).
- Isolation: extensions only reach the Go core through gRPC with a token, and they never see the app's UI or keychain. The iOS app sandbox is the outer boundary. Not a hard security sandbox; be honest about that.
- App Store: guideline 2.5.2 forbids downloading code that changes app behaviour. Interpreted code is the gray area (the JavaScriptCore/scripting exemption is narrow). Plan: internal TestFlight (no review), no bundled sources, honest review notes. Distribution may end up on AltStore or sideloading.

**3. SwiftUI vs UIKit**
- SwiftUI everywhere, for speed of iteration, previews and accessibility.
- UIKit only where SwiftUI is weak: the manga reader canvas (a `UIScrollView` with manual page layout, a decode queue and a memory budget), the app-lock window, and a window-level gesture recognizer for idle detection.
- Trade-off: two mental models. But it gave a 60 fps reader for 50-page chapters with multi-MB images.

**4. Concurrency model**
- Swift 6 strict concurrency. `actor Backend` / `BackendAPI` own shared state. View models are `@MainActor @Observable`.
- JVM startup runs on a dedicated `DispatchQueue`, never the main actor, bridged with `withCheckedThrowingContinuation`.
- A request-coalescing `ResourceCache` actor (in-flight sharing, LRU memory plus disk, cancels a fetch when its last consumer cancels) handles GraphQL results and covers.

**5. Fork plus patch for the backend**
- The iOS changes live on a Tsunagu fork branch, also exported as `Services/patches/0001-embedded-core.patch` on top of upstream, so the build can rebuild from a clean upstream checkout.
- Trade-off: upstream moves fast (60 commits behind at port time). Cherry-pick source-compatibility fixes rather than doing risky merges.

## Defending the resume bullets

Verified numbers:

| Repo | Stars | Release downloads |
| --- | --- | --- |
| `moku-project/Moku` (desktop) | **190** | **6,997** (5,840 installers; the rest are updater/other assets) |
| `moku-project/Moku-iOS` | 0 | 0 (no releases yet) |
| `moku-project/Tsunagu` | 7 | 400 |

- Both numbers belong to the Moku project (the desktop repo), **not** the iOS port. "188+ stars" is still true (190). "6.5k+ downloads" is true for all release assets (6,997) but not for installers alone (5,840).
- Your commits: you are the sole author of the 10 Moku-iOS commits. On Moku desktop you have 1 contribution (the maintainer has 568). Be ready to say the desktop app is someone else's and the iOS port is yours.

Suggested wording:
- "Led development of the native iOS port (Swift 6/SwiftUI) of Moku, an open-source manga and anime reader whose desktop app has 6.9k+ downloads and 190+ GitHub stars."
- "Embedded the Go backend and an interpreter-only OpenJDK runtime on-device so Android source extensions run natively on iOS, removing the need for a separate server; fixed extension-compatibility issues (repo index formats, suspend-API listings, relative image URLs)."

Be ready to back up:
- "Fixed extension porting and compatibility issues": examples from this branch:
  - Keiyoushi/Yuzono moved to `repo.json` → protobuf `index.pb`, and the old JSON index became a placeholder. Fix: parse `index_v2`.
  - MangaDex 1.6 implements only the suspend `getPopularManga`, so the Rx path threw and Popular was empty.
  - MangaDex returns relative image paths, so pages failed with "no scheme". Fix: resolve through `imageRequest`.
  - gRPC 4 MB message cap on large pages.
  - Missing `UnmeteredSource` interface → `NoClassDefFoundError`.
- "Eliminating the need for a separate server": Go core plus JVM in-process, loopback only, a token per launch.

## Likely questions (with answer pointers)

**iOS lifecycle and system**
1. *What happens when the app is backgrounded?* The scene phase locks the app (if app lock is on) and flushes preferences. The backend stays up while foregrounded. Scheduling is foreground-only (the backend status reports `foreground scheduling only`; no BGTask yet).
2. *Why start the JVM lazily?* About 10 s cold start and about 200 MB memory. Library, history and settings don't need it.
3. *Why only one JVM per process?* `JNI_CreateJavaVM` can't be re-created after destroy. An atomic guard is in `TSJavaRuntime.m`. Failure is sticky; ask the user to relaunch.
4. *Memory warnings?* `didReceiveMemoryWarning` → `BackendAPI.trimMemory()` (drops in-memory caches). The reader keeps a 48 MB decoded-image budget.
5. *Launch time?* The UI renders from SQLite immediately and skeletons cover runtime start. Nothing blocks the main thread.

**Concurrency**
6. *Actor vs class plus lock?* Actors for async shared state (backend connection, caches). Data races are compile-time errors in Swift 6.
7. *How do you avoid duplicate requests?* `ResourceCache` keeps in-flight `Task`s keyed by query, with consumer counting. It cancels when nobody waits.
8. *Task cancellation in SwiftUI?* `.task(id:)` cancels on id change. View models check generation counters, so stale results can't overwrite newer ones.
9. *Bridging callback or blocking APIs?* `withCheckedThrowingContinuation` around the JVM start on its own queue.
10. *MainActor isolation of view models?* `@MainActor @Observable`; network and decoding run off-main in actors and detached tasks.

**Memory and images**
11. *Large manga pages?* Downsampled decode via ImageIO (`PageDecoder` actor). Only a window of pages around the viewport is decoded. Prefetch is capped at 3 transfers.
12. *Why did a 7 MB page fail?* The gRPC default 4 MB receive cap. Raised to 40 MB, matching the sandbox's 32 MiB limit.
13. *Decode bombs?* The backend validates image headers (≤16 MP) before caching.

**Caching**
14. *Layers?* Go: SQLite metadata, a disk cover cache and an in-memory page LRU. Swift: memory plus disk `ResourceCache` with TTL. AVPlayer handles its own segment caching.
15. *Invalidation?* Mutations clear the query cache. Covers are keyed by media id plus an override version.

**AVPlayer and HLS**
16. *How does video play?* The source resolves a stream. The Go core proxies MP4 with Range support and rewrites HLS playlists so segments go through loopback with source headers. AVPlayer plays `http://127.0.0.1`.
17. *Why proxy instead of giving AVPlayer the URL?* Sources need custom headers, cookies and referers, plus ad-segment stripping and subtitle conversion. AVPlayer can't set per-request headers reliably.
18. *ATS?* `NSAllowsLocalNetworking` only; no arbitrary loads.
19. *Subtitles?* Converted to WebVTT by the backend and rendered as a SwiftUI overlay.
20. *DASH?* AVPlayer can't play DASH. Playback prefers MP4/HLS variants. The bundled FFmpeg (`TSVideoEngine`) is used for video downloads. Check the current DASH path in `content.go` before claiming more.

**App Store and TestFlight**
21. *Will this pass review?* Internal TestFlight yes, since there's no review. External and App Store are at risk under 2.5.2 (downloaded executable code) and 5.2.3 (third-party content). Mitigations: no default sources, a clear disclaimer.
22. *Export compliance?* Only standard HTTPS/TLS plus PBKDF2 for the PIN, so `ITSAppUsesNonExemptEncryption = NO`.
23. *Privacy manifest?* Required-reason APIs (UserDefaults, file timestamps, boot time, disk space) are declared, including those used by the statically linked Go, JVM and FFmpeg.
24. *Why is the binary so big?* JVM modules, the sandbox JAR (88 MB) and FFmpeg. Ideas: jlink-trim modules, strip the sandbox's unused deps, on-demand resources.

**Open source and collaboration**
25. *Working with upstream?* The fork is a branch plus a patch file. Cherry-pick upstream fixes with `-x` so provenance is visible. Upstream later added an embedded package for mobile, so there's convergence to plan.
26. *Disagreement or code review?* (Prepare a story, e.g. choosing patch-based embedding over a long-lived fork.)
27. *Licensing?* Apache-2.0 app; OpenJDK GPLv2+CE; FFmpeg LGPL (static linking means you ship the notices and build scripts); Phosphor MIT.

**Testing and debugging**
28. *How do you test without real sources?* Fixture extensions plus a local fixture website. The acceptance suite runs the real on-device runtime (52 checks). UI tests use launch arguments with fixture repositories.
29. *Hardest bug?* An empty Popular shelf with no error: the sandbox mapped `UnsupportedOperationException` to an empty page. Found it from the cached GraphQL response on disk, then the suspend-API fix.
30. *Debugging a silent 502?* Added logging, then used a probe app plus a copied data dir to hit the endpoint directly, which surfaced "no scheme" (relative URL) and then the gRPC size limit.

**Behavioural**
31. *A time you scoped down?* Didn't merge 60 upstream commits overnight (15 conflicts, DB migrations). Cherry-picked the compatibility fixes instead.
32. *Leading the port?* Owned the architecture, build tooling (Swift CLI `moku-ios`), app and release prep. Coordinated with the desktop maintainer on API parity.
33. *What would you do differently?* Push to upstream an embedded mode earlier, measure cold start from day one, and plan App Store strategy before the architecture.

## Concepts to review
- App and scene lifecycle (`scenePhase`), background modes, memory warnings, jetsam limits.
- Swift concurrency: actors, reentrancy, `Sendable`, `@MainActor`, structured vs unstructured tasks, cancellation, continuations.
- SwiftUI data flow: `@Observable`, `@State`, `@Environment`, `.task(id:)`, view identity, performance (lazy stacks, `EquatableView`).
- UIKit interop: `UIViewRepresentable`, `UIScrollView` zooming and layout, ImageIO downsampling.
- AVFoundation: `AVPlayer`/`AVPlayerItem`, HLS playlists (master vs media, segments, EXT-X-KEY), audio session, PiP.
- Networking: URLSession config, ATS, HTTP Range requests, caching headers.
- JVM basics: JIT vs interpreter, why iOS forbids JIT (W^X, code signing), JNI, classloaders.
- gomobile/cgo: static libraries, calling conventions, threads and signals in a shared process.
- gRPC/protobuf: message limits, deadlines, wire format (useful for the `index.pb` story).
- App Store: guidelines 2.5.2, 4.2, 5.2.3; TestFlight internal vs external; privacy manifests; export compliance.
- Licences: GPL with Classpath Exception, LGPL static-linking obligations, Apache-2.0.
