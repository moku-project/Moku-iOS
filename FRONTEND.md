# Swift frontend foundation

The project contains an icon-only floating navigation shell with a compact mode
picker, native Home dashboard, Spotlight search interface, and compact Settings and Profile pages.
Library has a mode-aware landing page. Downloads has a native queue/history interface; Recent has native History and Updates views; More → About remains a placeholder. Extensions and Sources
are connected to the embedded backend. The full theme
system remains pending. Search links the embedded Go/JVM service and starts it
on first use, entirely on-device.

## Open and build

Open `Moku.xcodeproj` and select the shared `Moku` scheme. Targets are named
`Moku`, `Tests`, and `UITests`. The deployment baseline is iOS 18.2, matching the
native service probe's minimum, with iPhone and iPad enabled. Swift 6 language
mode and complete concurrency checking are enabled.

The checked-in project can be opened without XcodeGen. `project.yml` is its source
of truth; after adding files or changing target configuration, regenerate it.

Use the in-repo Swift tool; it prepares missing/stale backend inputs before app builds:

```sh
./moku-ios dev                         # Simulator + watch/relaunch
./moku-ios run                         # One build/install/launch
./moku-ios build --platform device     # Signed device build, no deployment
./moku-ios generate                    # Regenerate project explicitly
./moku-ios format                      # Lint Swift formatting
./moku-ios test unit
./moku-ios test ui
```

Apple Silicon, Xcode, XcodeGen, Go, and the Java toolchain described in
`services/README.md` are required. `./moku-ios doctor` checks local prerequisites.

Generation was verified with XcodeGen 2.44.1. Keep the generated project and shared
scheme with the spec in version control; make project changes in the spec or
xcconfig files so regeneration preserves them. Developer UI state and build outputs
are local. Frontend builds copy the prepared JVM resources and sandbox JAR and
link the combined native archive; missing inputs fail the build with a clear error.
Only arm64 is currently supported. `ENABLE_DEBUG_DYLIB=NO` keeps JVM symbols in
the executable; the exploded `lib` directory must remain at the app bundle root
for JVM boot class-path discovery.

Keep `ENABLE_DEBUG_DYLIB=NO` in Debug as well as Release. The statically linked
OpenJDK uses `dlopen(nil, RTLD_FIRST)` for JNI lookup on Apple platforms, which
searches only the main executable. Enabling the debug dylib moves the JNI symbols
out of that executable and can crash `ZeroInterpreter::main_loop` during
`JNI_CreateJavaVM`. `EmbeddedRuntimeLinkageTests` checks this lookup contract in
the app test host. Modern Canvas execution that requires a debug dylib is not
compatible with this runtime configuration; use legacy previews where supported
or run the app in Simulator for integrated checks.

Keyboard console warnings involving only `_UIRemoteKeyboardPlaceholderView`,
`_UIKBCompatInputView`, `accessoryView.bottom` (-17), and `inputView.top` (0)
describe contradictory constraints inside UIKit's keyboard. These were observed
on iOS 26.5 Simulator with hardware keyboard input enabled. Check the debugger's
actual stop reason independently: those warnings are separate from a JVM startup
SIGSEGV. To compare keyboard behavior, test with Simulator → I/O → Keyboard →
Connect Hardware Keyboard turned off and the software keyboard shown. Do not
change app spacing or deactivate private UIKit constraints to silence this log.

`com.moku.app` and the current signing team are preserved in `project.yml`.
Other developers should configure their own team before physical-device deployment. App icons, release metadata, and any required privacy
declarations must be provided when product capabilities are implemented.

## Ownership and dependencies

See [Architecture and codebase walkthrough](ARCHITECTURE.md) for the current
hierarchy, MVVM conventions, state ownership, and test layout.

- `App`: composition, lifecycle, profile sessions, and navigation.
- `Features/<Feature>`: screen and ViewModel, plus Components, Domain, and Data
  where that feature needs them. Details is independent of Search UI.
- `Shared`: multi-feature media contracts, profile/library/activity stores,
  reusable components, theme, backend transport, cache, and storage helpers.
