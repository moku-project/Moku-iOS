# Home mobile design review

Generated concept mockups for review, not captures of implemented iOS screens. Sample reading history and covers come from the desktop reference; they are not live account data. Created with the built-in image-generation tool. The full generation specification is in `prompt.txt`.

- `home-mobile-concepts-v1.png`: initial Home, lower scroll position, and first-visit state.
- Desktop references: `Moku/docs/screenshots/Moku-Home.png` and the current `Home.svelte`, `HeroStage.svelte`, `ActivityFeed.svelte`, `ActivityHeatmap.svelte`, and `StatsGrid.svelte` components.
- Keep the four resume/pinned slots and existing five-icon floating navbar; Library retains its mode badge and long-press picker.
- Stack resume, upcoming chapters, recent activity, activity, and stats in one mobile scroll. Use a compact recent-weeks heatmap instead of compressing the desktop full-year heatmap.
- The mockup abbreviates the desktop stats to four prominent tiles. Preserve Series started and Reading since below these when implementing the full screen. Make earlier activity available through a range selection or horizontal scrolling.
- Implementation must accommodate Dynamic Type, reduced motion, safe areas, and real loading/empty/error states. Generated text and chart geometry are visual proposals rather than pixel-exact specifications.

No app navigation or Home implementation was changed for this review.
