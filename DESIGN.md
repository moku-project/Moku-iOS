# Moku design reference

Captured 2026-09-19 from Moku commit `ee54dbb6d37be4c574933a569134f3a7bb53778b` (v0.13.0). This is the desktop design baseline for Moku-iOS, not a claim that the iOS interface has been implemented. Keep this document versionable; local dotfiles and agent instructions are excluded separately.

## Mobile reference and reuse

User direction, 2026-09-20: use the current implemented Library as the mobile reference for future screens. Preserve desktop styling while reusing the Library radial menu, container pills, padding, and Phosphor icon choices. Search should reuse the floating search component used by Browse sources, including its keyboard-aware placement, rather than introduce another search layout. Keep visible copy limited to necessary content and actions; do not add small descriptive labels, decorative metadata, or promotional filler.

For the Extensions redesign, fold source search and preferences into Extensions and remove the separate Sources page. Review mockups against `Features/Library/LibraryView.swift`, `Features/Library/LibraryRadialMenu.swift`, and `Features/Search/SpotlightSearchView.swift` before implementation.

## Visual identity

Moku is a restrained, cover-led media library. Near-black layered surfaces, fine borders, compact controls, muted metadata, and a sage-green accent define its default appearance. Cover artwork supplies most of the color. Sans-serif titles sit alongside monospaced labels, chapter numbers, timestamps, and statistics. Small corner radii and thin separators keep dense screens orderly. Reader/player controls can use frosted surfaces over content.

The home reference shows a slim icon rail and leaf mark, a large cover with resume information and an upcoming-chapter column, then recent activity, statistics, and an activity heatmap. The library uses portrait cover grids; series details combine a portrait cover, metadata, compact badges, actions, and chapter navigation. These are desktop compositions to adapt for iOS.

## Implemented app themes

| Name / ID | Character | Base | Accent | Primary text |
| --- | --- | --- | --- | --- |
| Original / `original` | Soft near-black, warm gray text, muted sage | `#0c0c0c` | `#6b8f6b` | `#f0efec` |
| Dark / `dark` | Deeper black, brighter text, stronger sage | `#080808` | `#7aaa7a` | `#ffffff` |
| Light / `light` | Warm stone and ivory surfaces with green accents | `#e2deda` | `#3f9142` | `#080806` |
| Midnight / `midnight` | Blue-black surfaces with periwinkle accents | `#080c18` | `#6a7ab8` | `#eeeef8` |
| Warm / `warm` | Brown-black and sepia surfaces with amber accents | `#100e08` | `#c0902a` | `#f5f0e0` |

**Default behavior:** `DEFAULT_SETTINGS.theme` and the initial HTML body both select `dark`. “Original” is labeled “Default near-black” in the picker and supplies the root/custom-editor baseline, but it is not the initial selected theme. System matching is optional; when enabled, its fallback pair is Dark and Light, with either selection configurable to a built-in or saved custom theme.

**Source discrepancies:** `light-contrast` exists only in the `BuiltinTheme` type; there is no corresponding CSS palette or picker option. Do not count it as a sixth implemented theme. The Light picker thumbnail uses different colors from the actual CSS. The tables below preserve the CSS values, not thumbnail approximations.

## Exact app color tokens

Values resolve each theme against `src/app.css` root defaults. Tokens omitted by a theme inherit those defaults, including semantic colors. All hex values are sRGB CSS colors. Keep semantic names when porting them to native color assets.

- `bg-void` is the deepest backdrop; `bg-base` the main background; `bg-surface`, `bg-raised`, and `bg-overlay` provide layered panels and controls; `bg-subtle` is an additional quiet fill.
- Borders range from dim separators through strong outlines, with a separate focus color.
- Text ranges from primary content through secondary, muted, faint, and disabled states.
- `accent` is the core action/progress color; dim and muted variants support borders and tinted fills; foreground and bright variants support emphasis.

### Backgrounds