- `Preview`: shared Debug-only fixtures and fake repositories.
- `Resources`: assets and string catalogs.

Domain describes values and contracts; Data implements storage/transport. Views
render state and ViewModels coordinate actions. These remain folders in one Swift
module. Preserve state lifetime, cancellation, and actor isolation when extracting
components. Never put backend startup in a view's render body.

## Swift conventions

Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
Use UpperCamelCase for types, lowerCamelCase for members and cases, descriptive
Boolean names (`isLoading`), and conventional acronym casing (`seriesID`, `coverURL`).
Name files after their primary type. Keep implementation private and avoid needless
public declarations. Prefer value types for data and explicit dependency injection
at actual boundaries.

Use small SwiftUI views and local `@State`. Introduce `@MainActor @Observable`
presentation models for coordinated screen state or asynchronous work; simple
components do not require models. Use structured concurrency, explicit isolation,
and cancellation. Async functions do not automatically move blocking native work
off the main actor. Represent loading, empty, error, and content states deliberately.
Keep backend persistence and client preferences separately owned.

Formatting uses four spaces and a 100-column target, enforced with Apple's
`swift-format`. The configuration lives at `Configuration/swift-format.json` because
this repository's local ignore rules exclude dotfiles. To apply formatting:

```sh
./moku-ios format --fix
```

Use Swift Testing in `Tests` and XCTest UI automation in `UITests`. Navigation UI tests cover tab switching, More menu routing, persisted mode
selection, dismissal on selection, and button geometry in portrait and landscape.
Run `./moku-ios test ui --simulator UDID` to execute them.
Formatting and simulator builds remain the initial CI checks.
Support Dynamic Type, VoiceOver, localization, and reduced motion during UI design.


## Floating navigation

`RootView` retains a navigation stack per tab. The five destinations are Home,
Library, Browse, Downloads, and a More menu. The menu opens Profile, Recent, Tracking,
Extensions, Settings, and About. Profile itself contains only identity
and personal details. Recent has native History and Updates views; More → About remains a placeholder. Mode selection
(All, Manga, Novels, Anime) persists via AppStorage and will feed feature filtering
when data integration is added. Library has a mode-aware landing page with a
visible current-mode label and title. Selecting a mode opens Library, and a normal
Library tap returns to that same mode. Saved titles are loaded from the active profile’s local library.

The main bar expands to at most 336 × 60 points and compacts to 300 × 52 points
on downward scroll, expanding on upward scroll with a Reduce Motion-aware spring.
It sits 12 points lower into the bottom safe area with 2 points of top spacing.
The footer is transparent and the island uses lightly tinted material. Content
scrolls behind it; the scrollbar ends 4 points above the island, following its
expanded or compact height and lowered bottom position. Content margins keep the final item accessible above the island.
The expanded mode picker
is 200 by 44 points with 12-point corners, deliberately smaller and flatter. There
are no visible labels or chevrons on the islands; VoiceOver labels and selection
traits remain available. All controls have at least 44-point hit regions. Holding
Library for 0.3 seconds opens the mode picker above the bar; a normal tap opens
Library. A small badge at the top right of the Library icon shows the current mode.
There is no separate mode button or reserved picker space while it is closed.
Selecting a mode, tapping outside, or selecting a tab dismisses the picker.
VoiceOver also exposes a “Choose content mode” action on Library.

More opens a trailing-aligned floating panel 8 points above the navbar. The main
tabs remain interactive while it is open. Selecting a destination, selecting another
tab, or tapping outside dismisses it; tapping More again toggles it closed.
More and mode selection are mutually exclusive. The More panel scrolls in
compact-height layouts to stay above the bar and within the safe area.

A bottom safe-area inset reserves content space with 16-point side padding and
8-point bottom breathing room above the system safe area. Only the background
ignores safe areas. Reduced Motion removes picker animation; Reduced Transparency
uses a solid island background. Navigation uses the dark baseline pending the full
theme implementation. Browse opens Spotlight search over the current tab and closes
back to that tab without changing its navigation stack.


## Spotlight search and Profile

