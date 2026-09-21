# Player regression coverage

Run both the model and UI suites from the Moku scheme:

```sh
./moku-ios build --platform simulator
xcodebuild -project Moku.xcodeproj -scheme Moku \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .build/frontend CODE_SIGNING_ALLOWED=NO \
  -only-testing:Tests/PlayerTests -only-testing:UITests/PlayerUITests \
  -parallel-testing-enabled NO test
```

For hardware, build with `./moku-ios build --platform device`, use the connected
phone's destination, and supply the project's signing team instead of disabling
signing. Run tests with the phone unlocked and resting untouched. Close floating
picture-in-picture windows first: system overlays can intercept the synthetic
taps. Rotation helpers wait for stable app geometry before touch gestures.

The original local MP4 fixture covers layout, subtitles, menus and accessibility
slider adjustment. The streaming fixture starts the real embedded JVM and Go
backend in a disposable database, imports three synthetic video episodes, and
plays through the production authenticated HTTP content endpoint. Progress saves
also use the production repository. Subtitle text and alternative source labels
are deterministic test data; no third-party source availability is required.

The streaming test delivers SIGPIPE and SIGXFSZ after runtime startup. Before the
OpenJDK patch, SIGPIPE reproducibly aborts in `os_bsd_zero.cpp:92`, matching the
phone crash. The patch handles these ignored signals before accessing the
unimplemented Zero instruction context, preserving signal chaining.

The timeline reserves a 44-point touch surface and accepts track taps/drags,
including touches that begin beside the moving thumb. UI tests use coordinate
taps and drags, including playing/paused seeks,
portrait/landscape, source changes, play/pause, mute, speed, captions, control
visibility, episode selection and dismissal. Model tests cover invalid times,
bounded seeks, paused source changes and a late extraction result after closing.

This does not establish compatibility with every third-party HLS playlist,
codec, subtitle format or unavailable upstream server. Validate a live episode
when modifying extraction or remote streaming behavior.
