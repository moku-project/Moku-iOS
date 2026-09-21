# Moku feature inventory

Source baseline: sibling `Moku` repository, commit `ee54dbb6d37be4c574933a569134f3a7bb53778b` (v0.13.0), inspected 2026-09-19.

## How to use this document

This inventories desktop source behavior to guide Moku-iOS development. It is not an iOS completion checklist: desktop behavior is not assumed to be implemented in this iOS repository; explicit mobile milestones are recorded separately below. Evidence comes from source inspection, not an end-to-end test against a running server. Backend-dependent behavior depends on the connected Tsunagu version and source capabilities. Consult `DESIGN.md` for visual tokens and themes.

Each numbered feature group has a stable ID and source pointers. Paths in source pointers are relative to the sibling Moku repository. Preserve IDs when adding mobile implementation decisions. Treat settings labels, type declarations, and README promises as weaker evidence than their executing code; known gaps are listed below.

## Architecture and responsibility boundaries

Moku is a Svelte/Tauri frontend for Tsunagu. Desktop builds can launch and supervise a bundled backend; the UI can also connect to an external instance. The frontend calls GraphQL and other server endpoints through adapters. Sources, library records, folders, chapter data, tracker operations, and download jobs largely depend on that server. Frontend presentation, reader preferences, local history, and native desktop integrations have separate state and platform code.

A server download is not automatically an offline copy on another client device. A source extension installed through Moku is managed by Tsunagu, not a Swift plugin. Folder membership can be shared through the server, while per-folder view preferences are client settings. Do not assume every preference/history field already has cross-device sync.

Sources: `src/lib/server-adapters/tsunagu/index.ts`, `src/lib/server-adapters/types.ts`, `src/lib/graphql/client.ts`, `src/lib/core/persistence/persist.ts`, `src/lib/platform-adapters/types.ts`, `src-tauri/src/backend.rs`.

## F01 — Content types and app navigation

**iOS status (2026-09-19):** Navigation shell implemented in `Moku/App/Navigation` and `Moku/Features/Profile`. Icon-only floating tabs, compact persistent content-mode selection, and Profile popup menu destinations are wired. Content screens are placeholders; mode selection does not yet filter backend data. Simulator UI tests in `UITests/NavigationTests.swift` verify navigation, persistence, and portrait/landscape control geometry. Spotlight search UI and grouped Profile cards are implemented; keyword search now uses the embedded runtime.

- Manga, novels, and anime in one application and library model.
- Global All / Manga / Novel / Anime content filtering.
- Home, Library, Browse/Search, Downloads, Recent, Extensions, and Settings destinations.
- Series detail and a shared media-viewer entry point that mounts the appropriate manga, novel, or anime viewer.
- Sidebar navigation, window chrome, settings modal, loading/empty/error states, context menus, and toast feedback.

Sources: `src/routes`, `src/lib/components/chrome/Sidebar.svelte`, `src/lib/components/media/MediaViewer.svelte`, `src/lib/types/settings.ts`.

## F02 — Home and personal activity

- Continue/resume hero with cover, title, progress, recent chapter information, and next chapters.
- Four configurable hero slots and a slot picker.
- Recent activity feed linking back to titles and reading/viewing activity.
- Reading statistics including streak, content-type distribution, chapter/episode counts, and time summaries.
- Activity heatmap.

Sources: `src/lib/components/home`, `src/lib/state/home.svelte.ts`, `src/lib/state/history.svelte.ts`.

## F03 — Library browsing and organization

- Save/remove titles; Saved and Downloaded views, including downloaded entries outside the saved library.
- Cover grid and list modes, text search, cover cropping, unread/download counters, and configurable render/page limits.
- Per-folder ascending/descending sorting: alphabetical, unread count, recently read, date added, total chapters, latest fetched, and latest uploaded.
- Per-folder publication-status filters: ongoing, completed, hiatus, cancelled, publishing finished, or all.
- Per-folder content filters: unread, started, downloaded, bookmarked, and tracked.
- Folder creation, renaming, deletion, organization, and title membership; server-backed folder records include hierarchy and update/download participation.
- Hidden/pinned/reordered tabs and default-folder selection.
- Saved-view options for including foldered titles and hiding completed titles.
- Selection mode and contextual/bulk library operations.
- Refresh individual titles, folders, or the library; progress and failed-title reporting.
- Optional automatic movement to the Completed folder when chapters are read, with a disable setting.

