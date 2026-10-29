# Settings and Profile implementation

Actual iPhone 17 Pro simulator screenshots captured by SettingsProfileTests.

- settings-general.png: source language, animation preference, source management links.
- settings-appearance.png: live Sepia theme, solid surfaces and cover fitting.
- settings-library.png: collection, layout, chapter order, and history controls.
- settings-storage.png: real storage totals, shared cover cache, preference reset.
- profile.png: compact identity and device-local profile switcher.

The UI uses 13-point row titles, 11–12-point supporting text, and the existing
22-point centered page heading. Interactive rows retain comfortable tap targets.
The source runtime and its extension preferences are shared. Saved-title membership,
Home activity, and app preferences are isolated by local profile UUID. Existing
Home history is retained for the default profile. Tsunagu server authentication
is not a multi-user profile system, so these local identities do not use auth tokens.

Validation: 15 model tests and 2 UI tests passed in moku-settings-profiles3.xcresult;
simulator and signed iPhone builds succeeded. Tests use isolated profile data.

## Section index revision

Settings now opens a plain vertical list of all 16 desktop sections in desktop
order, including the reserved iOS sections. `settings-sections.png` shows the new
index. Each row opens a pushed page with a centered title and a Back to Settings
button; `settings-general.png` and `settings-reserved-section.png` show examples.
Supported controls and per-profile persistence are unchanged. The horizontal
category strip has been removed.
