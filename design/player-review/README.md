# Video player mobile mockups

First review board: player-mobile-v1.png. Generated with the built-in imagegen tool; full prompt in prompt-v1.txt. Design mockups only, no application changes.

Reference: Moku/docs/screenshots/Moku-AnimeViewer.png and desktop AnimePlayer.svelte / MediaChrome.svelte.

States: landscape playback, landscape subtitle popover, portrait playback. Preserve inset charcoal toolbars, thin borders, sage timeline, episode navigation, subtitle access, speed and volume controls. Portrait wraps the timeline and transport controls into two rows.

Implementation fidelity notes: use the source labels Language, Text size, Height, and the Background Box/Shadow button (the generated board simplifies these). Fit the original video at its actual aspect ratio without cropping; image generation approximates frame geometry. Validate 44pt touch targets and device safe areas in native implementation.
