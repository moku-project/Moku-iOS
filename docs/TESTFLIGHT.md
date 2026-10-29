# TestFlight release checklist

What is already done in the repo, and the manual steps left for the account
holder. Nothing here has been uploaded, and no signing credentials were changed.

## Current state (branch `testflight-ready`)

| Item | Value |
| --- | --- |
| Bundle ID | `com.moku.app` (tests: `com.moku.app.tests`, `com.moku.app.uitests`) |
| Version / build | `0.1.0` (`1`) in `Configuration/Base.xcconfig` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`) |
| Minimum iOS | 18.2, iPhone + iPad, arm64 only |
| Signing | Automatic, team `7D6BVN4W87` (set in `project.yml`) |
| App icon | Single 1024×1024 universal PNG, no alpha (`Moku/Resources/Assets.xcassets/AppIcon.appiconset`) |
| Launch screen | `UILaunchScreen` with the `LaunchBackground` colour (Midnight theme `#080808`) |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO` in `Configuration/Info.plist` |
| Privacy manifest | `Moku/Resources/PrivacyInfo.xcprivacy`: no tracking, no collected data; required-reason APIs declared |
| Usage strings | `NSFaceIDUsageDescription` (app lock), `NSLocalNetworkUsageDescription` (desktop sync). No camera, photos, location, contacts, microphone or tracking APIs are used. |
| Background modes | `audio` (anime playback and Picture in Picture), `processing` (`com.moku.app.maintenance`: library updates and the download queue while idle) |
| Bonjour | `NSBonjourServices`: `_moku._tcp` (finding Moku desktop on the local network) |
| Notifications | Local only (new chapters found in background updates), asked when the user turns that option on. No push. |
| Category | Books (`LSApplicationCategoryType`) |
| Release archive | `xcodebuild archive` (Release, `generic/platform=iOS`) succeeds; app bundle is about 210 MB before App Store thinning |

`127.0.0.1` in Release is intentional. The Go backend and the JVM sandbox run
inside the app process and talk over loopback with per-launch bearer tokens.
There is no development server URL in the app.

## 1. Build the native backend for device (one-time, slow)

The archive links prebuilt static libraries from `Services/.build` (git-ignored).
On a fresh machine:

```sh
./moku-ios doctor
./moku-ios backend all --platform device     # OpenJDK + Go + sandbox jar + FFmpeg; ~30–60 min cold
```

On this Mac the OpenJDK build tree is kept in
`Services/preserved-build-sources/openjdk-source-2026-09-24` and symlinked as
`Services/.build/openjdk-source`, so `./moku-ios backend package-jvm --platform device`
is enough. **Run `./moku-ios backend inputs` first.** `package-jvm` silently
produces a `libopenjdk.a` without libffi when `Services/.build/libffi-device` is
missing, and the device link then fails with undefined `_ffi_call`.

The submodule `vendor/Tsunagu` points at commit(s) on the local
`testflight-ready` branch of the Tsunagu fork. **Push that branch to
`kannachi323/Tsunagu` before anyone else clones Moku-iOS**, or the submodule
commit will not resolve.

## 2. App Store Connect record

1. developer.apple.com → Identifiers → register the App ID `com.moku.app`.
   If that ID is taken (it is a generic name), pick another one, e.g.
   `io.github.kannachi323.moku`, and change `PRODUCT_BUNDLE_IDENTIFIER` in
   `project.yml`. Then run `./moku-ios generate`. Capabilities: none needed.
2. App Store Connect → Apps → **+ New App**: platform iOS, name "Moku" (if that
   name is taken use e.g. "Moku Reader"), primary language English, the bundle
   ID above, SKU `moku-ios`.
3. App Privacy → **Data Not Collected**. The app has no analytics. AniList and
   MyAnimeList sync only send data to those services when the user signs in.
   Desktop sync is peer to peer on the user's own network, to their own
   computer; no developer server is involved.
4. Age rating: answer the content questions honestly. Sources are user-added
   and can include mature content, so expect 17+.

## 3. Archive and upload

1. Bump `CURRENT_PROJECT_VERSION` in `Configuration/Base.xcconfig` for every
   upload (build numbers must increase).
2. Xcode → open `Moku.xcodeproj` → scheme **Moku** → destination **Any iOS Device (arm64)**
   → Product → **Archive**. Or from the terminal:
   ```sh
   xcodebuild -project Moku.xcodeproj -scheme Moku -configuration Release \
     -destination "generic/platform=iOS" -archivePath build/Moku.xcarchive archive
   ```
   (The verification run used `CODE_SIGNING_ALLOWED=NO`. Leave that off for a
   real upload so Xcode signs with your team.)
3. Organizer → select the archive → **Distribute App** → **App Store Connect** →
   Upload. Alternatively, export an `.ipa` and upload it with **Transporter**.
4. Wait for processing (10–30 min). An email arrives if any ITMS warnings come up.

## 4. Export compliance answers

`ITSAppUsesNonExemptEncryption` is `NO`, so App Store Connect should not ask.
If it does:

- Uses encryption? **Yes, only exempt encryption**: HTTPS/TLS through the OS,
  the Go standard library and the bundled JVM, plus PBKDF2 hashing of the local
  app-lock PIN (authentication). Desktop sync uses HTTP on the local network
  with a password session; no custom cryptography.
