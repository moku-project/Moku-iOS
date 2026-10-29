# iOS responsiveness audit — 2026-09-22

The audit scanned the 186 Swift files under `Moku`, traced the navigation and feature-loading paths, and reviewed the embedded backend's Swift/native execution boundary. Existing local changes were preserved. This document describes the additional changes from this audit, rather than attributing earlier performance work to it.

These are code-level causes of avoidable work and latency. They are not an Instruments trace or a claim that every possible source of dropped frames has been eliminated. Network/source latency, GPU compositing cost, cold OS/framework initialization, and thermal behavior require measurements on an iPhone.

## Findings and fixes

| Area | Cause | Change |
| --- | --- | --- |
| Tab navigation | Every first tab mount waited for two display ticks before constructing its page. | Mount the page immediately, retaining the small view boundary that isolates observations from the navigation shell. |
| Player startup | First playback deliberately waited for a complete 2.2-second skeleton animation. | The player UI no longer requests that minimum delay. |
| Player startup | Automatic subtitle downloads held up video preparation. | Load optional subtitles independently; cancel automatic work when switching/stopping playback. Parse captions away from the main actor. |
| Library navigation | Every activation fetched the entire server library, wrote it to disk, and published it even when unchanged. | Use a 30-second freshness window for automatic refreshes, skip unchanged disk writes/publications, and retain explicit retry/import refreshes. |
| Library state | Appearance tasks reset the selected view and repeatedly rebuilt presentation items. | Configure the default view once. Reuse item preparation when its inputs have not changed; only publish changed items. |
| Library rendering | Filtering and localized sorting happened during SwiftUI body evaluation. | Prepare lists asynchronously outside the UI executor and publish only the current selection's result. Keep synchronous model access available for existing non-view callers. |
| Library search | The scoped local repository filtered on the main actor; source discovery rescanned the entire library for each source. | Prepare the selected snapshot asynchronously, filter away from the main actor, and group sources in one pass. |
| Library membership | Every `contains` lookup scanned all saved titles. | Maintain a title-ID set for constant-time membership checks. |
| Details | Chapter preferences were decoded and chapter lists filtered/sorted inside rendering. | Prepare chapter lists asynchronously when data or filters change, with cancellation checks before publication. Preserve preferred release order for equal chapter numbers. |
| Scanlator menus | Menu rendering repeatedly rebuilt scanlator lists and decoded the entire preferences document. | Prepare unique group choices asynchronously and retain decoded preferences until their input changes. |
| Details loading | The page-wide skeleton hid usable metadata while the chapter source request was still running. | Reveal metadata as soon as it is available; keep chapter loading in the chapter area. |
| Home/Details data | Each revisit rescraped the source chapter list, including navigation between Home and Details. | Share requests and reuse a successful source sync for 120 seconds. Revisited pages still read current progress/download state from local SQLite. Explicit chapter refresh bypasses freshness. |
| Home data | Two separate appearance/change tasks requested library counts. | Use one keyed task, with a short cache for identical read-only count queries. |
| Browse | Discovery shelves repeatedly normalized/deduplicated titles during unrelated view updates. | Cache derived shelf arrangements until their source arrays change. |
| Search | Result sorting ran on the main actor; a hidden page's unstructured search could continue competing with navigation. | Sort outside the main actor. Suspend interrupted searches on disappearance, resume on return, and reject stale responses. Stop discovery loading while a search query is active. |
| Downloads | Each three-second poll made a serial title lookup for every title in the queue and created a date formatter for every record. | Batch missing title names in groups of 40, retain names for five minutes, and prepare snapshots on a dedicated actor using one formatter per snapshot. |
| Download publications | Identical snapshots still invalidated views, and progress ticks caused Library's completed-title set to be rebuilt. | Publish only changed snapshots and maintain a separate completed-title index that changes only when completion membership changes. |
| Download lifecycle | Polling remained active behind the root details overlay. | Include details visibility in the active-page condition. |
| Download bulk actions | Clearing N entries refreshed the entire queue N times. | Perform the requested removals, then refresh once. |
| Recent opening | Opening History immediately requested chapter data for every saved title. | Load Updates on demand when that tab is selected. Numeric saved titles can read stored chapters without resolving source metadata or starting the source runtime. |
| Recent rendering | History grouping/sorting ran in the view body; every day rescanned the full history; all title rows were constructed eagerly. | Prepare history and day sections away from the UI, precompute chapter groupings, and use lazy history rows. Prepare statistics when their panel opens. |
| Recent dates | Sorting chapters repeatedly constructed `ISO8601DateFormatter` and reparsed dates inside the comparator. | Parse each source date once during construction/decoding, including fractional seconds. Sorting now compares stored dates. |
| Activity history | Every progress sample replaced title metadata, removed/reinserted the session, and queued another full-history file write. | Skip unchanged metadata, update an existing session in place, and coalesce writes while preserving an explicit `flush` boundary. Recent-title ordering scans sessions once and sorts only unique titles. |
| Reader preferences | Every page turn synchronously encoded all preferences, positions, overrides and bookmarks. | Coalesce rapid changes and encode snapshots off the main actor. Flush on reader dismissal/backgrounding. Avoid saving an unchanged position. |
| Reader progress | Rapid page changes and flushes could send redundant progress mutations. | Coalesce pending progress and skip successfully committed duplicates. |
| Reader/player rendering | Every body evaluation rebuilt all chapter labels and activity metadata. | Prepare activity metadata once per model, outside the UI executor. Inactive activity recording no longer wakes a periodic sampler. |
| Long-strip reader | Opening a chapter allocated an image view, placeholder and label for every page. | Retain layout geometry for the chapter but instantiate UIKit page views only around the visible/preload window. Transfers remain limited to three. |
| Reader scrolling | Visible-page lookup scanned the whole chapter and auto-scroll advanced on a fixed 30 Hz timer. | Use binary lookup into page frames, bounded view maintenance, and a display link with elapsed-time-based movement. Stop image work when the canvas is inactive. |
| Cover images | Warm cache hits still briefly showed placeholders; each image had overlapping skeleton machinery; unused requests kept running. | Read the thread-safe decoded cache for the first frame, use one lightweight placeholder, and cancel shared loads only after their last consumer leaves. Check cancellation before assigning pixels. |
| Disk cache | Every downloaded resource enumerated and sorted the entire cache directory before returning. | Build a lazy size/date index once, account incrementally, and sort only when eviction is necessary. Preserve the existing disk budget and clear semantics. |
| Extensions | Changing catalog filters/pagination unnecessarily reloaded installed sources and repository lists. | Filter-driven catalog loads reuse the loaded independent sections; explicit reloads and mutations still refresh them. |
| Release build | A preview referenced a Debug-only host outside a Debug compilation guard. | Guard that preview so optimized iPhone builds compile. |
| Theme resolution | Even a built-in theme decoded all custom theme JSON during root updates. | Return built-in themes before decoding custom themes. |