`Features/Search` owns the search model, request/options types, and repository
contract; `AppDependencies` supplies `LiveMediaRepository`. Normal sessions
start the bundled runtime, connect through authenticated loopback GraphQL, and
search installed sources. Fresh installations have no repositories or extensions. Add a repository and
explicitly install an extension from the More menu → Extensions. Opening search
never installs anything. Existing installations are preserved. No sample entries ship in
the Release search path. Debug UI tests opt into deterministic fixtures with
`--ui-testing-search`; fixtures are not a backend verification.

`LiveSearchTests` uses an isolated empty database and exercises repository addition,
explicit MangaDex installation, source search, uninstall, and the empty Sources state. Opt in with
`./moku-ios test live-ui`.
The runtime stays alive for the app process; a native startup failure requires an
app restart. HTTP credentials are headers only and redirects are refused.

Search opens with no results. Typing searches after a 350 ms pause. Submit or Apply
searches immediately and cancels any pending debounce; opening Sort or Filter hides results while choices are edited.
Cancel discards the draft. Changing the query cancels and invalidates old results.
Global search publishes completed sources while slower sources are still running,
with at most three source requests active. Results retain the selected sort order;
a failed source does not discard successful results. A progress indicator remains
visible until the remaining sources finish. Closing, filtering, or editing the
query invalidates both late progress and final responses.
Only Sort, Filter, and Close appear in the top-right control row. A separate input
floats 24 points above the keyboard safe area; panels scroll within the available
height. The background blurs and is inaccessible while the overlay is active;
Reduce Transparency substitutes an opaque backdrop.

Filter groups keyword/tag/source search, media, available source languages,
source selection (pinned sources first), the desktop genre catalog with genre
lookup and all/any matching, and multiple publication statuses. Source and language
choices come from the repository. Source search requires a chosen source. Sort
supports source order and ascending/descending title among returned entries; it
does not imply global ordering across unloaded source pages. Real pagination,
source-specific genre/status/tag translation, content-safety settings, media-detail integration remain pending. Unsupported filters
report an explicit error rather than being ignored. Search currently fetches the
first page per selected source. Covers in search rows, the detail sheet, and Home
load through the authenticated embedded image proxy. Relative proxy paths and
absolute HTTP(S) covers are supported; loading and unavailable images have
placeholders. Image data is cached in memory (32 MB budget).

Profile uses a compact identity row and a list of local profiles. Create, rename,
and switch profiles without a server login. Each UUID scopes a preferences suite,
Home activity, and the saved-title list; installed sources and their preferences
remain shared. The existing profile name, Library mode/layout, and Home file are
preserved when the default profile is first created.

SearchModelTests cover debouncing, immediate submit, clear/close cancellation, draft
isolation, request options, sorting, and incompatible source selection. CoverURLTests
cover relative paths, URL encoding, and rejection of unsupported image paths. SearchTests cover explicit submit, results
hidden during editing, filter application, top control ordering, keyboard spacing,
and Profile editing. NavigationTests continue to verify the shared navbar.


## Unified Extensions

Extensions supports HTTPS repository index URLs, rename, refresh, and removal;
search with repository/media/language filters; paginated catalog loading; explicit
install, update, and uninstall. Removal of a repository is disabled while it has
installed sources. Mutation failures remain visible and can be retried. Catalog
refresh discovers updates; updating an extension is an explicit action.

The single Extensions page defaults to Installed, with Browse for the paginated
catalog. Both views share repository/media/language filters. Installed rows open
source-scoped Spotlight search and expose source settings, updates and uninstall.
Source settings retain switch/list/multiple-choice/text preferences and restoring
defaults. Repositories are managed in an expandable section. There is no separate
Sources navigation destination; Settings also links to this unified page.

Extension queries request the desktop's `iconUrl` field. `/proxy/icon/{id}` is
loaded through the authenticated loopback image client, bounded connection pool,
memory/disk cache and off-main image decoder, without starting Java. Icons use
aspect-fit independently of cover-cropping preferences, with a puzzle-piece
fallback when missing/unavailable. Existing repository data is unchanged.

