# Native Home screenshots

Captured from the SwiftUI app on an iPhone 17 Pro simulator. These are actual app
screenshots, not generated mockups.

- `home-empty.png`: live empty-state layout with four neutral carousel slots.
- `home-empty-stats.png`: empty activity, streak, and statistics.
- `home-sample.png`: populated layout using explicit debug-only sample history.
- `home-sample-stats.png`: sample-history statistics and media breakdown.

Sample covers use the same neutral fallback as failed/missing cover URLs. No
sample reading records or cover artwork are inserted into production storage.
The first-visit concept from the earlier generated board was superseded by the
user's requested gray templates and desktop-style empty copy.

The Home UI and local store are implemented. A future reader/library integration
must supply session updates, saved titles/chapters, cover URLs, and the resume
handler. The app's real Home stays empty until it has reading history.