## Validation

- `python3 Tools/PerformanceChecks/run.py`: **27 tests passed** on macOS using the actual production core files, including cache sharing/cancellation/eviction, history preservation, rapid preference edits, library filtering, chapter selection, and source-date decoding. The runner creates a temporary Swift package with symlinks; it does not replace production implementations with test stubs.
- Debug app and all iOS test targets: built with `xcodebuild ... -destination 'generic/platform=iOS Simulator' ARCHS=arm64 build-for-testing`. This compiles tests without running a simulator. New iOS regressions cover interrupted-search resumption, completed-download indexing, and the 1,000-page reader view window.
- Optimized physical-iPhone target: **Release build passed**, with signing disabled for compile/link validation. Build log: `.build/ui-performance-release-build.log`.
- No simulator, app, UI test, screen capture, or device-control session was launched for this audit.

The checkout already had whitespace warnings in its native backend patch; those unrelated edits were preserved. AppIntents metadata-extraction warnings are unrelated to these changes.

## Device verification

Check rapid Library ↔ Browse ↔ Home ↔ Downloads switching with a populated library, including switching away while searches and covers are loading. Confirm selected Library views and scroll positions survive returning. Open a long chapter list, filter/reverse it, enter the reader, jump far ahead, rotate, and verify single/double/RTL/long-strip modes, auto-scroll, and restored progress. Open a video with a slow subtitle source and confirm video preparation does not wait for subtitles. Verify Recent History opens without a library update and its Updates tab still refreshes explicitly.

