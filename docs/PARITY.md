# Desktop → iOS parity ledger

The source of truth is the desktop app at `../Moku` (v0.14.1, SvelteKit + Tauri) and this repo's
`Moku/` folder. Both were inventoried from code on 2026-10-28. Each row is one user-facing desktop
feature with its iOS status.

**Status:**
- ✅ at parity
- 🟡 partial or broken on iOS
- ❌ missing on iOS
- ➖ desktop-only, with no iOS equivalent needed (the iOS replacement is noted instead)
- ✨ iOS-only extra

**Priority:**
- **P0**: broken or misleading today; fix before external testers.
- **P1**: core parity.
- **P2**: polish or power-user parity.

The **Plan / where** column names the iOS file or approach. Rows flip to ✅ in the same commit as
their fix.

## Where it stands (2026-10-28)

Every P0 row is at parity. Every P1 row is either at parity or partial, and
the partial ones are listed below. What remains is P2 polish, plus three items that need
work outside the iOS app.

**Remaining, by size:**
- **Needs a Tsunagu change:**
  - In-app Cloudflare verification: the API doesn't expose a source's base URL.
  - Pushing progress to trackers automatically after marking chapters read.
  - Alternate titles: the schema has none.
- **Needs the desktop app built and run:** the Phone sync toggle and Bonjour advertising
  (`Moku` branch `testflight-ready`). Their std-only Rust parts were compiled and run on
  their own; `cargo check` of the whole app needs rustc ≥ 1.90 (this Mac has 1.88).
- **P2 polish:**
  - library: infinite scroll, latest-fetched sort;
  - details and novels: resume page in chapter rows, cover picker,
    a separate novel bookmark, justified text, reading guide;
  - reader: PDF chapters, resume banner, next-chapter prefetch;
  - search: per-source browse page, per-extension library and bulk migration;
  - folders: content types per folder;
  - settings: storage-limit dialog, server log viewer;
  - player: ASS styling; MyAnimeList (also missing on desktop);
  - QR pairing; localisation.

**How it was verified:**
- **Unit tests:** 126, all passing except the keychain-only app-lock test in unsigned
  simulator builds.
- **Simulator, real MangaDex:** genre search, Details controls, mark read/unread,
  onboarding, the Sync screen, the fixture player (subtitles, AirPlay, autoplay next).
- **Desktop sync:** end to end against a Tsunagu server on this Mac (pairing, adds,
  progress both ways, folders, removal, content-filtered titles).