| Token | Original | Dark | Light | Midnight | Warm |
| --- | --- | --- | --- | --- | --- |
| `bg-void` | `#080808` | `#000000` | `#d8d4ce` | `#050810` | `#0c0a06` |
| `bg-base` | `#0c0c0c` | `#080808` | `#e2deda` | `#080c18` | `#100e08` |
| `bg-surface` | `#101010` | `#0d0d0d` | `#ece8e2` | `#0c1020` | `#16130c` |
| `bg-raised` | `#151515` | `#111111` | `#f5f2ec` | `#101428` | `#1c1810` |
| `bg-overlay` | `#1a1a1a` | `#171717` | `#ffffff` | `#151a30` | `#221e14` |
| `bg-subtle` | `#202020` | `#1e1e1e` | `#e4e0d8` | `#1a2038` | `#28241a` |

### Borders

| Token | Original | Dark | Light | Midnight | Warm |
| --- | --- | --- | --- | --- | --- |
| `border-dim` | `#1c1c1c` | `#252525` | `#c4c0b8` | `#1a2035` | `#201c10` |
| `border-base` | `#242424` | `#303030` | `#b0aca4` | `#222840` | `#2c2818` |
| `border-strong` | `#2e2e2e` | `#3e3e3e` | `#989490` | `#2c3450` | `#3a3420` |
| `border-focus` | `#4a5c4a` | `#5a7a5a` | `#3a5a3a` | `#4a5c8a` | `#6a5a30` |

### Text

| Token | Original | Dark | Light | Midnight | Warm |
| --- | --- | --- | --- | --- | --- |
| `text-primary` | `#f0efec` | `#ffffff` | `#080806` | `#eeeef8` | `#f5f0e0` |
| `text-secondary` | `#c8c6c0` | `#e8e6e0` | `#181612` | `#c0c4d8` | `#d8d0b0` |
| `text-muted` | `#8a8880` | `#b0aea8` | `#38342e` | `#808498` | `#988c60` |
| `text-faint` | `#4e4d4a` | `#6e6c68` | `#706c64` | `#404860` | `#584e30` |
| `text-disabled` | `#2a2a28` | `#303030` | `#b0aca4` | `#202840` | `#302a18` |

### Accent

| Token | Original | Dark | Light | Midnight | Warm |
| --- | --- | --- | --- | --- | --- |
| `accent` | `#6b8f6b` | `#7aaa7a` | `#3f9142` | `#6a7ab8` | `#c0902a` |
| `accent-dim` | `#2a3d2a` | `#2e4a2e` | `#a8d0a8` | `#252d50` | `#3a2c10` |
| `accent-muted` | `#1a251a` | `#1e2e1e` | `#cfe6cf` | `#181e38` | `#261e0c` |
| `accent-fg` | `#a8c4a8` | `#bcd8bc` | `#2f8a34` | `#a8b4e8` | `#e0b860` |
| `accent-bright` | `#8fb88f` | `#9fcf9f` | `#46a94b` | `#8896d0` | `#d0a040` |

### Semantic colors

| Token | Original | Dark | Light | Midnight | Warm |
| --- | --- | --- | --- | --- | --- |
| `color-error` | `#c47a7a` | `#c47a7a` | `#8a1a1a` | `#c47a7a` | `#c47a7a` |
| `color-error-bg` | `#1f1212` | `#1f1212` | `#f8e0e0` | `#1f1212` | `#1f1212` |
| `color-success` | `#7aab7a` | `#7aab7a` | `#7aab7a` | `#7aab7a` | `#7aab7a` |
| `color-info` | `#7a9ec4` | `#7a9ec4` | `#7a9ec4` | `#7a9ec4` | `#7a9ec4` |
| `color-info-bg` | `#121a1f` | `#121a1f` | `#121a1f` | `#121a1f` | `#121a1f` |
| `color-read` | `#2e2e2c` | `#2e2e2c` | `#e0dcd4` | `#2e2e2c` | `#2e2e2c` |

`dot-active` aliases `accent`; `dot-inactive` aliases `text-faint`. Light explicitly sets `color-scheme: light`; the root declares dark. Accent-filled buttons can use a white fallback (`accent-contrast` is not defined in these palettes); native foreground contrast needs its own validation.

