# Downloads mobile concepts

Generated with the built-in image-generation tool for review, using sample data.
These are mockups, not screenshots of implemented Downloads functionality.

Reference: desktop Moku-Downloads.png, Downloads.svelte, DownloadQueue.svelte,
DownloadItem.svelte, DownloadHistory.svelte, and the approved Home mobile board.
The full generation prompt is saved in prompt.txt.

Keep Queue/History tabs with counts, expandable series groups, chapter progress,
page counts, ETA, retry affordances, and completed chapter size/date metadata.
Pause/Resume is the prominent queue action. The overflow menu holds selection,
reordering, retry-all, auto-retry, notifications, and contextual clear actions.
In selection mode, expose move-to-top/bottom, move up/down, retry, and remove in
an action sheet or compact toolbar above the navbar without hiding navigation.
Clearing history must remain distinct from deleting downloaded media.

Empty states use neutral gray surfaces and plain copy. No onboarding language.
The existing floating navbar and Library mode badge stay unchanged.

Files: downloads-mobile-concepts-v1.png and prompt.txt.

## Revision 2

`downloads-mobile-concepts-v2.png` supersedes v1. Generated using the current
native Library screenshot and component styles as the visual reference. Prompt:
`prompt-v2.txt`.

- Compact Library-sized title and dark, lightly outlined tab container.
- Toolbar order: Queue/History pills, auto-retry toggle, pause, more.
- Mixed-case labels; no auto-retry footer.
- Small inline retry glyph with a larger invisible hit area for implementation.
- Unboxed empty state directly on the page background.

Auto-retry and pause remain visible toolbar actions, superseding the v1 plan to
place auto-retry inside the overflow menu. This revision is still a mockup.
