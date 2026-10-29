# Extensions — Library-aligned concept review

2026-09-21. Design exploration only; no application UI changes.

The live Library screenshot is the visual source of truth, replacing older references. Proposed views: Installed, Browse, Repositories. Reuse Library’s content tabs, view controls, spacing, icon scale, floating navigation and radial tools. Keep catalog rows flat; move search and filters into the tools flow. Preserve repository management, source settings, install/update/uninstall, and filters in the eventual implementation.

`library-reference.png`: current Library captured from Simulator.
`extensions-before.png`: current Extensions captured from Simulator.
`concept-prompt.txt`: exact prompt for built-in image generation.
`extensions-library-concepts-v1.png`: AI-generated mockups for discussion; sample catalog content, not live state or implemented screens.

## Implemented refinement

The approved direction is implemented in ExtensionsView. Library's actual ViewIconRail and LibraryRadialMenu are reused. Each row exposes only a three-dot native menu; configure/update/install and repository rename/refresh appear inside it. Uninstall/remove uses native trailing swipe actions. Logos are 64-point Dynamic Type-scaled squares without app-added backgrounds, padding, or rounded clips. Search/filters move into the tools sheet. Final UI review is left to the user.
