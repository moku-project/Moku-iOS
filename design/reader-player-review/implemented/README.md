# Implemented manga reader — simulator verification

Captured September 20, 2026, on iPhone 17 Pro / iOS 26.5 simulator.
These are screenshots of the implemented SwiftUI/UIKit app, using deterministic
numbered page fixtures rather than a live manga provider.

- [Reading view](reader-reading.png): Phosphor Sliders and plain arrow navigation.
- [Settings drawer](reader-settings-layout.png): desktop layout/transition/fit tiles and zoom slider.
- [Presets and behaviour](reader-settings-presets.png): persisted reader settings.
- [Landscape drawer](reader-landscape-drawer.png): double spread and offset controls.

## Verification

The final build and targeted acceptance run passed: 8 ReaderTests unit tests and
2 ReaderUITests, with zero failures. The UI checks cover portrait/landscape,
chapter selection, direction, page navigation, bookmarks, drawer settings, presets,
and settings/page restoration after terminating and relaunching the app.
The unit checks cover persistence, desktop spread grouping, progress/completion,
download routing, errors, corrupt image rejection, bounded image decoding, and
all 98 bundled Phosphor icon names in three weights.

Result: `services/.build/reader-app/Logs/Test/Test-Moku-2026.09.20_10-49-23--0700.xcresult`.
All three NavigationTests also passed in the earlier 10:27:09 result. An earlier
reader UI timing failure was fixed by waiting for the drawer's slide animation
before tapping its moving layout tile; both reader UI tests passed in the final run.

Source audit found no app-authored `systemName:`, `systemImage:`, or `symbolEffect`
uses. System-owned controls retain their native platform glyphs.

Production reader actions use the embedded backend, but these fixture tests do
not verify live providers, physical-device memory/performance, or complete offline
service behavior. Native page curl differs from desktop DOM peel, and image decode
is capped at 2048 pixels per dimension. This change implements the manga reader;
a novel reader is separate. See `Moku/Features/Reader/README.md` for implementation
contracts and behavior.