- Proprietary or non-standard algorithms? **No**.
- No French declaration or CCATS is needed.

## 5. TestFlight groups and beta review

- **Start with Internal Testing.** Up to 100 App Store Connect users. No
  Beta App Review is needed, so builds are usable minutes after processing.
- **External testing needs Beta App Review.** Expect pushback on:
  - **Guideline 2.5.2**: the app downloads extension packages (APK/JAR/JS)
    from user-added repositories and runs them in the embedded JVM and JS
    engine. That is the core of the app, and the main review risk.
  - **Guideline 5.2.3 / 1.4**: a content aggregator that can reach
    third-party sites. The app ships with **no** default repositories or
    sources. Keep it that way.

Suggested Beta App Review notes:

> Moku is an open-source reader (Apache-2.0, github.com/moku-project/Moku-iOS)
> for manga, light novels and video that the user already has access to. The app ships with no
> content and no content sources. To test without adding any third-party
> source: tap the gear icon → Storage → Import local file, pick a CBZ/EPUB/MP4
> from Files, then open it from the Library. Moku does not host or distribute content.
> No account is required.

Test information for testers: "Add a repository URL in More → Extensions →
menu → Repositories, install a source, then Search. To sync with Moku on your
computer, turn on Settings → Auth → Phone sync there (needs a server
password), then connect in the app's Settings → Sync."

If Beta App Review asks about the background modes: `audio` keeps anime
episodes playing with the screen locked and in Picture in Picture;
`processing` lets the app finish the user's download queue and check their
library for new chapters while the phone is idle. Both are user-initiated
features, and background updates are off by default.

## 6. Before tagging a build

- [ ] `./moku-ios test unit` passes. Known: `SettingsParityTests.appLockPersistsPinAndLimitsWrongAttempts`
      fails when the CLI builds the simulator test host unsigned (`CODE_SIGNING_ALLOWED=NO`), because there
      is no keychain entitlement. Run it from Xcode with signing on.
- [ ] `./moku-ios test acceptance` passes (52/52 on 2026-10-28)
- [ ] Launch on a real device: first launch starts the backend and Search shows sources
- [ ] Archive from a clean checkout with the submodule pushed

## Known issues at hand-off (2026-10-28)

- **Cold start.** The source runtime (interpreter-only JVM) takes about 10–20 s to come up on the
  first Search or details visit. Skeletons cover it, but testers should be told.
- **Anime with real sources** was not verified end to end: no anime extension was installed
  on the test device. Playback was verified with the bundled fixture streamed through the
  embedded backend (`--ui-testing-player --ui-testing-player-streaming --ui-testing-isolated-backend`),
  plus the acceptance suite's MP4/HLS/subtitle checks.
- **Upstream drift.** Tsunagu `upstream/main` is about 60 commits ahead of the iOS fork. Only
  source-compatibility fixes were cherry-picked; see the `testflight-ready` branch log.

## Desktop sync

- Requires the desktop build from the `Moku` repo's `testflight-ready` branch: Settings →
  Auth → Phone sync. That branch hasn't been built or run yet (see the ledger).
- The pairing is kept in the Keychain. **Unsigned simulator builds have no Keychain
  entitlement**, so there the pairing lasts only until the app quits. Signed builds keep it.
- Tested end to end on the simulator against a Tsunagu server on this Mac. Bonjour
  discovery between two real machines hasn't been tested.

## Layout coverage

Checked on simulators on 2026-10-28:

| Screen | iPhone 17 Pro | iPhone SE (3rd gen) | iPad (A16), portrait |
| --- | --- | --- | --- |
| Library (empty) | ✅ | ✅ | ✅ |
| Search / discovery shelves | ✅ | – | – |
| Series details + chapter list | ✅ | – | – |
| Manga reader | ✅ (real MangaDex pages) | ✅ (fixture) | ✅ (fixture) |
| Anime player | ✅ (fixture via embedded backend) | ✅ (fixture; controls auto-hidden) | – |
| Home, Downloads, Recent, Tracking, About, Settings | ✅ | – | – |

**Not verified. Check on a device or in Xcode Previews before inviting external testers:**
- Picture in Picture (the simulator reports it isn't possible for the fixture stream), lock-screen
  controls, and background audio with the screen off.
- Background updates/downloads (`BGProcessingTask`): trigger with the debugger,
  `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.moku.app.maintenance"]`.
- The novel reader with a real LNReader source; the light themes across all screens.
- Every "–" above, especially Search shelves and Details on the 375-pt-wide SE (long titles,
  three-across cover shelves) and iPad multitasking (Split View / Stage Manager at compact width).
- Landscape on iPhone and iPad (both are enabled in Info.plist).
- Light and system themes (`Settings → Appearance`). Only the default Midnight (dark) theme was checked.
- Large Dynamic Type sizes. Settings rows switch to a stacked layout below 300 pt (`GeneralRow`), but the shelves and
  the reader chrome were not checked at accessibility sizes.

Size-class reasoning: content pages are full-width stacks with `maxWidth: 640` for forms
(About, app lock). The tab bar and reader/player chrome are centred overlays, so the main
iPad risk is wide empty margins rather than clipping. On the SE, the risk is truncated titles in
the three-column shelves.