Sources: `src/lib/components/library`, `src/lib/state/library.svelte.ts`, `src/lib/components/settings/sections/FoldersSettings.svelte`, `src/lib/components/settings/sections/LibrarySettings.svelte`, `src/lib/server-adapters/tsunagu/folders.ts`, `src/lib/server-adapters/tsunagu/discovery.ts`.

## F04 — Discovery and search

**iOS status (2026-09-19):** `Moku/Features/Search` implements the Spotlight overlay, draft Filter/Sort panels, explicit submit/apply, results/error/empty states, and cancellation. Top controls are Sort, Filter, Close; results are hidden during editing. Normal app sessions use the bundled Go/JVM runtime through `EmbeddedSearchRepository`, with no automatic repository or extension installation. Extensions combines Installed and Browse views, repository management, installs/updates/uninstalls, scoped source search and source preferences. Extension icons use the same authenticated icon proxy as desktop; there is no separate Sources page. Keyword searches fetch page one from selected installed sources. Source/media/language selection and local title sorting are connected; genre/status/tag translation and pagination remain pending and unsupported filters report explicit errors. `LiveSearchTests` opts into network verification; fixture tests remain available for deterministic interaction checks.

- Keyword search across available sources, with per-source results and pagination.
- Browse/search an individual source and pin preferred sources.
- Source-language and media-type filtering.
- Genre/tag browsing and drill-down search; combine tags using AND or OR and filter publication status.
- Source-provided filter controls, including text, selection, checkbox, tri-state, sort, and grouped filters where supported.
- Source-entry previews, series details, and chapter previews before saving a title.
- In-library indicators on search results and content filtering during discovery.

Sources: `src/lib/components/browse`, `src/lib/components/shared/manga/MediaPreview.svelte`, `src/lib/server-adapters/tsunagu/discovery.ts`, `src/lib/server-adapters/types.ts`.

## F05 — Series detail, metadata, and migration

- Cover, description, author/artist, alternate titles, publication status, genres, source, progress, and chapter information.
- Resume/start actions, library membership, folders, and source links.
- Refresh source metadata and chapter lists.
- Search/apply/refresh/unlink external metadata matches.
- Override/refetch covers through a cover picker and server operations.
- Manually link related/equivalent series; optional automatic linking by similar titles.
- Migrate a title to another source; source-level migration UI also exists.
- Series-specific tracker and automation panels.

Sources: `src/lib/components/series`, `src/lib/components/shared/manga/SeriesLinkPanel.svelte`, `src/lib/components/shared/manga/MigrateModal.svelte`, `src/lib/components/extensions/panels/SourceMigrateModal.svelte`, `src/lib/core/cover`, `src/lib/server-adapters/tsunagu/library.ts`.

## F06 — Chapter and episode management

- Chapter list/grid presentations, pagination, ascending/descending order, and source/chapter-number/upload-date sorting.
- Read/completed, downloaded, and saved progress indicators.
- Chapter selection and batch actions for reading state and downloads.
- Per-series preferred scanlator, scanlator filtering/blacklisting, forced preference, and auto-download scanlator choices.
- Chapter/episode picker, previous/next navigation, and progress/resume handling shared across viewers.

Sources: `src/lib/components/series/ChapterList.svelte`, `src/lib/components/series/lib/chapterList.ts`, `src/lib/components/media/shared`, `src/lib/types/settings.ts`, `src/lib/server-adapters/tsunagu/progress.ts`.

## F07 — Manga reader

- Single-page, double-page, automatic layout, and long-strip viewers.
- Left-to-right/right-to-left reading, double-spread offset, and page gap controls.
- Fit to width, height, screen, or original dimensions; zoom and optional pinch gestures.
- Page transition choices: none, fade, slide, and flip, with viewer-specific handling.
- Page-position/progress navigation, previous/next chapter, and chapter selection.
- Automatic page-position bookmarking, read marking at completion, configurable read marking when skipping, and next-chapter loading.
- Page preloading and image/page caching; configurable contrast optimization.
- Reader presets and per-title reader preferences.
- Dockable controls, optional tap-based bar visibility, full-window or containerized reader, and solid/frosted chrome.
- Keyboard shortcuts and touch/swipe handling.