Validation: 10 targeted Swift tests passed for proxy URLs, authenticated core
startup and incremental extension loading. The unified-page UI test covers
source search, source settings, install/uninstall and opening Add repository;
the navigation-during-runtime-startup test also passed. Normal simulator data
showed both saved repositories and the 1,651-entry catalog, with real MangaDex
and catalog icons displayed and cached by the backend.


## Fast simulator development

For layout work, use the existing `#Preview` blocks in Xcode's canvas. SwiftUI
previews refresh as views change. Keep live backend startup out of preview-only
fixtures; the embedded JVM can only initialize once per process.

For the full app with real sources, use the in-repo Swift tool:

```sh
./moku-ios dev                           # Watch and relaunch after saved edits
./moku-ios run                           # Build/install/launch once
./moku-ios dev --simulator SIMULATOR_UDID
```

This automatically rebuilds/relaunches the app; in-memory navigation state resets,
while installed extensions and app data persist. Ctrl-C stops the watcher. The CLI
reuses `.build/frontend`, caches native build inputs, and regenerates the Xcode
project when `project.yml` changes. Swift-only edits do not rebuild Go, Kotlin,
or OpenJDK. Backend source edits invalidate the relevant cached components.
Xcode calls the CLI's internal `embed-backend` command to copy only changed resources.

Use `./moku-ios backend go`, `./moku-ios backend jvm`, or `./moku-ios backend sandbox`
to force a specific native rebuild; the next app run refreshes the combined archive.
The first simulator build/install can be slow. Use a physical phone for device-specific
verification and performance checks. [CLI reference](Tools/MokuIOS/README.md).


## Home

Home implements the approved mobile layout: four swipeable resume/pinned slots,
upcoming chapters, recent activity/history, a scrollable 12/26/52-week heatmap,
streaks, six statistic tiles, and a media breakdown. Empty sections retain their
structure with gray surfaces, “Nothing here yet”, “No chapters to show”, and zero
statistics. There is no onboarding slogan or fabricated live history.

`HomeStore` persists a Codable snapshot to Application Support/Moku/home.json.
`record(_:entry:)` accepts reader session updates by stable ID, while `pin(_:slot:)`
maintains slots 2–4. The first slot always resolves to the most recently read title.
Malformed history is preserved and reported rather than overwritten. Statistics
use local calendar days; recent history deduplicates series for the Home feed.

Reader and Player record activity through the shared activity adapter. Home uses
that profile-local history for resume slots, recent activity, and statistics.
Its optional `onResume` callback remains the boundary for launching playback from
Home; availability of that action depends on the caller wiring it. Cover loading
uses the shared authenticated image pipeline.


Debug previews and `--ui-testing-home-populated` use isolated in-memory sample
history; `--ui-testing-home-empty` likewise avoids the user's history file.
Neither argument changes Release behavior. Native UI screenshots are stored under
`design/home-review/implemented/` and are separate from generated design concepts.


## Library template

Library now has a capsule tab strip with matching text/count fonts, a compact
Search field, and independent desktop-style Sort, Filter, and More dropdowns.
The mode control beside the left-aligned heading uses the same persisted
`contentMode` as the navbar. Its vertical island overlaps the trigger and places
the current selection first. Covers have no media-type corner badges.

`LibraryViewModel` filters items supplied by the profile-local `ProfileLibrary`.
When the selected media mode has no saved items, Library shows a centered book
outline, “Nothing here yet”, and “Titles you save will appear here.” on the open
background. The sage “Browse titles” button opens the existing Spotlight search
with the selected media mode. Header and tabs remain visible; the search/sort/filter
toolbar appears when there are saved items or an active query/filter. No preview
titles are generated. Search, filters, and empty tabs within a populated library
retain their no-match states. Grid/list preference persists locally. Refresh and
Sync explain that data integration is pending.


### Library visual refinement

Use the header's system sans-serif family throughout app UI, including dropdowns;
menu section labels use normal capitalization, never forced uppercase. Library
tabs use 10-point container corners and 6-point selection corners. Toolbar search
and individual buttons are 44 points high with 4-point gaps. The mode trigger stays
visible while its dropdown opens below it, with an animated chevron that respects
Reduce Motion. This supersedes the earlier capsule tabs and monospaced menus.

