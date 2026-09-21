# Persistence and read performance

The embedded Go backend already stores its database in Application Support at
`Backend/tsunagu.db`. SQLite uses WAL, foreign keys, a busy timeout and migrations.
It owns source metadata, titles, chapters, downloads, app settings and reading/watch
progress. Native profile manifests, profile libraries/organization and Home history
use actor-serialized JSON documents; preferences and reader positions also use
profile-specific UserDefaults. Search queries live in a profile-local SQLite database
at `Profiles/<profile-id>/search-history.sqlite`, independent of the source runtime.
Successful searches are trimmed, deduplicated case-insensitively, ordered by recency,
and limited to 30 entries. Cancelled searches are not recorded. The search page can
repeat a query, remove one entry, or clear the active profile's history.

Disposable caches:

- GraphQL reads are opt-in: installed sources 30 seconds, searches 60 seconds,
  title details 120 seconds, reader page lists 60 seconds. Responses also persist in
  `Library/Caches/Moku/Results-v1` with a 32 MiB disk limit and the same expiry.
  The 8 MiB memory cache
  shares in-flight requests. All GraphQL mutations invalidate these reads before
  and after writing; explicit chapter refresh bypasses prior entries. Errors are
  not cached. Abandoned searches cancel their loader when no consumer remains.
- Covers use canonical relative proxy paths, never session ports or credentials.
  Encoded artwork has a 24 MiB memory budget and a 128 MiB disk budget in
  `Library/Caches/Moku/Covers-v1`, with seven-day expiry and oldest-use eviction.
  Cache IO failures fall back to loading normally. Settings → Storage → Clear cache clears cover/result caches and skeleton visit state
  and includes disk covers in storage usage.
- ImageIO downsamples covers to at most 600 pixels on their longest side away
  from the main actor. Prepared images share a 48 MiB NSCache; off-screen views
  release their image references. The first twelve search/library covers are
  prefetched, at most three per batch; cover HTTP connections are limited to four
  and use a separate session from metadata requests.
- Source searches run at most three concurrently and preserve source order and
  explicit failure behavior. Existing reader page prefetch remains bounded at
  three transfers with a decoded-memory budget. Playback URLs/progress responses
  are not cached by the new metadata cache.

`CacheTests` covers coalescing, hits, expiry, failures, cancellation, invalidation
of in-flight work, LRU eviction, disk persistence/budget, bounded ordered fan-out
and thumbnail resolution. SearchModel/SearchStartup/LibrarySearch regression
suites cover existing search behavior. First-time extension/JVM startup and
upstream latency remain possible; no device latency improvement has been measured.
