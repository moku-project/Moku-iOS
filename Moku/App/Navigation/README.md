Root tabs and navigation composition live here.

The bottom navigation overlays the page with a translucent island and no opaque
footer. Main vertical scroll views use separate content and indicator margins:
content can pass behind the island, the final item clears it by a small gap, and
the scrollbar ends 2 points above the island in both expanded and compact states.
The content margin remains constant during collapse to avoid changing scroll geometry.

The island expands to 336 × 60 points and compacts to 300 × 52 points, constrained
by available width. It sits 12 points lower into the bottom safe area, clamped to
the screen edge. Top spacing is 2 points. Popups float above without changing
page layout. Buttons retain at least 44-point targets. Reduce Transparency restores
an opaque island while the area around it remains clear.

Apply `tracksNavigationScroll()` to each page's main vertical ScrollView or List,
not horizontal carousels or menu scroll views. The active page shrinks navigation
after 24 points of downward travel and expands it after 12 points upward or at the
top. Scroll views disable edge bounce at app startup, so scrolling stops at content
boundaries. Navigation tracking also clamps offsets defensively; tab changes reset
the state. Open menus force expansion.
Animations respect Reduce Motion.