Sources: `src/lib/components/media/manga`, `src/lib/state/mangaReader.svelte.ts`, `src/lib/core/cache/pageCache.ts`, `src/lib/components/settings/sections/ReaderSettings.svelte`, `src/lib/types/settings.ts`.

## F08 — Novel reader

- Formatted chapter rendering with HTML sanitization.
- Paper, Sepia, and Dark reading palettes, independent of the app theme.
- Serif/sans/mono font options and system-font selection; adjustable font size, line height, paragraph spacing, and page width.
- Left/justified alignment.
- Auto-scroll with speed control.
- Reading guide with configurable number of lines.
- Chapter navigation, progress/history recording, and shared reader chrome.
- Persisted novel preferences. The source's “sans” option currently references its monospaced UI font stack; see `DESIGN.md`.

Sources: `src/lib/components/media/novel`, `src/lib/state/novelReader.svelte.ts`, `src/lib/components/media/shared/historyTracking.svelte.ts`.

## F09 — Anime player

- Stream/source resolution, selectable quality/source, and per-series preferred source.
- HTML video playback with HLS/DASH handling paths; actual decoding support depends on runtime and media format.
- Play/pause, seek/scrub, forward/back jumps, volume, playback speed, episode navigation, and automatic next episode.
- Playback-position persistence and resume.
- External and manifest subtitle tracks, language preference, default enablement, subtitle scale, and vertical position.
- ASS subtitle handling alongside simpler subtitle tracks.
- AniSkip intro/outro markers and skip controls when matching data is available.
- Standard controls and compact “Nethermind” transport layout; manual/tap-controlled chrome.
- Experimental WebGL video upscaling with Off/Fast/Quality choices; settings explicitly warn about Linux rendering problems.

Sources: `src/lib/components/media/anime`, `src/lib/state/animePlayer.svelte.ts`, `src/lib/core/video/upscaler.ts`, `src/lib/components/settings/sections/PlayerSettings.svelte`.

## F10 — Downloads

- Server download queue and completed-download history, grouped by series.
- Chapter enqueue/removal and batch management.
- Progress, bytes, speed, completion, and error display.
- Queue reordering by chapter/selection/series, move to top/bottom, and reverse chapter order.
- Retry individual/selected/series/all failed items and optional automatic retry.
- Clear queue/completed records and remove series downloads.
- Download progress toasts and notification preference.
- Storage-limit warning dialog.

These are existing server jobs plus client presentation. Phone-local download manifests, airplane-mode availability, and server-to-device file transfer remain mobile design work.

Sources: `src/lib/components/downloads`, `src/lib/state/downloads.svelte.ts`, `src/lib/server-adapters/tsunagu/downloads.ts`.

## F11 — Automation and library updates

- Enable/disable automation globally and optionally enforce global defaults over per-series overrides.
- Download new chapters on refresh and download ahead while reading.
- Retain a maximum number of chapters; optionally delete downloaded chapters after reading with a delay.
- Default/per-series daily, weekly, or manual refresh preferences, with per-series pause and scanlator options.
- Inspect/reset custom series automation overrides.
- Server library-update initiation/status with counts, current title, and failures.

UI settings and frontend-triggered work are present; this repository alone does not prove that every rule runs autonomously when all clients are closed. Establish execution ownership during the port.

Sources: `src/lib/components/settings/sections/AutomationSettings.svelte`, `src/lib/components/series/panels/AutomationPanel.svelte`, `src/lib/components/media/manga/lib/chapterActions.ts`, `src/lib/server-adapters/tsunagu/discovery.ts`, `src/lib/types/settings.ts`.

## F12 — Recent updates and history

- Recent chapter updates and reading/viewing history tabs.
- Resume/open series from history and updates.
- History cleanup per series and overall history controls.
- Reading-session/time data feeding home activity and statistics.
- Shared progress tracking for the media viewers.