## Frosted surfaces

Shared blur is `blur(20px) saturate(180%)`. Each theme supplies the following tint and border:

| Theme | Frost background | Frost border |
| --- | --- | --- |
| Original | `rgba(16, 16, 16, 0.72)` | `rgba(46, 46, 46, 0.55)` |
| Dark | `rgba(14, 14, 14, 0.72)` | `rgba(58, 58, 58, 0.55)` |
| Light | `rgba(246, 243, 237, 0.78)` | `rgba(150, 146, 138, 0.5)` |
| Midnight | `rgba(16, 20, 40, 0.72)` | `rgba(44, 52, 80, 0.55)` |
| Warm | `rgba(28, 24, 16, 0.72)` | `rgba(58, 52, 32, 0.55)` |

Exact shadow recipes:

```css
/* Original */
--frost-shadow: 0 1px 0 rgba(255, 255, 255, 0.05) inset, 0 8px 28px rgba(0, 0, 0, 0.55);
/* Dark */
--frost-shadow: 0 1px 0 rgba(255, 255, 255, 0.05) inset, 0 8px 28px rgba(0, 0, 0, 0.55);
/* Light */
--frost-shadow: 0 1px 0 rgba(255, 255, 255, 0.7) inset, 0 8px 28px rgba(70, 66, 58, 0.18);
/* Midnight */
--frost-shadow: 0 1px 0 rgba(255, 255, 255, 0.06) inset, 0 8px 28px rgba(0, 0, 6, 0.55);
/* Warm */
--frost-shadow: 0 1px 0 rgba(255, 240, 210, 0.05) inset, 0 8px 28px rgba(0, 0, 0, 0.55);
```

The solid reader/player option defaults to off. `body.frost-off` replaces frost background with `bg-surface`, border with `border-base`, and removes blur; that rule does not remove the shadow token. Custom themes do not expose frost tokens in the editor and inherit the root frost recipe (`rgba(15, 15, 15, 0.72)`, border `rgba(60, 60, 60, 0.55)`, shadow `0 1px 0 rgba(255, 255, 255, 0.05) inset, 0 8px 28px rgba(0, 0, 0, 0.5)`).

## Typography, geometry, and motion

| Property | Desktop source values |
| --- | --- |
| Body/title font | `"DM Sans", ui-sans-serif, system-ui, sans-serif` |
| UI/metadata font | `"DM Mono", "Fira Mono", ui-monospace, monospace` |
| Type scale, 2xs through 3xl | 10, 11, 12, 13, 14, 15, 17, 20, 24 px |
| Default body | 13 px, weight 400, line height 1.6 |
| Weights | 400 / 500 / 600 |
| Line heights | 1 / 1.3 / 1.45 / 1.6 |
| Tracking | -0.02 / 0 / 0.06 / 0.1 em |
| Spacing scale | 4, 8, 12, 16, 20, 24, 32, 40 px |
| Radius scale, sm through 2xl | 3, 5, 7, 10, 14 px; full = 9999 px |
| Desktop chrome tokens | Sidebar 62 px; titlebar 36 px |
| Library grid | Auto-fill columns, minimum 145 px; portrait covers 2:3 |
| Transition tokens | Fast 80 ms, base 140 ms, slow 220 ms; ease |
| Entry animations | Fade/scale 140 ms; vertical fade 180 ms with 5 px travel; scale from 0.97 |
| Loading | Skeleton shimmer 1.4 s; pulse 1.6 s; spinner 0.7 s |

These are declared font stacks, not proof that the named fonts are bundled or installed. Source components use Phosphor icons. Selected controls commonly combine `accent-muted` fill, `accent-dim` border, and `accent-fg` text. Secondary controls use raised backgrounds and subtle borders. Progress fills use the accent. Some hero/chart elements use fixed colors and translucent white rather than theme tokens; theme selection does not recolor every visual.

## Novel-reader palettes (independent of app theme)

