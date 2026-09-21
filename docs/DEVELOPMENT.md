# Development notes

See the [architecture walkthrough](../ARCHITECTURE.md) for folder ownership, then
[frontend setup](../FRONTEND.md) for build requirements and Swift conventions,
and [backend services](../services/README.md) for native runtime setup.

## Preview-first UI iteration

Open the app project in Xcode, select the Moku scheme and an iPhone simulator,
then open a SwiftUI file and show Editor > Canvas. Use legacy previews where supported; see [Canvas compatibility](../FRONTEND.md) for runtime limitations.
Keep the canvas open while editing; Xcode handles preview compilation and refreshes.
An initial build or a preview rebuild can still be necessary after structural changes.

Focused previews live alongside their views:

- `PageHeader.swift`: shared title and icon proportions.
- `LibraryPreview.swift`: empty Library, view dropdown, layout toggle, and radial menu.
- `DownloadsView.swift`: empty, active, failed, and completed sample downloads.
- `RootView.swift`: More index (destination content is a preview placeholder).
- `HomePreviewData.swift`: existing empty and populated Home previews.

Library previews use a temporary library directory and separate preview preferences.
Use previews for visual iteration; run `./moku-ios run` when ready to check the integrated
app. Avoid `./moku-ios dev` during this workflow because it watches edits and rebuilds.
Previews do not replace checking real navigation, persistence, or backend behavior.