For reliable performance conclusions, profile the Release build on representative iPhones with Instruments' SwiftUI, Hangs, Time Profiler and Animation Hitches tools. Compare warm and cold page openings separately; inspect memory after extended scrolling and check VoiceOver with the virtualized reader. The existing debug responsiveness monitor only detects larger main-actor stalls and is not an FPS measurement.

## Follow-up: navigation stays slow after Library

The reported symptom persists on Home/More after leaving Library, independently of the number of saved titles. That makes a library-size explanation insufficient. This follow-up fixes additional navigation dependencies and lifecycle work found in code; it does not establish the duration or definitive cause of the reported two-second stall without a device trace.

| Finding | Change |
| --- | --- |
| The closure used to build each visited tab captured the whole root view and read global selection. Unrelated tab switches therefore invalidated the Library page boundary too. | Replace it with an explicit, equatable page boundary whose parent inputs are stable references. Each tab observes its own activity/visited state; switching between Home and More does not publish changes to Library's activity. Model, environment and preference changes still update the relevant page. |
| Each navigation change replaced the shared scroll-navigation object. | Reset its directional accumulator in place; publish a compactness change only when necessary. |
| Closed Library dropdowns still constructed, laid out and observed the geometry of all their invisible rows. | Mount dropdown rows when opening and remove them once closing finishes. |
| Appearance/preference callbacks reassigned unchanged Library settings, incrementing the result revision and discarding cached sorts. | Invalidate derived results only when values actually change. Observe the library revision rather than compare the saved-entry array in the view. |
| Duplicate item-update callbacks cancelled and restarted identical preparation; obsolete detached sorts kept running. | Reuse preparation already in flight for the same inputs, cancel superseded work, propagate cancellation into filtering/sorting, suspend preparation when inactive, and reject stale publications. Library search also receives the page's active state. |
| Every disappearing cover cleared multiple state values, then reset/reloaded them on reappearance. | Keep a weak handle to the cached image, avoid state teardown on disappearance, and return immediately for a warm cover. The shared decoded cache retains its existing budget; retained cell state does not strongly own the bitmap. |
| Navigation timing was available only with a UI-test launch argument. | Log tab-selection-to-frame-probe timing in ordinary Debug runs, warning at 100 ms. The probe runs for two display callbacks per selection, not continuously. This is a diagnostic proxy, not a GPU presentation or touch-to-screen measurement. |

Follow-up validation: **31 native core tests passed**, including inactive-tab observation isolation, retained visit state while overlays suspend activity, no-op Library settings and cancelled-preparation recovery. The Debug app and all test targets compiled without launching a simulator, and the optimized physical-iPhone Release build passed with signing disabled. Logs: `.build/library-navigation-core-tests.log`, `.build/library-navigation-build.log`, and `.build/library-navigation-release-build.log`.

Device check: visit Library, then switch rapidly between Home and More, return to Library, and confirm its filters/scroll position survive. Exercise Library's view/layout dropdowns and the content-mode selector, including opening settings/details and returning. If a stall remains, Debug console messages in `com.moku.app` / `Navigation` and `UIResponsiveness` now expose its timing for the next investigation.

## Reference principles

The changes follow Apple's guidance to keep view bodies inexpensive, reduce unnecessary updates, keep non-UI work off the main thread, and bound rendering/image work:

- [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)
- [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
- [Demystify SwiftUI performance](https://developer.apple.com/videos/play/wwdc2023/10160/)
