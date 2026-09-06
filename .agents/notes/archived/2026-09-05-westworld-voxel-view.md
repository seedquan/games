# A rotatable voxel presentation without new dependencies

- **Status:** archived
- **Date:** 2026-09-05
- **Category:** rendering architecture

Superseded by `../implemented/2026-09-05-westworld-mini-island.md`.

## Decision

Default to a solid voxel-style town, with the prior 2D pixel view still available
through an explicit selector. Add a small software renderer rather than a CDN,
model service, WebGL dependency or cross-project dependency on terrarium.

The new module builds actual cuboids and pitched-roof geometry. An orthographic
camera projects them onto a Canvas 2D surface. Shaded visible faces, a raised
ground slab, foliage and voxel residents provide depth. A logical-resolution
depth buffer resolves solid geometry per pixel, then scales it with pixel
smoothing disabled. Face-average painter ordering was insufficient: wall tops
could cover parts of pitched roofs and incorrectly obscure nearby residents.

The same camera projects the buildings' real-button hit regions, resident
positions, movement keyframes and overhead speech captions. Mouse dragging
orbits and changes elevation; buttons provide keyboard/touch rotation. Shift
plus dragging pans the zoomed viewport. Full view resets both camera and zoom.

## Invariants

- Rendering receives only the existing visible-scene projection. Hidden crop,
  shelter changes, residents and private memories are not passed to geometry.
- Walking samples already-committed motions on the real road routes. It never
  creates decisions, advances time, changes saves or starts inference.
- Draw once on changes and while a bounded movement remains active. Do not
  maintain an idle animation loop. Switching to 2D cancels pending 3D frames.
- Theme colors come from the existing CSS variables, including pixel-buffer
  colors resolved through the browser's own color parser.
- Unsupported canvas is visibly reported; the 2D scene remains usable.
- Keep the inner map's `overflow: clip` invariant and HTML interaction labels.

The build now joins five browser modules. No dependencies or server changes
are needed. This is an orthographic software-rendered 3D view, not a new physics
engine or photorealistic scene. The existing live bridge serves the rebuilt
artifact without restarting or resetting its request budget.

## Coverage

Focused cases cover camera bounds/elevation, face geometry, per-pixel occlusion,
private-scene projection, exact projected motion endpoints, finite redraw
lifecycle, camera controls and explicit 2D fallback. Isolated Chrome exercises
orbit/pan/zoom, public drops, model-wait captions, successful dialogue, reduced
motion, mobile layouts and the preserved 2D option using mock decisions only.