Sources: `src/lib/components/recent`, `src/lib/state/history.svelte.ts`, `src/lib/components/media/shared/historyTracking.svelte.ts`.

## F13 — Trackers and list import

- AniList authentication through the server, with browser authorization and redirected-URL input.
- Search/link/unlink tracker entries to local series.
- Read/update tracker status, chapter/episode progress, score, start/finish dates, and private flag; resync linked entries.
- Configurable reverse progress sync, threshold, and scanlator-respecting behavior.
- AniList list import with status/media selection, source matching, review/manual search, excluded entries, retries, and resumable drafts.
- Import matched source titles or library stubs; dry-run mode.
- MyAnimeList sync is explicitly unavailable in the tracking settings. MAL IDs/URLs used for metadata or skipping do not establish MAL account-sync support.

Sources: `src/lib/components/settings/sections/TrackingSettings.svelte`, `src/lib/components/series/panels/TrackerPanel.svelte`, `src/lib/components/tracking/TrackerImportModal.svelte`, `src/lib/components/tracking/trackerImport`, `src/lib/state/trackers.svelte.ts`, `src/lib/server-adapters/tsunagu/trackers.ts`.

## F14 — Repositories, extensions, and local sources

- Add/remove extension repositories and refresh their indexes.
- Repository families described by Moku include Mihon/Tachiyomi, Aniyomi, and LNReader; execution/compatibility is provided by Tsunagu.
- Browse/filter extensions by media/language and installation state; language variants.
- Install/uninstall and update extensions, including update-all and installation from an external extension URL.
- Source-specific preference panels and source-library inspection/migration.
- Local source browsing and rescan without a remote content extension.
- Desktop local file/folder import with media-type detection, copying, progress, and rename support.
- Import classification recognizes manga images and CBZ/ZIP, video file extensions, and text/HTML/EPUB/Markdown extensions. Recognition does not guarantee decoding of every file or format.

Sources: `src/lib/components/extensions`, `src/lib/server-adapters/tsunagu/extensions.ts`, `src/lib/server-adapters/tsunagu/repositories.ts`, `src/lib/core/localImport.ts`, `src/lib/server-adapters/tsunagu/library.ts`.

## F15 — Content filtering

- Strict, Moderate, and Unrestricted levels, with server filtering across library/search/discovery.
- Inspect/manage/reset filter rules by category, keyword, field, weight, and block level.
- Rule fields include genre, tag, title, and description.
- Per-source force-allow/always-block overrides.

Sources: `src/lib/components/settings/sections/ContentSettings.svelte`, `src/lib/server-adapters/tsunagu/contentFilter.ts`, `src/lib/server-adapters/types.ts`.

## F16 — Storage, backup, and maintenance

- Server/local storage usage, free space, category breakdowns, cache clearing, and extra scan paths.
- Download/local-source path configuration and relocation/migration where supported.
- Manga chapter storage format selection and conversion of existing downloads to the selected format, including CBZ.
- Configurable storage-warning threshold.
- Full server SQLite backup listing, creation, and deletion; server settings expose backup configuration.
- Mihon/Tachiyomi `.tachibk` library export/import; UI explicitly limits export to manga and novels, excluding anime.
- Desktop app-settings ZIP export/import and pre-update backups (UI describes retention of the last five).
- Reset/cleanup controls for app/server data; native dialogs and filesystem operations where supported.

Server backups, library exchange files, app-settings backups, and offline media are separate concepts with different coverage. Do not promise that one backs up everything.

Sources: `src/lib/components/settings/sections/StorageSettings.svelte`, `src/lib/server-adapters/tsunagu/storage.ts`, `src/lib/core/backup.ts`, `src-tauri/src/commands/backup.rs`, `src-tauri/src/commands/storage.rs`.

## F17 — Server connection, authentication, and administration

- Configurable server connection and startup flow; desktop supervision of bundled Tsunagu.
- Server authentication, persisted sessions, password configuration, and static-token interoperability.
- App-lock PIN independent of server credentials; Windows Hello option where supported.
- Server version/status and editable server settings, with live/restart-required distinctions.
- Cloudflare solver installation/status controls when supported by the server platform.
- Backend logs and connectivity/startup errors.