| Reader ID | Page background | Text |
| --- | --- | --- |
| `paper` (default) | `#f5f2e9` | `#2b2622` |
| `sepia` | `#efe3c8` | `#4a3c28` |
| `dark` | `#14140f` | `#cbc6bd` |

The default novel layout uses a serif stack (`Georgia`, `Iowan Old Style`, `Times New Roman`, serif), font scale 1, line height 1.7, paragraph gap 1.1 em, maximum width 42 rem, and left alignment. Preferences also offer sans/mono and a system-font override. The current “sans” option references `--font-ui` (the monospaced UI stack); preserve this as a source observation rather than assuming a conventional sans font. Reader palette selection is separate from the five application themes.

## Custom themes

Saved themes have `{ id, name, tokens }`, with generated IDs prefixed `custom:`. The editor exposes 25 tokens: six backgrounds, four borders, five text colors, five accent colors, and five semantic colors (excluding `color-read`). New/reset themes use the Original color values. Users can edit, save/apply, delete, and import/export JSON. Import merges provided tokens over defaults. No named custom themes are shipped in `DEFAULT_SETTINGS` (`customThemes: []`); user-created runtime themes cannot be inventoried from this repository alone.

Custom selection injects token overrides on `:root` and removes the built-in `data-theme` attribute. It does not explicitly set a light color scheme. Frost, typography, spacing, and motion are outside the editor's declared token set.

## iOS adaptation baseline

Preserve the five palette identities, semantic token roles, cover-led hierarchy, restrained accent use, compact metadata styling, and separate reader palettes. Translate desktop dimensions into native layout decisions rather than copying pixel sizes literally. Support native text scaling, touch-sized controls, safe areas, system appearance, and reduced motion/transparency when implementing the app. These are proposed porting constraints; this document does not assert that they already exist in Moku-iOS.

## Source map and maintenance

All paths below are relative to the sibling Moku checkout at the recorded commit:

- `src/lib/styles/themes.css`: authoritative built-in theme overrides.
- `src/app.css`: inherited colors, typography, spacing, radii, frost, motion, and chrome tokens.
- `src/app.html`, `src/lib/types/settings.ts`, `src/routes/+layout.svelte`: initial theme, defaults, schema, and system matching.
- `src/lib/core/theme.ts`: theme application and system appearance listener.
- `src/lib/components/settings/sections/AppearanceSettings.svelte`, `src/lib/components/settings/ThemeEditor.svelte`: theme picker and custom theme behavior.
- `src/lib/components/home/HeroStage.svelte`, `src/lib/components/library/LibraryGrid.svelte`, `src/lib/components/series/SeriesHeader.svelte`: layout and control treatments.
- `src/lib/components/media/novel/NovelReader.svelte`, `src/lib/state/novelReader.svelte.ts`: independent reader colors and typography.
- `docs/screenshots/Moku-Home.png`: inspected visual reference for composition; screenshots are illustrative and may lag code. Additional references: `Moku-Library.png`, `Moku-Settings.png`, `Moku-Reader.png`, and `Moku-NovelReader.png` in that directory.
- `src/lib/assets/moku-icon.svg` and related Moku SVG assets: existing brand artwork.

When themes change, update the source commit/date, exact token tables, defaults, and discrepancies together. Keep actual source behavior distinct from future iOS decisions.

## Native icon and reader rule (2026-09-20)

Follow the desktop UI style and adapt its layout for touch. Use the desktop's
Phosphor icon names and weights, not SF Symbols substitutes or newly chosen
pictograms. Native SVG image assets are pinned to `phosphor-svelte` 3.1.0, the
same version as desktop, and rendered by `PhosphorIcon`. Its manifest records
names, weights and the source archive checksum; the MIT notice ships in Resources.
Regenerate assets with `python3 scripts/import-phosphor.py` after adding names.
No app-authored `systemImage:` / `systemName:` icon references remain. System-owned
controls (keyboard, alerts, document picker) retain their standard iOS presentation.

