# App structure

Start with the feature you are changing. Read its screen, its ViewModel, and then
its data contract. Follow the contract to its implementation only when you need
to understand storage or backend behavior.

```text
Moku/
  App/                 Launch, profile session lifetime, dependency selection
    Navigation/        Root, tabs, navigation bar, destination routing
  Features/
    Home/
    Library/           Includes Components, Folders, and Domain
    Search/            Includes Components and Data (search history)
    Details/           Shared title-detail screen, independent of Search UI
    Reader/            Includes Components, Canvas, Domain, and Data
    Player/            Includes Components, Domain, and Data
    Downloads/         Includes Components and Domain
    Recent/            Includes Components, Domain, and Data
    Tracking/          Includes Components, Domain, and Data
    Extensions/        Includes Components, Sources, Domain, and Data
    Profile/
    Settings/          Includes Components, Domain, and Data
  Shared/
    Media/             Search/detail contracts and shared media values
      Domain/
      Data/
    Profiles/          Profile identity, selection, and preference rules
    Library/           Profile-local saved titles, folders, and library search
    Activity/          Persistent reading/watching activity used across screens
    Components/        Reusable controls, headers, covers, popups, skeletons
    Theme/             Colors, surfaces, and Phosphor icons
    Backend/           Embedded service lifetime and authenticated API transport
    Cache/             Image pipeline and resource cache
    Storage/           Generic JSON document storage
  Preview/
    Fixtures/          Shared Debug-only sample data
    Repositories/      Debug-only fake repositories
  Resources/           Asset and string catalogs
Tests/
  Features/            Unit tests grouped by feature
  Shared/              Unit tests for shared stores and infrastructure
  Support/             Unit-test helpers
  Fixtures/            Test fixture guidance
  UI/                  XCTest app automation, separate UITests target
```

## What Domain means

Domain holds the concepts and contracts a feature works with: for example,
`LibraryItem`, `ReaderPosition`, and `ReaderRepository`. It is independent of SwiftUI,
UIKit, and the embedded backend. Repository protocols describe operations without
choosing storage or transport. Data implements those operations.

Shared domain types belong in `Shared/Media/Domain` when multiple features consume
them. Feature-only types stay inside the feature. Do not create empty Domain/Data
folders or a protocol for every helper. Screen-only choices can remain with their
screen or component.

These folders are part of one Swift app module; they do not create namespaces or
compiler-enforced module boundaries. Keep useful feature prefixes on Swift types,
use internal access by default, and leave implementation details private. Introduce
packages only when a concrete ownership, testing, or reuse need justifies them.

## MVVM and component ownership

A feature's main View and ViewModel sit at its top level. Components contains real
child views or focused view modifiers, not fragments of a giant View extension.
A ViewModel coordinates asynchronous actions and screen state. A store persists
shared data. Existing stores such as `HomeStore` remain stores, not ViewModels.
Simple screens and controls do not need an otherwise-empty ViewModel.

Use values for display, bindings for editable state, and callbacks for user intent.
Keep expansion/focus state local. Keep navigation, search tasks, playback, and
profile state at their existing lifetime owners. SwiftUI identity affects when
state resets; moving a declaration can change behavior even if the UI looks the same.

Examples:

- Library owns mode, search presentation, selection, and its screen model.
  `LibraryFolders` owns folder UI drafts/focus, while `FolderViewModel` validates
  and saves through `ProfileLibrary`.
- Recent owns navigation and expanded IDs. `HistoryList`, `HistoryRow`, and
  `UpdateList` render their inputs and send navigation actions back to Recent.
- Player owns playback lifetime, menu selection, and scrub state. `PlayerControls`
  and `PlayerMenu` render controls without starting a second player.
- `TrackingDraftStore` performs disk I/O on its actor. The ViewModel queues snapshot
  writes in order; `flushDraft()` waits for persistence when a workflow must finish
  durably, including before an import returns.

A file approaching 300 lines merits a responsibility review, not an automatic
split. Native coordinators and cohesive screens can be longer. Prefer specific
names such as Components, Backend, and Cache over a generic Utils directory.

## Walk through a user journey

1. `App/MokuApp.swift`: launch and development-only entry points.
2. `App/ProfileHostView.swift` and `ProfileSessionView.swift`: profile state and
   `.id(profiles.activeID)`, which replaces the session on profile changes.
3. `App/Navigation/RootView.swift`: tabs, account navigation, search, and details.
4. `Features/Search/SearchView.swift` → `SearchViewModel.swift` →
   `Shared/Media/Domain/SearchRepository.swift` →
   `Shared/Media/Data/LiveMediaRepository.swift` → `Shared/Backend/BackendAPI.swift`.
5. `Tests/Features/Search/SearchModelTests.swift`: cancellation, filtering, and
   debounce behavior that must remain stable.

Ask who owns the state, who changes it, where the side effect happens, and how
cancellation or failure is reported. Read the matching tests before changing that
contract.

## Builds and tests

`project.yml` is the XcodeGen source of truth. After adding/moving Swift files,
run `./moku-ios generate` and build. The generated Xcode project remains checked in.

Unit tests and UI tests share a filesystem parent but remain separate Xcode targets:
`Tests` excludes `UI/**`; `UITests` includes only `Tests/UI`. Target names and scheme
entries remain unchanged, so `./moku-ios test unit` and `./moku-ios test ui` still work.

Reusable preview fixtures are Debug-only. Focused `#Preview` declarations and
reader/player preview hosts stay beside the features they demonstrate.

The services, vendor checkout, scripts, and build configuration retain their roles.
Do not move generated backend archives or upstream source into app feature folders.

## Refactor verification

The structure refactor was checked with Debug and Release simulator builds,
81 passing Swift Testing tests (two opt-in device XCTest cases skipped), Swift
formatting, and seven passing CLI tests. Reader's two UI tests, Player's portrait/
landscape controls test, and General Settings' persistence/scaling test passed.

The broader UI run is not green: XCTest sometimes resolves visible controls to
an off-screen tap point, and some Library menu queries have duplicate identifiers.
The navigation and new-folder tap failures were reproduced using the pre-refactor
source on the same simulator. Library mode tabs passed once and failed on a later
run with the same off-screen tap symptom. Treat these as remaining UI verification
limitations; do not equate passing unit tests with complete UI coverage.