Sources: `src/lib/state/boot.svelte.ts`, `src/lib/state/auth.svelte.ts`, `src/lib/components/settings/sections/AuthSettings.svelte`, `src/lib/components/settings/sections/ServerSettings.svelte`, `src/lib/components/chrome/BackendLog.svelte`, `src/lib/server-adapters/tsunagu/auth.ts`, `src-tauri/src/backend.rs`.

## F18 — Appearance and interaction preferences

- Five implemented application themes: Original, Dark, Light, Midnight, Warm; Dark is the initial default.
- Custom theme editor with named themes and JSON import/export.
- Optional system appearance matching with configurable dark/light theme choices.
- Solid or frosted reader/player controls.
- UI zoom, animation preference, cover presentation, idle splash, and animated cover-card background.
- Customizable keyboard bindings and reader interaction preferences.
- Desktop hover/tilt and compact control treatments.

The README's High Contrast claim and the `light-contrast` type entry do not correspond to an implemented selectable palette. Exact colors, defaults, discrepancies, and novel-reader themes are documented in `DESIGN.md`.

Sources: `src/lib/styles/themes.css`, `src/lib/components/settings/ThemeEditor.svelte`, `src/lib/components/settings/sections/AppearanceSettings.svelte`, `src/lib/core/keybinds`, `src/lib/types/settings.ts`.

## F19 — Onboarding, notifications, and desktop integrations

- Welcome/onboarding flow and guided tour for navigation, searching, content types, sources/local files, settings, and tracking.
- Toast/notification state for app activity, downloads, successes, and failures; this is not evidence of mobile push notifications.
- Idle splash and app-lock presentation.
- Discord Rich Presence for title/chapter and elapsed time on supported desktop runtime.
- App version, release/changelog fetching, update checking/install flow, and restart through the desktop adapter.
- Native window controls/fullscreen and close/tray/quit handling.
- Bug-reporting UI and developer controls for test toasts, replaying onboarding, changelog/splash previews, biometrics, and runtime/cache diagnostics.

Sources: `src/lib/components/onboarding`, `src/lib/state/onboarding.svelte.ts`, `src/lib/state/notifications.svelte.ts`, `src/lib/components/chrome`, `src/lib/core/discord.ts`, `src/lib/components/settings/BugReporter.svelte`, `src/lib/components/settings/sections/DevToolsSettings.svelte`, `src/lib/platform-adapters/tauri/adapter.ts`, `src-tauri/src/commands/updater.rs`.

## Bundled backend requirement — 2026-09-19

The user requires Tsunagu to ship with Moku-iOS and start automatically, requesting a separate process as on desktop. This supersedes the earlier external-server proposal. Preserve the bundled/on-device requirement; do not silently replace it with a remote-server dependency. The later accepted native bridge direction uses an in-process Go library; JVM startup and MangaDex search now work in the iOS simulator; physical-device execution remains unverified.

Initial inspection of sibling `Tsunagu` at `1992fea656f4bfe5e9345280c8949dd99c0854f0` found:

- `backend/cmd/server/main.go`: Go server initialization, database/services, and supervised sandbox setup.
- `backend/internal/sandbox/lifecycle.go`: launches Java using `os/exec` and communicates with the sandbox through gRPC.
- `sandbox/build.gradle.kts`: Kotlin/JVM, Java 21 toolchain, dex2jar, and GraalJS dependencies.
- `sandbox/src/main/kotlin/tsunagu/loader/ExtensionLoader.kt`: converts APK bytecode where needed, dynamically loads JAR classes, and instantiates source implementations.
- `sandbox/src/main/kotlin/tsunagu/novel/NovelPluginLoader.kt`: GraalJS contexts for novel plugins.
- `backend/internal/download/manager.go`: FFmpeg subprocess paths for some video downloads.
- `backend/internal/flaresolverr/manager.go`: external solver process management.

An embedded Go library is a candidate for preserving local backend behavior, not a verified complete port. It does not solve the JVM extension loader or other subprocess dependencies. Do not treat desktop ARM64 binaries, simulator success, or a Go binding alone as evidence that this process chain works on an iPhone. A device feasibility milestone is needed before promising full source compatibility.