Main pages use `PageHeader`: a centered title, a top-left Profile button, and
an optional right-side action. Equal side slots keep the title centered. Library's
media control is a plain label and chevron without a pill background. The bottom
More tab uses an ellipsis and collects global destinations. Tracking now exposes service
connections and AniList import using the embedded tracker APIs; its connection and import
controls live in popups. MyAnimeList remains marked Coming soon.


### Page headers

The shared page header is a plain three-column row: a 44-point profile control,
a flexible centered title, and an always-present 44-point trailing slot. The
trailing slot reserves its width even with no control, keeping titles centered
on every page. Library uses a white chevron to open its media menu below the
header, with the current mode in its accessibility label.

Header artwork uses the available header width: profile/settings icons are
20.4 points below 400 points (including iPhone 13 Pro portrait) and 24 points
on wider layouts (including iPhone 17 Pro portrait). Back arrows use 14.5 and
17 points respectively. PhosphorIcon applies Dynamic Type once; parent header
metrics do not pre-scale icon sizes. Button hit areas remain 44 by 44 points.

### Profile and Settings navigation

The header’s profile and Settings buttons open full pages within the app shell,
with the shared header and floating navbar. They do not use sheets. Selecting a
navbar destination returns to that tab, retaining its existing navigation state.
Settings opens a plain icon/name/chevron index. Each section pushes a page with a back button. Profile uses a
small identity row and profile list. Both keep content text below the shared
22-point header title in size.
Neither Profile nor Settings belongs to More;
More contains Recent, Tracking, Extensions, and About, and uses the
`DotsThreeCircle` Phosphor icon in the navbar.


### Search results and title details

Search results sit directly over the blurred app with 88 × 126 covers and smaller
right-aligned-column metadata. Loading leaves the result area clear; an empty
response displays “No results”. Result taps open a full-page native title view
and Back returns to the preserved search. The details layout follows desktop’s
cover/metadata and chapter columns, stacking below 700 points. It resolves source
metadata and chapters through `resolveMedia` and saves library membership using
`setInLibrary`. Chapter text filtering, order reversal, and refresh are available.
Manga chapter rows open the native reader; desktop’s advanced Manage actions remain pending.
Reduced Transparency retains its solid-background accessibility fallback.


### Search startup responsiveness

Opening Spotlight only displays and focuses its UI. Source choices are loaded
when Filters opens; submitting a query resolves its sources through the repository.
Concurrent filter-source requests share an in-flight task, and canceled views do
not publish its result. JVM startup runs on `moku.jvm.startup`; Go construction,
startup, connection-property reads, cleanup, and shutdown run on the serial
`moku.go.lifecycle` queue rather than Swift’s cooperative executor. Both native
queues assert that they are not the main queue. The process-wide JVM startup
remains single-flight, including cached failures.


## Settings and device-local profiles

`SettingsView` lists all 16 desktop sections in their desktop order. General,
Appearance, Library, Storage, and About contain working mobile settings; the
remaining sections retain dedicated pages with concise availability notes.
Functional preferences: source language for global search, interface animations
(respecting system Reduce Motion), Midnight/Charcoal/Sepia palettes, solid menu
surfaces, cover crop/fit, Library mode and list layout, card progress display,
and default chapter order. Storage displays app data, cover cache, and available
space; confirmed actions clear only cached covers or the active profile's reading
history, or reset only that profile's preferences. File operations run on actors.

Desktop window controls, external-server configuration, keyboard shortcuts,
Discord presence, GPU controls, and folder scanning are omitted from General.
General uses the approved desktop panel styling: headings inside 7-point bordered
panels, 8-point panel gaps, thin dividers, right-aligned controls, and system sans-serif
text with normal capitalization. Its working controls include 50–200% interface
scale (slider, numeric entry, presets, reset), the bundled server address and
manual/automatic startup, idle timeout (Never/1/2/5/10/15/30 minutes), interface
animations, freeform normalized source language codes, and Extensions navigation.