- **Not run:** a real novel source, real anime sources, PiP on a device, background
  tasks (BGTaskScheduler doesn't fire on its own in the simulator), Bonjour discovery
  between two machines.

## 0. Desktop sync (new on both sides)

The desktop keeps library, folders, read progress, automation, content rules and trackers on its
Tsunagu server. Tsunagu binds to `127.0.0.1:6007` and checks a password with Bearer sessions
(`POST /api/auth/login`). The phone runs its own embedded Tsunagu. "Sync" means a two-way merge
between the two servers, so the phone keeps working offline.

| Feature | Desktop | iOS | Pri | Plan / where |
| --- | --- | --- | --- | --- |
| Let other devices reach the desktop server (LAN bind + required password) | ✅ | – | P1 | Desktop: Settings › General › Server › "Allow devices on your network" restarts Tsunagu on `0.0.0.0:6007`, requires a server password, and shows the LAN URL and a pairing QR code |
| Pair a phone with a desktop (URL + password → session token) | – | ✅ | P1 | iOS: Settings › Sync › Connect to desktop (scan QR or type URL), `POST /api/auth/login`, token kept in the Keychain |
| Two-way library sync (saved titles, matched by extension package + external ID) | – | ✅ | P1 | `Shared/Sync/DesktopSync.swift`: 3-way merge against the last-synced snapshot, so removals carry over |
| Two-way read progress (chapter `externalId`, newest `updatedAt` wins) | – | ✅ | P1 | Same engine, via `readingProgress` / `updateReadingProgress` |
| Folders and folder membership (matched by name) | – | ✅ | P1 | Same engine |
| Sync triggers: on app open, on return to foreground, manual "Sync now", status and last-sync time | – | ✅ | P1 | Settings › Sync |
| Missing extensions reported ("install X to sync N titles") | – | ✅ | P2 | Sync report |

## 1. App shell and chrome

| Feature | Desktop | iOS | Pri | Plan / where |
| --- | --- | --- | --- | --- |
| Main navigation (Home, Library, Browse, Downloads, Recent, Extensions) | ✅ | ✅ | – | Tab bar plus More |
| Global content-type filter All / Manga / Novels / Anime | ✅ | ✅ | – | Mode tabs |
| Toast notifications (success / error / info / download) | ✅ | ✅ | P1 | `Shared/Components/Toast.swift`; replace one-off `.alert` notices |
| Splash and boot progress, error log, retry | ✅ | 🟡 | P2 | Skeleton plus error and retry exist; no log |
| "What's new" changelog after an update | ✅ | ✅ | P2 | Bundled notes (`WhatsNew.releases`), shown once after an update |
| Onboarding welcome and tour | ✅ | ✅ | P0 | First-run flow: what Moku is, add a repository, install a source, Local files |
| Server log viewer | ✅ | ❌ | P2 | Settings › Dev Tools › Server log |
| Idle screen (animated covers) | ✅ | ✅ | – | |
| App lock PIN plus OS biometrics | ✅ | ✅ | P2 | Face ID prompts on lock; themed lock screen; PIN hashed off the main actor |
| Interface scale | ✅ | ✅ | – | |
| Pull to refresh | n/a | ✅ | P0 | Global bounce override removed; reader keeps bounce off itself |
| Title bar, tray, close dialog, single instance, window controls | ✅ | ➖ | – | |
| Discord Rich Presence | ✅ | ➖ | – | |
| In-app updater | ✅ | ➖ | – | TestFlight / App Store |

## 2. Home

| Feature | Desktop | iOS | Pri | Plan / where |
| --- | --- | --- | --- | --- |
| Hero stage: 4 slots, pin/unpin, resume, empty slot | ✅ | ✅ | – | |
| Hero genre chips → genre drill | ✅ | ✅ | P0 | Genre search now works (§4) |
| Up next (5 chapters, scanlator prefs) | ✅ | ✅ | – | |
| Activity feed and full history | ✅ | ✅ | – | |
| Heatmap and stats tiles, streak, by-type donut | ✅ | ✅ | – | Heatmap made lazy |

## 3. Library

| Feature | Desktop | iOS | Pri | Plan / where |
| --- | --- | --- | --- | --- |
| Saved / Downloaded / folder tabs | ✅ | ✅ | – | |
| Reading / Completed views reachable from the page | – | 🟡 | P2 | Only via Settings default view |
| Reorder and hide tabs, default folder | ✅ | 🟡 | P2 | Hide and reorder are in Settings › Folders |
| Sort: A–Z, unread, total, recently added, recently read | ✅ | ✅ | P0 | `addedAt` read from the server |
| Sort: latest fetched chapter, latest uploaded chapter | ✅ | 🟡 | P2 | Latest upload added; latest fetched not yet |
| Filters: unread, started, downloaded, bookmarked | ✅ | ✅ | – | |
| Status filter (ongoing, completed, …) | ✅ | ✅ | P0 | Server status mapped to filters |
| Show tracked only | ✅ | ✅ | P2 | Library filter → Tracked |
| Grid / list layouts | ✅ | ✅ | – | iOS has 5 layouts |
| Update entire library, with progress and result | ✅ | ✅ | P1 | Library tools → Update and Recent → Updates use the server update |
| Multi-select and bulk actions (move to folder, remove from folder, remove from library) | ✅ | ✅ | P1 | Long-press → Select; selection bar |
| Card menu: folders, add/remove library, refresh, delete downloads | ✅ | ✅ | P1 | |
| Infinite scroll | ✅ | 🟡 | P2 | Paged with Previous/Next |
| Empty and error states | ✅ | ✅ | – | |

## 4. Browse / Search

| Feature | Desktop | iOS | Pri | Plan / where |
| --- | --- | --- | --- | --- |
| Keyword search across sources, grouped by source | ✅ | ✅ | – | |
| Language filter, preferred language | ✅ | 🟡 | P1 | Preferred language is applied when Search opens |
| Popular when the query is empty | ✅ | ✅ | – | iOS adds recommended, latest and explore shelves ✨ |
| Load more / infinite results | ✅ | ✅ | P1 | Load more button |
| Tags tab: genres + status, AND/OR, using source filter options | ✅ | ✅ | P0 | Port of `buildGenreFilterInputs`, plus status selects |
| Genre drill page (library + sources) | ✅ | 🟡 | P0 | Genre chips run a source genre search; library matches not merged |
| Sources tab: per-source browse (popular, in-source search, load more) | ✅ | 🟡 | P1 | "Search by source" exists; add a source page with pagination |
| Pin sources | ✅ | ✅ | P2 | Long-press a source in filters |
| Local Source entry | ✅ | 🟡 | P2 | Import exists in Settings › Storage |
| NSFW / content-level hiding | ✅ | ✅ | – | Server-side |
| Quick preview modal | ✅ | ➖ | – | iOS opens Details directly; long-press preview ✨ later |

## 5. Series details

| Feature | Desktop | iOS | Pri | Plan / where |
| --- | --- | --- | --- | --- |
| Header, status, source, genres, description, add to library | ✅ | ✅ | – | |
| Alternate titles | ✅ | ❌ | P2 | Needs Tsunagu: the schema has no alternate titles |
| Primary button: Start / Continue · Ch X / Read again | ✅ | ✅ | P1 | |
| Chapter sort: source order, number, upload date, asc/desc | ✅ | ✅ | P1 | |
| Jump to chapter / filter | ✅ | ✅ | – | |
| Scanlator prefer / enforce / block | ✅ | ✅ | – | |
| Mark read / unread, mark above/below | ✅ | ✅ | P0 | Chapter menu: mark read/unread, mark previous read/unread |
| Multi-select chapters → download / delete / mark read / unread | ✅ | ✅ | P1 | |
| Download menu: next 5/10/25, unread, all, custom range, delete all | ✅ | ✅ | P1 | No custom range; use selection instead |
| Chapter row: resume page, read and downloaded icons | ✅ | 🟡 | P2 | Read, downloaded and upload date; no resume page |
| Switch source (migrate) | ✅ | ✅ | P1 | Details → Manage |
| Series link | ✅ | 🟡 | P2 | Auto-link exists; manual link UI missing |
| Cover picker / refetch cover | ✅ | 🟡 | P2 | Refresh cover; no picker |
| Metadata match (AniList) | ✅ | ❌ | P2 | `searchMetadata`, `applyMetadataMatch` |
| Per-series automation panel | ✅ | ✅ | P1 | Details → Manage → Automation |
| Per-series tracking panel (status, progress, score, sync) | ✅ | ✅ | P1 | Details → Manage → Tracking |
| Tracker push after marking read | ✅ | 🟡 | P1 | Manual “Sync from tracker” only |
| Open source page | ✅ | 🟡 | P2 | MangaDex only; generalise |
| Novel chapters open a reader | ✅ | ✅ | P0 | §7 |

## 6. Manga reader

| Feature | Desktop | iOS | Pri | Plan / where |
| --- | --- | --- | --- | --- |
| Single / double / auto / strip, transitions, RTL, fit, zoom | ✅ | ✅ | – | |
| Pinch zoom, swipe and tap zones, auto scroll | ✅ | ✅ | – | |
| Page gap, contrast, offset spreads | ✅ | ✅ | – | |
| Per-manga settings, presets | ✅ | ✅ | – | |
| Bar position, tap to toggle, containerised | ✅ | ✅ | – | Settings import accepts left/right (fixed) |
| Bookmarks, auto-bookmark, resume banner | ✅ | 🟡 | P2 | No resume banner |
| Preload pages, next-chapter prefetch | ✅ | 🟡 | P2 | No next-chapter prefetch |
| PDF chapters | ✅ | ❌ | P2 | PDFKit |
| Webtoon image quality | ✅ | ✅ | P0 | Decode bounds the short side and pixel count |
| Keyboard shortcuts | ✅ | ✅ | – | Hardware keyboard |

## 7. Novel reader

| Feature | Desktop | iOS | Pri | Plan / where |
| --- | --- | --- | --- | --- |
| Novel reader (HTML / text), continuous scroll | ✅ | ✅ | P0 | `Features/NovelReader`; not yet run against a real LNReader source |
| Paged mode | ✅ | ✅ | P1 | Tap edges to turn a screen |
| Font, size, line height, paragraph gap, width, alignment | ✅ | 🟡 | P1 | All but justified alignment |
| Paper / sepia / dark themes | ✅ | ✅ | P1 | Plus black |
| Progress save and resume, bookmark | ✅ | 🟡 | P0 | Synced progress and resume; no separate bookmark |
| Reading guide, auto scroll | ✅ | ❌ | P2 | |

## 8. Anime player

| Feature | Desktop | iOS | Pri | Plan / where |
| --- | --- | --- | --- | --- |
| HLS / direct playback, source fallback, resume | ✅ | ✅ | – | |
| Transport, ±10 s, prev/next, speed | ✅ | ✅ | – | |
| Double-tap left/right to seek | ✅ | ✅ | P1 | |
| Skip intro / outro / recap (server skip timestamps) | ✅ | ✅ | P1 | |
| Preferred source per series | ✅ | ✅ | P2 | Remembered by source label |
| ASS subtitles | ✅ | 🟡 | P2 | ASS → plain-cue fallback |
| Subtitle style persisted | ✅ | ✅ | P1 | Style and picked language remembered |
| Volume control | ✅ | ➖ | – | Hardware buttons |
| Stream info | ✅ | ✅ | P2 | Player options: resolution and source |
| Upscaler | ✅ | ➖ | – | |
| Background audio, Picture in Picture, AirPlay, lock-screen controls | n/a | ✅ | P1 | ✨ PiP needs a device check (not possible in the simulator) |

## 9. Downloads

| Feature | Desktop | iOS | Pri | Plan / where |
| --- | --- | --- | --- | --- |
| Queue and history, grouped by series | ✅ | ✅ | – | |
| Pause/resume, clear, retry all, auto-retry | ✅ | ✅ | – | |
| Remove single item / series | ✅ | ✅ | P1 | Long-press a chapter or series |
| Reorder (move up/down/top/bottom) | ✅ | 🟡 | P2 | Series to top/bottom |
| Series covers in groups | ✅ | ✅ | P2 | |
| Storage warning dialog | ✅ | 🟡 | P2 | Inline text only |
| Download toasts | ✅ | ✅ | P1 | |
| Continue downloading in background | n/a | ✅ | P1 | ✨ Background task plus BGProcessingTask |

## 10. Recent

| Feature | Desktop | iOS | Pri | Plan / where |
| --- | --- | --- | --- | --- |
| History by day, resume, clear per series / all | ✅ | ✅ | – | |
| History stats strip | ✅ | ✅ | – | Statistics popup |
| Updates tab with real new chapters | ✅ | ✅ | P1 | Server `chapterUpdates` |
| Run library update | ✅ | ✅ | P1 | |

## 11. Extensions

| Feature | Desktop | iOS | Pri | Plan / where |
| --- | --- | --- | --- | --- |
| Installed / available / search / language | ✅ | ✅ | – | |
| Updates tab, Update all | ✅ | ✅ | P1 | Tools → Update all (N) |
| Install from URL | ✅ | ✅ | P2 | |
| Repositories add / remove / refresh / rename | ✅ | ✅ | – | |
| Source settings | ✅ | ✅ | – | |
| Per-extension library, bulk source migration | ✅ | ❌ | P2 | |
| Local Source library management | ✅ | 🟡 | P2 | Import only |
| Cloudflare challenge (managed solver) | ✅ | 🟡 | P1 | Clear "behind Cloudflare" error and external solver setting. The in-app browser (`SourceVerificationBrowser`) needs Tsunagu to expose a source's base URL first |

## 12. Tracking

| Feature | Desktop | iOS | Pri | Plan / where |
| --- | --- | --- | --- | --- |
| Tracker list, OAuth connect, disconnect | ✅ | ✅ | – | |
| MyAnimeList | 🟡 | 🟡 | – | "Coming soon" on both |
| Import from AniList (setup, match, dry run, resume) | ✅ | ✅ | – | |
| Per-title tracking | ✅ | ✅ | P1 | §5 |

## 13. Settings

| Feature | Desktop | iOS | Pri | Plan / where |
| --- | --- | --- | --- | --- |
| General: scale, server URL, auto-start, idle, animations, language | ✅ | ✅ | – | |
| General: default start view | ✅ | ✅ | P2 | |
| Appearance: themes, system sync, custom themes | ✅ | ✅ | – | Light-theme dark spots fixed |
| Theme editor export / import JSON | ✅ | ✅ | P2 | Copy as JSON / Paste, in desktop's `{id, name, tokens}` format |
| Reader, Player, Library, Automation, Keybinds | ✅ | ✅ | – | |
| Automation: update library on app open | ✅ | ✅ | P1 | Plus background updates with notifications ✨ |
| Performance: items per page, cache stats, clear cache | ✅ | ✅ | – | |
| Storage: usage, format, directories, backups, Mihon import/export | ✅ | ✅ | – | |
| Storage limit warning | ✅ | 🟡 | P2 | |
| Reset: reading stats, settings | ✅ | ✅ | P2 | Stats come from history: Library → Clear reading history; Storage → Reset preferences |
| Folders (content types per folder) | ✅ | 🟡 | P2 | Content types missing |
| Content level, rules, source overrides | ✅ | ✅ | – | |
| Server settings | ✅ | ✅ | – | |
| Auth: server password, app lock | ✅ | ✅ | – | |
| About: versions, release notes, links | ✅ | ✅ | – | |
| Bug reporter (prefilled GitHub issue, redacted settings) | ✅ | 🟡 | P2 | Prefilled issue with app/iOS/device; no settings attached |
| Dev tools | ✅ | ✅ | – | |

## 14. Production readiness (iOS)

| Item | Status | Pri | Notes |
| --- | --- | --- | --- |
| Release archive, privacy manifest, export compliance | ✅ | – | `docs/TESTFLIGHT.md` |
| Onboarding for an app that ships with no sources | ✅ | P0 | §1 |
| Background playback / PiP / downloads | ✅ | P1 | §8, §9 |
| Light theme correctness | ✅ | P1 | Fixed in menus, toggles, tabs and sheets; reader and player stay dark by design |
| Performance (see "Performance fixes" below) | ✅ | P0 | |
| Localisation | 🟡 | P2 | English only (matches desktop) |

## Performance fixes

Each row is a measured-in-code cause of lag, and its status.

| Smell | Status |
| --- | --- |
| Activity history rewritten on every page turn and every second of playback, re-rendering Home, Library, Recent and Search | ✅ recorder throttled to 5 s, plus chapter / completion / pause changes |
| Every mutation (including progress saves) wiped the whole query cache, memory and disk | ✅ progress-sensitive reads cached separately; progress saves invalidate only those |
| Starring a title sent flag and order mutations for every folder | ✅ only changed folders |
| Reader ran `loadWindow` on every scrolled frame | ✅ only when the visible page range changes |
| Page decodes serialised on one actor | ✅ stateless concurrent decoder |
| Player re-renders the whole view 4×/s | 🟡 captions now stored; position ticks remain |
| Heatmap: 364 buttons with popovers, not lazy | ✅ lazy columns, one readout |
| JSON decoded in `body` (custom theme, mode tabs, keybinds) | 🟡 custom themes decode only when one is selected; mode tabs and keybinds remain |
| Theme colours parsed from hex on every access | ✅ cached per palette |
| App lock PBKDF2 on the main actor | ✅ unlock hashes off the main actor |
| Settings › Storage walks the whole data folder, result unused | ✅ removed |
