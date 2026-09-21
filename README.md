![Moku for iOS](docs/banner.png)

[![Release](https://www.shieldcn.dev/github/release/moku-project/Moku-iOS.svg?variant=outline&size=default)](https://github.com/moku-project/Moku-iOS/releases/latest)
![GitHub Downloads](https://www.shieldcn.dev/github/downloads/moku-project/Moku-iOS.svg?variant=outline&size=default)
[![Stars](https://www.shieldcn.dev/github/stars/moku-project/Moku-iOS.svg?variant=outline&size=default)](https://github.com/moku-project/Moku-iOS)
[![Discord](https://www.shieldcn.dev/discord/members/x97hj8zR72.svg?variant=outline&size=default)](https://discord.gg/x97hj8zR72)

# Moku for iOS

Moku is a fast, minimal manga, novel and anime app. This is the native SwiftUI port of [Moku desktop](https://github.com/moku-project/Moku) for iPhone and iPad, with the same design direction and controls adapted for touch. The app bundles Tsunagu and runs it on-device.

> In development. Desktop feature parity is still in progress.

---

## Screenshots

Coming soon.

---

## Features

Coming soon.

---

## Installation

### iPhone and iPad

Build from source using the development instructions below. Select your device in Xcode and configure your own signing team before installing.

Physical-device runtime verification is still in progress.

---

## Requirements

**iOS 18.2 or later.** iPhone and iPad are enabled as build targets.

The app bundles and starts Tsunagu automatically. No separate server or Java installation is needed on your device. Add a source repository and install extensions from the app to get started; nothing is preinstalled.

---

## Development

**Prerequisites:** an Apple Silicon Mac, Xcode, XcodeGen, Go, Python 3.12+, and a JDK 25 boot compiler.

The `moku-ios` Swift tool is included in this repository. No separate install is needed.

```sh
git clone --recurse-submodules https://github.com/moku-project/Moku-iOS
cd Moku-iOS
./moku-ios doctor
./moku-ios dev
```

The CLI prepares the backend, launches Simulator, and watches for changes. Use `./moku-ios run` for a single build and launch, or `./moku-ios test` to run unit tests.

See the [architecture and codebase walkthrough](ARCHITECTURE.md) for feature ownership, MVVM, and the test layout.

For Xcode development, open `Moku.xcodeproj` and select the **Moku** scheme. Build requirements and native runtime details are documented in `FRONTEND.md` and `services/README.md`.

---

## Stack

| | |
|---|---|
| Swift 6 + SwiftUI | Native interface |
| Tsunagu | Embedded Go/JVM backend |
| XcodeGen | Xcode project generation |
| moku-ios (Swift) | Builds, Simulator and tests |

---

## Community

Questions, feedback, or just want to hang out — join the Discord.

[![Discord](https://www.shieldcn.dev/discord/members/x97hj8zR72.svg?variant=secondary&size=large)](https://discord.gg/x97hj8zR72)

---

## License

Distributed under the [Apache 2.0 License](./LICENSE).

---

## Disclaimer

Moku does not host or distribute any content. The developers have no affiliation with any content providers accessible through connected sources.