Interface scale adjusts layout proposals and drawing together; large-scale rows
can stack controls without clipping. Reader full-screen and containerized modes
retain their own zoom. Idle tracking is passive, stops in the background or when
Never is selected, and pauses for readers, modal playback and assistive navigation.
The idle screen dismisses on an explicit tap. Scale, idle timeout, animations and
language are profile-scoped and included in Reset preferences. Automatic server
startup is device-scoped because the backend is shared; disabling it gates future
startup requests without interrupting a running server. Starting manually boots
only the local core; Java remains deferred until a source operation requires it.

Validation: three General settings unit tests and the simulator persistence/UI
flow pass, covering idle deadlines, media/background suppression, language
normalization, scale/reset navigation and saved settings after relaunch. Manual
simulator verification confirmed the approved side-by-side panel layout and
starting the local server from General. Simulator and signed device builds pass.

Reader settings are functional and shared with the contextual reader drawer.
Automation/download and tracker sections retain availability notes until their
frontend controls are connected. Desktop-only
sections also remain in the index. No inactive preference controls are shown.

Tsunagu's auth manager is a single-server password/session gate, not a multi-user
identity or data partition system. Its embedded API uses a per-start loopback token.
`ProfileStore` therefore supplies local identities rather than reusing auth tokens
as profile IDs. Profile switching remounts the UI with a UUID-scoped UserDefaults
suite, `HomeStore`, and `ProfileLibrary`. The source runtime is not restarted.
These profiles organize local data; they are not password-protected accounts and
do not sync across devices. Source installations/preferences and cover caches are
shared. The default Home file remains at its legacy path; other profiles use
`Application Support/Moku/Profiles/<UUID>/home.json`. Each library is a separate
`library.json` in that profile directory. Catalog data in Tsunagu stays shared;
saved-title membership is owned by ProfileLibrary and not the server's global flag.

ProfileStoreTests exercise manifest persistence, preference isolation, corrupt-file
preservation, and saved-title isolation. SettingsProfileTests exercise settings,
theme selection, creation/switching, preference isolation, and active-profile
restoration after relaunch. Debug UI tests use isolated directories and suites.

The Settings index uses plain rows (icon, section name, chevron) without card
backgrounds or descriptions. Section pages use a centered heading and Back to
Settings button. SettingsProfileTests opens and returns from every desktop section.


### Contextual Settings and Profile navigation

Settings and Profile now use `BackHeader` with a centered title and a single
back control, without the global Profile/Settings shortcuts. RootView retains
an ordered stack of account pages over the original tab stack. Back pops that
stack and reveals the prior page, preserving its scroll/filter/selection state.
Settings → Auth → Profile → Back returns to Auth before returning to the original
tab. Tab navigation explicitly closes the account stack. The Settings index has
no separators, 17.5-point labels, 21.25-point section icons (25% larger), and
64-point rows. Profile content is also 25% larger with more spacing and no dividers.

## Native video player

Anime episode rows open `Features/Player/PlayerView.swift` full screen. It adapts
its floating header and sage playback timeline between portrait and landscape,
with episode, subtitle, source, and speed menus. `PlayerViewModel` owns AVPlayer and
coordinates loading, seeking, progress resume/save, and playback lifecycle;
`LivePlayerRepository` resolves media through the existing GraphQL/content
proxy contracts. VTT/SRT external subtitles have size, position, and background
controls. AVPlayer codec support applies; DASH and ASS/SSA are not implemented.
Implementation screenshots and validation notes live in
`design/player-review/implemented/README.md`.


## Phosphor icons and manga reader

App-authored controls use native asset-catalog images from the same
`phosphor-svelte` 3.1.0 artwork as desktop. `PhosphorIcon` supplies regular, light,
and fill weights, template tint, and Dynamic Type scaling. The pinned importer
and MIT notice are included; no runtime SVG parser or SF Symbols fallback is
used. System-owned controls such as the keyboard retain platform rendering.

