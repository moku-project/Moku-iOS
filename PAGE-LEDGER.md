# iOS page completion ledger

Updated: 2026-09-20. This tracks implementation, not release certification.
Source of truth: native routes and views; older README and feature inventory statements can lag the code.

| Page / flow | Status | Remaining work |
| --- | --- | --- |
| Recent | Implemented; user review pending | History and Updates using Library styling. Final visual/interaction check belongs to the user. See notes below. |
| Tracking | Service connections and import implemented | Live-account OAuth/import verification and per-title tracker editing remain. |
| More → About | Placeholder | Replace placeholder or reuse Settings → About. |
| Novel reader | Missing | Native novel reading experience. |
| Settings → Player | Availability note | Connect playback/subtitle preferences; player itself exists. |
| Settings → Automation | Availability note | Automatic downloads and cleanup controls. |
| Settings → Content | Availability note | Content filters and source overrides. |
| Settings → Performance | Reserved | Define useful mobile controls. |
| Settings → Keybinds | Availability note | Decide mobile/external-keyboard scope. |
| Settings → Folders | Availability note | Decide mobile storage scope; Library folders already exist. |
| Settings → Server / Auth | Availability notes | Decide scope: runtime is embedded and profiles are local. |
| Settings → Dev Tools | Availability note | Define mobile diagnostics scope. |
| Title details | Partial | Advanced desktop chapter management and migration. |
| Downloads | UI implemented, service integration incomplete | Queue/history currently use presentation state; connect live transfer service. |
| Home, Library, Search, Extensions (including sources), Profile | Implemented | Individual feature gaps and end-to-end verification remain; not blanket completion claims. |
| Manga reader | Implemented | Continue source/device verification. |
| Video player | Implemented with limits | DASH and ASS/SSA support absent; physical-device verification remains. |

## Recent acceptance checklist

- [x] Library typography, surfaces, view dropdown, mode selection, and empty-state styling.
- [x] History / Updates views with independent title/chapter search.
- [x] History statistics: streak, chapters/episodes, time, titles.
- [x] Collapse sessions by title, expand chapters, group by latest activity day.
- [x] Chapter position, duration, repeat count, and direct resume.
- [x] Confirm clearing all history or one title; persist within active profile.
- [x] Updates grouped by date; expandable bundles of three or more chapters.
- [x] Refresh active profile's library, progress, completion count, failed-title feedback.
- [x] Last update time, unread count, read/download indicators.
- [x] Open title/chapter; queue and delete real downloads with error feedback.
- [x] Loading, empty, no-results, failure, and retry states.
- [x] Reader/player feed actual activity into profile history.
- [x] Model tests and simulator compilation.
- [ ] User final visual/navigation check (requested by user; no further automated UI review).

Desktop references: `Moku/src/lib/components/recent/Recent.svelte`, `HistoryTab.svelte`, `UpdatesTab.svelte`, and their grouping helpers.

## Architecture notes

iOS library membership belongs to ProfileLibrary, not Tsunagu's global inLibrary flag. Recent must refresh/query saved titles for the active profile rather than mutate global membership to invoke desktop's global updater. History is local to HomeStore. Source catalog and download files remain device-shared, as in the existing iOS architecture.


## Recent implementation notes

- Implemented in `Moku/Features/Recent`; More routes to RecentView.
- History uses profile-local HomeStore, with actual reader/player activity recording.
- Refresh uses saved profile titles and syncChapters rather than changing backend-global membership. It shows the latest 100 matching chapters grouped by source upload date, including an explicit undated group. This is the mobile adaptation of desktop's global chapterUpdates feed, not its global updater job.
- Real download enqueue/start/delete calls are wired; the separate Downloads queue screen still has its existing integration gap.
- Novel rows open title details with an availability message; the novel reader remains a separate unfinished page.
- Verification before user requested implementation-only work: unit suite passed (59 passed, 2 skipped), including 5 new Recent tests. Simulator UI checks exposed identifier propagation and confirmation-presentation issues; code was adjusted. The final UI pass is intentionally pending user review, and live-source download/resume behavior has not been certified by these fixture tests.
- Working agreement: focus on implementation; leave final visual and interaction checks to the user after implementation is finished.

## Extensions redesign — 2026-09-21

Implemented from the approved Library-aligned mockups, with the user's refinements:

- Installed, Browse, and Repositories use Library's existing ViewIconRail pill and LibraryRadialMenu components.
- Library-style underlined media tabs, flat rows, and dark theme; no inset grouped-list containers.
- One trailing three-dot custom boxed dropdown per row. Configure, search, update, and install live in that menu; repositories offer refresh/edit name.
- Native swipe-left actions uninstall sources or remove repositories, retaining confirmation and the installed-source removal guard.
- Source logos use a square 64-point frame scaled for Dynamic Type, with no added background, corner mask, or internal padding. Original source artwork is preserved.
- Search and repository/language filters live in the tools sheet; repository addition and source configuration retain their backend operations.
- Simulator build passes. Existing UI test selectors updated for new entry points; final visual/interaction review remains with the user.