The manga reader opens its right-side panel with desktop `Sliders`, not a
hamburger. Its bottom navigation uses `ArrowLeft` / `ArrowRight` in light weight,
not video transport icons. Settings use the desktop layout/transition/fit tiles,
monospaced section labels, fine borders and sage selection. The drawer animates
from the trailing edge in 240 ms; reduced motion removes movement. Its dismissal
swipe begins at the drawer edge, so horizontal setting sliders do not dismiss it.
Thin sage sliders have 44-point touch targets and accessibility adjustment actions.

## Loading presentation — 2026-09-21

Content loading uses animated skeletons shaped like the content being fetched. Never show visible “Loading …” or “Searching …” placeholder copy or an indeterminate spinner in place of content. Reuse ContentSkeleton for row, result, chapter, settings, grid, dashboard, reader and video layouts; use SkeletonBlock for individual images or values. Keep loaded content visible during incremental requests where possible. Determinate download, reading and library-update progress remains meaningful and should stay visible.

Skeletons respect Reduce Motion, the profile animation preference, and inactive scene state. Expose one concise accessibility status per skeleton group rather than fake interactive content. ReaderCanvas uses page-sized native placeholders, animating only visible pending pages; failures always replace the skeleton with an actionable error. Final visual review belongs to the user.

## Pill staircase motion — 2026-09-21

ViewIconRail opens from the selected row downward, revealing one row every 70 ms while extending the capsule; closing reverses the sequence from the bottom upward. Each step eases over 160 ms. Rapid toggles reverse from the current visible step. Expanded labels sit 12 points outside the icon rail; the collapsed selected label uses a tighter visual icon-to-text gap. Trailing icon-only rails mirror the expanded spacing. Hidden/retracting choices are not interactive. Reduce Motion skips the sequence.


Pill motion refinement: labels now travel 36 points horizontally, increasing by 10 points per subsequent row (mirrored for trailing rails). Each step moves in 90 ms; stagger is 70 ms + 70 ms / row count. This keeps each menu's prior total duration (row count × 70 ms + 160 ms) while making the individual steps more distinct. Expanded and collapsed resting gaps are unchanged.

The selected/top label participates in the first staircase step as a single persistent text element. Its spacing animates from the compact gap to the expanded gap over 90 ms, keeping the text clear of the icon without overlapping crossfade copies. Icon-only top labels use 36-point travel when opening. At the final closing step, restore compact spacing and hide icon-only labels immediately, without a trailing text slide or fade. The lower rows retain their reverse staircase animation.

Pill dropdown triggers include a small downward chevron on the right, including icon-only triggers. Hide it immediately when opening and keep it hidden until the staircase closes; reserve its layout space so the icon rail stays aligned. Back navigation uses a standalone left chevron, including Search, Details, and radial submenus; retain descriptive accessibility labels and at least 44-point touch targets.

Search uses the navbar's 60-point height, 30-point continuous rounding, 8-point horizontal interior padding, and surface tint. The close control sits beside the input with only 2 points of additional spacing. Idle search shows profile-local recent queries with repeat, remove, and clear-all controls; history loading uses content skeletons.

## First-load skeletons and disposable cache — 2026-09-21

On the first visit to a content view in a profile's app session, keep its content-shaped skeleton visible for one full pulse (1.1 seconds dimming + 1.1 seconds returning), even when data is already ready. Load underneath it in parallel. Repeat visits skip this forced interval; ordinary loading placeholders still apply to uncached work. Reduced Motion and disabled animations skip the forced delay. Interrupted visits do not count as completed; foreground visits restart the cycle. Clearing cache resets completed visits. Video startup waits before playback, rather than playing audio behind a placeholder.

Temporary GraphQL results use the existing per-query expiry rules, an 8 MiB memory budget, and a 32 MiB sandbox disk budget under Library/Caches/Moku/Results-v1. Mutation invalidation clears both tiers. Covers retain their bounded cache. Settings → Storage → Clear cache removes temporary results and covers without deleting user records, downloads, or search history. iOS may purge Library/Caches whenever it needs space.
