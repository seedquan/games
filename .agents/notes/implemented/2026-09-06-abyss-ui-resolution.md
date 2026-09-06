# Abyss independent UI resolution

Status: enabled by default after browser comparison; `?sharpUI=0` retains the single-canvas fallback.

The adaptive world raster budget can reduce ultrawide backing resolution below
one pixel per CSS pixel. That also softens HUD text and menus. An independent
transparent canvas now draws HUD, menus, touch controls and opt-in review panels
at a separate density, while the world retains its measured adaptive budget.

The UI canvas uses pointer-events:none, so existing input coordinates/listeners
remain on the world canvas. All UI drawing still uses CSS coordinates. Density
is bounded by device DPR, 1.5x, and 8 million pixels (32 MiB RGBA backing maximum,
excluding browser overhead). The renderer selects world context at frame start,
selects/clears the UI context after the world post-processing, and restores the
world context at frame end. No UI canvas is created with the explicit fallback query.

24 focused checks pass. The added check covers independence from world DPR,
retina budget limits, transform/clear coordinates and the disabled path. Inline
syntax, whitespace and offline checks pass. Pages browser A/B must verify text,
menu input, layering and frame cost before enabling this by default. This alone
does not improve world character resolution or establish production acceptance.


Browser acceptance on f583cc8: at a 3440×1440 viewport, the independent UI is
3440×1440 while the adaptive world is smaller. HUD, pause and Build Overview
text are visibly sharper; clicking Build Overview through the overlay works.
The 240-frame hub sample was 60 FPS / P95 18.2 ms. A first-room sample with 9
active enemies at 1280×720 was 60 FPS / P95 17.8 ms (122 frames). On ultrawide,
startup at 1.5 MP dropped to 41.2 FPS; after adaptation to 1514×634, a separate
8-enemy active combat sample reached 60 FPS / P95 18.1 ms (121 frames). These are
short first-room samples, not a Boss/mobile performance claim. No console errors.

The 390×844 layout check exposed existing overflowing pause instructions. Compact
pause layouts now use short Chinese hints, 44px targets and two columns when
height is below 560px. The world-space terminal labels remain a separate issue.
25 focused checks pass, including compact target bounds for portrait/landscape.
