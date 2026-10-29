# Implemented iOS video player

Native SwiftUI chrome around an aspect-fit AVPlayerLayer. Screenshots are from the
passing iPhone 17 Pro Simulator UI test, using a generated 24-second grid video
and sample subtitle data. They are actual app screenshots, not imagegen outputs.

- Landscape: inset charcoal header and single-row playback bar, sage scrubber.
- Portrait: compact two-line header and stacked timeline/transport bar.
- 44pt control targets, safe-area margins, reduced-motion/transparency support,
  native accessible seeking, auto-hiding chrome (held open for VoiceOver/menus).
- Episode picker, previous/next, play/pause, seeking, speed, mute and source selection.
- External VTT/SRT subtitle selection, size, position and background settings.
- Loading/error/retry UI; saved progress/resume through the embedded backend.
- Closing and backgrounding pause playback; audio interruptions pause playback.

Anime episode rows in SearchDetailView open the player full screen. Manga rows
retain their reader destination. Production playback resolves `videoStream` and
`readingProgress` through GraphQL and uses the authenticated loopback content
proxy. Source credentials remain in the backend.

Validation: simulator build, four Swift Testing cases and one comprehensive UI
test passed (5/5). The UI test covers portrait/landscape, playback, subtitles,
sizing, seek, speed, mute, episode changes and dismissal. Swift formatting passes
for the new player and tests. See test-summary.json.

Boundaries: AVPlayer-compatible media only (e.g. supported MP4/HLS); DASH and
ASS/SSA rendering are not implemented. The custom subtitle picker currently
lists external tracks returned by videoStream, not embedded media-selection
tracks. Live extension streams and physical-device playback were not exercised
in this UI implementation pass. Subtitle markup is rendered as plain text.

Preview: Debug builds launched with `--ui-testing-player` show the deterministic
paused fixture. Normal anime episode launches use EmbeddedPlayerRepository.
