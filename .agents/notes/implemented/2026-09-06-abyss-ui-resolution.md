# Abyss independent UI resolution

Status: implemented behind `?sharpUI=1`; performance acceptance pending.

The adaptive world raster budget can reduce ultrawide backing resolution below
one pixel per CSS pixel. That also softens HUD text and menus. An independent
transparent canvas now draws HUD, menus, touch controls and opt-in review panels
at a separate density, while the world retains its measured adaptive budget.

The UI canvas uses pointer-events:none, so existing input coordinates/listeners
remain on the world canvas. All UI drawing still uses CSS coordinates. Density
is bounded by device DPR, 1.5x, and 8 million pixels (32 MiB RGBA backing maximum,
excluding browser overhead). The renderer selects world context at frame start,
selects/clears the UI context after the world post-processing, and restores the
world context at frame end. No canvas is created without the flag.

24 focused checks pass. The added check covers independence from world DPR,
retina budget limits, transform/clear coordinates and the disabled path. Inline
syntax, whitespace and offline checks pass. Pages browser A/B must verify text,
menu input, layering and frame cost before enabling this by default. This alone
does not improve world character resolution or establish production acceptance.