Manga chapter rows open a native reader with desktop layout/fit/direction controls,
plain arrow navigation, chapter filtering, page jump, bookmarks, progress resume,
and chapter download actions. A Sliders button opens the trailing settings drawer
with a reduced-motion-aware slide animation. Global defaults, per-manga overrides,
and presets share the same settings component. The canvas supports strip,
single/double/automatic spreads, bounded page prefetch, pinch zoom, contrast,
auto-scroll, and chapter advance. See `Moku/Features/Reader/README.md` for service
contracts and native rendering differences, and
`design/reader-player-review/implemented/README.md` for actual simulator captures.

Reader model, persistence, image validation, and bundled icons are covered by
`Tests/Features/Reader/ReaderTests.swift`. `Tests/UI/ReaderTests.swift` exercises portrait,
landscape, drawer controls, chapter selection, and saved settings after relaunch.
These use deterministic fixtures; they do not certify live provider availability.


### Source chapter availability

Title metadata now loads separately from the explicit `syncChapters` request.
A failed chapter refresh preserves the cover, description, and any previously
loaded chapter list, with a separate retry message. A successful empty list is
shown as source unavailability; a filter with no matches offers Clear filter.
MangaDex title pages are linked from the empty state so publisher-only listings
can be inspected directly. No chapter availability is inferred from a cover or
successful search result.

`SearchDetailTests` covers empty responses, chapter failures and retry, preserving
loaded chapters after a failed refresh, independent metadata decoding, and source
link validation. `MangaSourceDeviceTests` is an opt-in live diagnostic; set
`MOKU_LIVE_MANGA_CHECK=1` in the Tests target environment of the generated
`.xctestrun` file and select that test with `test-without-building`. It requires
MangaDex to be installed, compares the embedded Nagatoro chapter count with the
provider feed excluding external-only publisher links, and decodes the cover
through the actual embedded HTTP service. Default test runs skip this live check.


Physical-device verification (September 20, 2026): the live MangaDex diagnostic
passed on the connected iPhone 13 Pro. Nagatoro returned 0 readable English
chapters from both the provider feed and embedded service; its 1,405,802-byte cover
was fetched through the app service and decoded successfully. The 12 focused
ReaderTests/SearchDetailTests passed on that device and in Simulator. The live
result is a point-in-time provider observation, not a permanent availability
assertion or proof that every MangaDex title can stream pages.


### Extension loading recovery

The Extensions screen preserves successful repository, installed-source, and catalog
responses independently. A failure in one request no longer erases the other
sections or displays “Add your first repository” as though saved data were gone.
Initial loading runs once through the search task. Read-only catalog requests retry
one transient lost/failed connection or timeout after 250 ms; mutations are never
retried automatically. Cancellation and generation checks prevent stale loads from
replacing newer results. Repository removal stays disabled if installed-source
loading failed, since the screen cannot verify the removal dependency.

`ExtensionModelTests` inject partial failures, recovery, and temporary/persistent
connection loss. Opt-in `ExtensionDeviceTests` and `ExtensionDeviceUITests` use
`MOKU_LIVE_EXTENSION_CHECK=1` in their test-run environment to verify the real
saved repositories, concurrent loading, catalog search, and visible iPhone UI.


## Recent — 2026-09-20

More → Recent uses Library’s IconRail, theme surfaces, Phosphor icons, and
navigation insets. History and Updates have independent search and share the
content-mode filter. History collapses sessions by title, groups by latest day,
expands chapter visits, displays stats/positions/time, resumes chapters, and
supports confirmed per-title or all-history clearing. HomeStore persists the
active profile’s history; reader/player activity now records real sessions and
excludes background/paused time. Clearing history leaves library membership,
pins, reader bookmarks, and downloaded files intact.

Updates reads chapters for ProfileLibrary’s saved titles, groups by source upload
date, bundles three or more chapters per title/day, and displays read/download
state. The latest 100 matching chapters are shown. Undated chapters are labeled
explicitly. Refresh synchronizes only this profile’s saved titles, reports
progress/new chapter counts/failed titles, and stores the last successful refresh
time in profile preferences. It intentionally does not invoke Tsunagu’s global
library updater: iOS membership is local, so the desktop global inLibrary query
would omit titles or mix profiles. Catalog chapter progress and download files
remain shared by the embedded backend. Download actions use enqueueDownload,
startDownloader, and deleteDownload. Downloads’ separate queue UI still needs
its existing service integration; see PAGE-LEDGER.md.