## Current backend decisions and implementation status — 2026-09-19

The user subsequently chose runtime extension downloads for the feasibility prototype, superseding the earlier bundled-source-only decision. Tsunagu itself remains bundled/on-device. App Store distribution is still intended, but eligibility of downloadable extensions remains unresolved and is not claimed by this implementation.

The accepted native bridge direction runs Go inside the app process rather than launching a Go executable. Source-built OpenJDK Zero now runs alongside Go in the iOS simulator. Physical-device execution remains unverified. Preserve repository installation and runtime updates as future backend requirements rather than removing them from the plan.

Implemented first stage: `services` contains a Swift actor, generated-framework build scripts, and a reproducible additive patch for the pinned Tsunagu checkout. The public Go `mobile` package reuses Tsunagu's SQLite initialization and all 17 migrations, with start/stop/status and authenticated loopback health/status endpoints. Go lifecycle/race tests and a real Swift-to-Go macOS smoke test pass; device/simulator ARM64 framework slices build and the Swift wrapper typechecks for both iOS targets.

The restricted upstream GraphQL catalog, installation, and search APIs now run in an ARM64 iOS simulator. A fresh test imports Keiyoushi, downloads MangaDex 1.6.0 as a JAR, installs it into the embedded Kotlin sandbox, and searches “Rent a Girlfriend”; results include “Rent-A-Girlfriend” and its official anthology. Source-built OpenJDK Zero fixes CodeCache permissions and iOS platform recognition. APK conversion, media delivery, broad extension compatibility, background transfers, and physical iPhone execution remain unverified. See `services/README.md` for reproducible commands and limits. No product frontend changes were made.

## Mobile translation — discussion draft, not committed scope

| Area | Proposed mobile treatment | Decision still needed |
| --- | --- | --- |
| Backend | User requires Tsunagu bundled and automatically started on device; requested separate-process execution | Desktop process model needs iOS feasibility work; an external server is not the chosen baseline |
| Navigation | Phone tabs for Home, Library, Browse, Downloads; settings via toolbar; Recent under Home | Final destination names and prominence |
| iPad | Adapt navigation to a sidebar and use available space for library/detail panes | Required iPad parity for the first release |
| Library/series | Preserve organization and metadata; use sheets, menus, and explicit selection for dense controls | Which advanced controls belong in the first release? |
| Readers | Full-screen content, touch navigation, reachable controls, and native text scaling | Launch with all three viewers, or prioritize manga? |
| Downloads | Clearly separate server files from copies saved on this device | Offline retention, cellular policy, and deletion semantics |
| Progress | Queue device changes while offline, reconcile on reconnect | Conflict resolution and authoritative state |
| Sources | Runtime repository/extension downloads for the prototype | Embedded JVM compatibility, supported catalog, and App Store eligibility |
| Automation | Assign server scheduling and device transfers explicitly | Which existing rules truly run on server versus active client? |
| Auth | Native credential storage and device biometrics | Reauthentication and app-lock behavior |
| Themes | Carry over semantic palettes; adapt sizing and materials | Native chrome vs custom chrome styling |
| Desktop extras | Reassess tray behavior, updater, Discord RPC, arbitrary disk paths, and hover effects | Omit, replace, or keep only remote administration |

Phone-local offline storage, background transfers, Files/share-sheet import, Face ID/Touch ID, and progress conflict handling are proposed mobile work, not inherited completed features. Likewise, AirPlay, picture-in-picture, widgets, push notifications, and cloud sync must not be marked supported without implementation and validation.

Apple references for later implementation: [adaptive tab/sidebar navigation](https://developer.apple.com/design/human-interface-guidelines/tab-bars) and [background downloads](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background). Background URLSession transfers can continue while an app is suspended; that does not make arbitrary continuous client automation available.

## Maintenance

When a feature changes, update its stable group, source pointer, limitations, and baseline commit/date. Add explicit iOS status only after implementation (for example: planned, in progress, implemented, verified), together with relevant Swift source and validation. Keep future ideas in the discussion section until scope is agreed. Never promote a README claim, unused setting, or backend API declaration into a verified mobile capability.
