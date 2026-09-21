# Native manga reader

Production entry: tap a manga chapter in Search/Library title details. The
reader uses public `chapter { pages }`, authenticated content requests,
`updateReadingProgress`, `enqueueDownload`, `startDownloader`, and the chapter-open
automation event. Source headers/cookies stay inside the embedded content proxy.

The drawer preserves desktop Manga Settings: Single/Double/Auto/Strip, offset
spreads, page gaps, automatic chapter advance and scrolling/speed, None/Fade/Slide/
Turn transitions, Width/Height/Screen/1:1, direction, 10–100% base zoom/reset,
contrast, optional native pinch inspection, mark-read-on-advance, per-manga
settings, and save/apply/rename/delete presets. Behaviour adds auto-mark-read,
auto-bookmark and 0–10 pages of prefetch. Bars can dock top/left/right; containerized
view leaves the surrounding app navigation available. Global Reader settings are
also available from Settings, using the same panel.

Desktop source is authoritative: `ReaderPresetPanel.svelte`, `ReaderProgressBar.svelte`,
`ReaderControls.svelte`, `ReaderSettings.svelte`, `mangaReader.svelte.ts`, and
`pageLoader.ts` at desktop commit ee54dbb6d37be4c574933a569134f3a7bb53778b.
Double layout keeps the first page alone; offset adds a second lone page before
pairing. Auto switches at viewport width/height > 1.25. Mobile Turn uses UIKit's
page curl rather than porting desktop DOM peel geometry.

Page transfer/decode tasks belong to the canvas and cancel when pages leave its
window or the reader closes. Decoding happens off the main actor, with 2048-pixel
thumbnails and bounded prefetch, at most three transfers concurrently. Source
pixel dimensions remain available for 1:1 geometry; high-resolution inspection is
limited by the decoded thumbnail. Auto-scroll stops during direct manipulation,
while drawers are open, and outside the active scene. It is resumed by a page jump
or by toggling auto-scroll. Failed pages retry on tap; chapter failures expose retry.

Preferences, resume positions and bookmarks use the active profile's UserDefaults
suite. Progress writes are serialized and completion is sticky, with a flush on
close/background. A failed sync is reported; local page position remains saved.
Downloads show explicit queue failures. The backend owns actual transfer work.

`--ui-testing-reader` launches deterministic local numbered image fixtures only
in DEBUG; `--reader-keep-preferences` verifies restart persistence. These fixture
screenshots are UI verification, not evidence of live provider availability.
The novel reader is separate and is not implemented by this manga reader change.