Recent uses the existing title-detail/reader/player routes. Unavailable chapters
fall back to details with an explanation; novels remain blocked on the missing
novel reader. This change does not add novel playback. Unit tests exercise
grouping/filtering, durable deletion, scoped refresh/failures, download commands,
and activity accounting. RecentUITests uses explicit debug fixtures for visual
and navigation checks; those fixtures do not verify live-source compatibility.


### UI responsiveness and local catalog startup

`Backend` now starts the authenticated Go/SQLite core independently of
Java. Repository lists, the extension catalog, installed sources, and search
filter choices request that local connection without booting the JVM. Source
execution starts Java once on demand and attaches it to the existing core;
neither its HTTP endpoint nor its database is restarted. A JVM failure is retained
for source calls but does not prevent subsequent local SQLite reads. There is no
second catalog database or cache that can disagree with the persisted records.

The pending sandbox rejects source operations until attached. Download workers
start after attachment, and scheduled source refresh skips the pending runtime.
`BackendAPI` lazily creates sessions/caches on its own actor rather than in its
caller’s screen initializer. Native Go and JVM work runs on dedicated utility
queues with main-queue assertions; JSON/disk/image decoding stays in service
actors. Reader Core Image context creation is lazy for the same reason.

Extensions publishes repository, installed-source, and catalog responses
independently. Filter tasks cancel obsolete requests; initial loading has no
search debounce. Keyboard autofocus runs after the first search-page render,
rather than during `onAppear` layout. Settings uses a lazy row stack to avoid
constructing offscreen rows on first entry. UI state remains on MainActor.

Validation: Swift startup tests exercise real Go/SQLite before runtime attachment,
including failed attachment and resume. Gated model tests verify saved lists are
visible while catalog loading is suspended and stale results cannot replace new
filters. Go race tests cover deferred attachment, readiness and persistence.
Simulator sampling found cold UIKit keyboard initialization during Search and
no service call blocking the main thread during Settings; device navigation
latency still requires on-device profiling if a multi-second delay persists.

Debug builds also sample background-to-main responsiveness while the scene is
active. Delays over 250 ms produce `com.moku.app / UIResponsiveness` console
warnings, independently of how long a source fetch takes. Sampling stops when
the app leaves the foreground and is absent from Release builds.

Manual simulator verification on the existing database showed both saved
repositories, the 1,651-entry catalog and the installed MangaDex source. Sampling
captured JVM initialization on `moku.jvm.startup`; no >250 ms main-actor warning
was recorded during that navigation/source-settings check. Targeted simulator
Search, Settings navigation and embedded playback tests passed, as did 15 Swift
unit tests and the Go race checks. The physical iPhone build/install succeeded;
its UI test runner timed out enabling automation before tests began, so physical
navigation timings remain unverified. The updated normal build is installed.

Broader pre-existing test issues remain: the old account-navigation test expects
`downloads.history`, which no longer identifies the current view selector, and
`TestLifecycleAndPersistence` hard-codes migration count 18 although the current
schema has 19. The targeted startup tests cover persistence and deferred runtime
readiness without that outdated migration assertion.

### Library-aligned Extensions — 2026-09-21

Extensions now uses Library's IconRail and RadialMenu, underlined media tabs, and a flat native List (retained for system swipe actions). Installed/Browse/Repositories share the view picker. The radial menu opens Search, Filter, Repositories, and Add. Source rows have one native three-dot menu for Configure, Search source, Update, or Install. Swipe left to uninstall; repository rows expose refresh/edit-name in their menu and swipe-left removal once their sources are uninstalled. Confirmations and existing backend operations are preserved. Source logos use square, Dynamic Type-scaled 64-point frames with CoverImage's opt-in bareIcon rendering; covers elsewhere keep their existing appearance. Final visual/interaction review is user-owned.