## Content-shaped loading — 2026-09-21

Replaced visible loading/searching placeholders and indeterminate content spinners with shared animated skeletons across startup, Library, Home, Recent, Extensions/repositories/configuration, search/results/source filters, title metadata/chapters, cover images, storage values, manga chapters/pages, and video loading. Existing playback remains visible during buffering with a subtle track placeholder. Determinate progress bars remain. Reduced Motion and the app animation preference produce static placeholders. User final visual check pending.

## Search pill and recent queries — 2026-09-21

- Search now shares the navbar's height, rounding, interior padding, and surface style, with tighter close-to-input spacing.
- Completed queries persist in a profile-local SQLite database, deduplicated case-insensitively and capped at 30 most recent entries.
- Idle search offers recent-query replay, individual removal, and Clear All. Loading uses skeletons; first use explains where recent queries will appear.
- Final visual review remains with the user.

## Recent and Tracking refresh — 2026-09-21

- Recent follows Extensions’ media tabs, flat cover rows, single secondary line, row overflow menus, and LibraryRadialMenu. History tools are Search, Filter, Clear history; Updates tools are Search, Filter, Refresh. Statistics remain reachable from a history row menu.
- Search/filter and destructive confirmation use dimmed/blurred popups. Filter changes apply together; Cancel leaves the active filters intact. Update chapters expand on demand with resume/download controls.
- More → Tracking and Settings → Tracking share TrackingView. Bundled official AniList/MyAnimeList artwork retains brand colors. Connection status is read from the embedded backend; no connected state is invented in production.
- AniList authorization supports opening/copying the auth link, polling with cancellation, and securely entering a token/redirect URL. Disconnect requires confirmation. Accounts remain backend/device-scoped, while imported library membership and resumable import drafts belong to the active local profile.
- Import supports Manga/Anime, list statuses, source/language selection or source-less imports, conservative automatic matching, manual match selection, skipping, duplicate protection, stop/resume, dry run, failed-item retry, and failure export. Import progress is persisted without account tokens and cannot resume under another username.
- Matched imports do not change backend-global library membership. ProfileLibrary saves the imported title locally; the backend stores tracker links and source-less catalog records.
- Live OAuth/account mutations have not been exercised against a real account. MyAnimeList remains Coming soon. This implementation does not add a per-title tracker editing panel or a native novel reader.

Validation for this change: 8 focused model tests (5 Recent, 3 Tracking) and 3 simulator UI tests passed across the targeted runs; changed Swift files pass strict swift-format lint. Screenshots are in `design/recent-tracking-review/implemented`.

## Shared row overflow menus — 2026-09-21

Extensions, repository rows, Recent History/Updates, Tracking accounts, and import-review rows now use `OverflowMenu`. The shared page-root overlay avoids list clipping and system capsule-menu styling. Panels size to their labels with 10-point horizontal row padding, a 4-point outer inset, 16-point corners, 44-point row targets, and a faint border. Menus flip above the trigger near the bottom, constrain to the viewport, scroll when necessary, and dismiss on selection, outside tap, accessibility escape, or anchor movement. Destructive/disabled actions retain their behavior. Simulator compilation and strict formatting of the new component were checked; visual review remains with the user.

## First-load skeleton cycle and sandbox cache — 2026-09-21

- Main content surfaces retain the first skeleton pulse for a complete 2.2-second cycle per profile/session. Repeat visits avoid the forced delay; Reduce Motion skips it.
- Temporary backend results now have bounded, expiring disk storage under Library/Caches alongside covers.
- Settings' Clear cache action clears results, covers, and first-visit presentation state while retaining user data.
- Build/unit verification is automated; final visual review remains with the user.

## Floating navbar selection — 2026-09-21

Navigation icons are 27 points expanded and 24 points compact. A single wide sage-tinted capsule (tab-slot width plus 8 points, 44 points tall expanded / 38 compact, with a 4-point shell inset) sits behind the active icon and slides between equal-width tab slots with a damped spring. The indicator follows compact sizing; Reduce Motion and disabled animations use immediate updates. Selection no longer scales individual icons.

Navbar icons stay white in every selection state. Active Search and Downloads use bold Phosphor outlines; the other active tabs use filled variants. Inactive tabs retain light outlines. The sliding sage container remains.

Navbar shell height is now 52 points expanded and 46 compact. The selected container follows the shorter shell while retaining its 4-point inset; icon hit targets remain at least 44 points.

## Dedicated global Search page — 2026-09-21

Global Search is a retained navbar destination with its own selected tab, top search field, results, and a dimmed/blurred filter popup with pinned Reset/Cancel/Apply controls. The navbar hides while the keyboard is visible and returns after submission/dismissal. Switching tabs retains the global model and mounted scroll view. Extension title-search and the Library “Browse sources” handoff open this page; Library-local search remains scoped to Library. Existing UI test selectors were adapted to tab navigation; final visual review remains with the user.
